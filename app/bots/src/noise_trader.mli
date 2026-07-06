(** A small liquidity/noise bot used as supporting cast.

    On every tick it submits [orders_per_tick] [Day] orders per symbol, each
    on a random side and priced within [jitter_cents] of the current
    fundamental (buys bid up, sells offer down). Because instances quote
    around the same fair value, their orders overlap at the touch and cross
    frequently, producing a continuous stream of trades and top-of-book
    changes.

    It is {e not} a pathological bot. Its job is to keep the market busy so
    that market-data-driven scenarios have something to observe -- in
    particular [Jsip_scenarios.Slow_consumers], where the noise traders
    generate the market-data firehose that the slow consumers refuse to
    drain. Unlike the book filler, this bot deliberately crosses the book, so
    it does {e not} pile resting orders without bound.

    All randomness is drawn from
    {!Jsip_bot_runtime.Bot_runtime.Context.random} so a given RNG seed
    reproduces the same order flow. *)

open! Core
open! Async
open Jsip_types

module Config : sig
  type t =
    { symbols : Symbol.t list (** Symbols to trade. *)
    ; orders_per_tick : int
    (** Orders to submit {e per symbol} on each tick. The intensity knob;
        combine with the runtime's [tick_interval] to set the overall order
        rate, and hence how much market-data traffic is generated. *)
    ; jitter_cents : int
    (** Half-width, in cents, of the price band around the fundamental within
        which orders are placed. Small values (e.g. [10]-[50]) keep orders
        near the touch so they cross often; larger values spread quotes out
        and trade less. *)
    ; size : int (** Shares per order. *)
    ; next_client_order_id : int ref
    (** Monotonic per-order ID counter. Use {!create}, which allocates a
        fresh [ref] per instance. *)
    }
  [@@deriving sexp_of]

  (** Build a config with a fresh, private [client_order_id] counter. All
      fields are required and have no default except [first_client_order_id],
      which defaults to [1]. *)
  val create
    :  symbols:Symbol.t list
    -> orders_per_tick:int
    -> jitter_cents:int
    -> size:int
    -> ?first_client_order_id:int
    -> unit
    -> t
end

include Jsip_bot_runtime.Bot_runtime.Bot with module Config := Config
