(** A pathological bot that rapidly piles resting orders it never intends to
    fill.

    On every tick the book filler submits [orders_per_tick] new [Day] orders
    per configured symbol, each priced deep away from the fundamental (bids
    below, asks above) so they are never marketable and rest on the book
    indefinitely. Every order uses a fresh [client_order_id], so the exchange
    keeps accepting them and the book grows without bound.

    The target is the order book itself. Piling resting orders attacks:

    - {b Memory}: every resting order is a distinct entry in the book's
      per-side [Map], so RSS grows roughly linearly in orders submitted.
    - {b BBO / snapshot latency}:
      {!Jsip_order_book.Order_book.best_bid_offer} sums over an entire side
      (O(N)) and is recomputed by the matching engine before and after every
      submit and cancel, and {!Jsip_order_book.Order_book.snapshot} sorts the
      whole book (O(N log N)) on every book query and market-data send. Both
      get slower as the book grows. ({!Jsip_order_book.Order_book.find_match}
      is only O(log N) on the current [Map]-backed book, so it is the least
      affected of the three the exercise names -- see the design note in the
      PR.)

    A single filler is enough to grow the book unboundedly; running several
    in a scenario (each its own participant and RNG seed) just reaches a
    painful book size sooner. See [Jsip_scenarios.Book_fill]. *)

open! Core
open! Async
open Jsip_types

module Config : sig
  type t =
    { symbols : Symbol.t list
    (** Symbols to flood. Each gets [orders_per_tick] new orders per tick. *)
    ; orders_per_tick : int
    (** New resting orders to submit {e per symbol} on each tick. The primary
        intensity knob; combine with the runtime's [tick_interval] to set the
        overall fill rate. *)
    ; size : int
    (** Shares per order. Keep this small (e.g. [1]): the pathology is about
        the {e count} of resting orders, not traded volume. *)
    ; min_offset_cents : int
    (** Smallest distance from the fundamental at which to rest an order, in
        cents. Must be large enough that orders stay clear of the touch and
        never become marketable. *)
    ; max_offset_cents : int
    (** Largest distance from the fundamental, in cents. A wider [min, max]
        band spreads orders across more price levels, which grows the book
        snapshot as well as its size. *)
    ; next_client_order_id : int ref
    (** Monotonic counter for allocating fresh per-order IDs. Use {!create},
        which allocates a fresh [ref] per instance -- sharing one [ref]
        across instances would collide their ID streams. *)
    }
  [@@deriving sexp_of]

  (** Build a config with a fresh, private [client_order_id] counter. All
      fields are required and have no default except [first_client_order_id],
      which defaults to [1]. *)
  val create
    :  symbols:Symbol.t list
    -> orders_per_tick:int
    -> size:int
    -> min_offset_cents:int
    -> max_offset_cents:int
    -> ?first_client_order_id:int
    -> unit
    -> t
end

include Jsip_bot_runtime.Bot_runtime.Bot with module Config := Config
