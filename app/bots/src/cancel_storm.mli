(** A pathological bot that hammers the cancel path.

    On every tick, for each configured symbol, {!on_tick} runs
    [cycles_per_tick] submit-then-immediately-cancel cycles. Each cycle
    allocates a {e fresh} [client_order_id], submits one passive [Day] buy
    (priced [passive_offset_cents] below the oracle fundamental, so it rests
    rather than filling), and immediately cancels {e that} order — without
    waiting for the [Order_accept] to arrive on the session feed.

    The point is to stress three things at once: the cancel path, the
    submit/accept/cancel event flow, and the duplicate-[client_order_id]
    bookkeeping. The fresh ID per cycle is load-bearing: reuse an ID and the
    exchange's duplicate detection rejects every submit after the first, so
    the "storm" would die on cycle two. Because a fresh order is cancelled
    before its acceptance is even observed, the bot also exercises the
    cancel-a-possibly-unacknowledged-order case.

    Note the memory angle: the matching engine's per-participant
    [client_order_id] table is never cleared (a cancelled order keeps its
    slot to prevent ID reuse), so an endless stream of fresh IDs makes that
    table grow without bound even though the order book itself stays small.
    This bot therefore stresses memory as well as the cancel path.

    Contrast with a well-behaved client: this bot never intends to trade, and
    fires blindly rather than reacting to events ({!on_event} is a no-op).
    See {!Jsip_bots} and the [Cancel_storm] scenario under [app/scenarios/]
    for how a crowd of these is launched. *)

open! Core
open! Async
open Jsip_types

module Config : sig
  type t =
    { symbols : Symbol.t list
    (** Symbols to storm. One submit/cancel loop runs per symbol per tick. *)
    ; cycles_per_tick : int
    (** Number of submit-then-cancel cycles per symbol on each tick. The
        primary intensity knob; the wall-clock rate is this times the tick
        frequency the runtime is configured with. *)
    ; max_in_flight : int
    (** Ceiling on how many cycles run concurrently within a tick. Bounds the
        number of in-flight RPCs so the storm applies real pressure (cycles
        overlap instead of blocking one round-trip at a time) without an
        unbounded burst. A value of [1] recovers fully-sequential behaviour. *)
    ; size : int (** Shares per submitted order. *)
    ; passive_offset_cents : int
    (** How far below the oracle fundamental to price the buy, in cents.
        Large enough that the order never crosses, so it rests and is then
        cancelled rather than filling. *)
    ; next_id : int ref
    (** Monotonic cursor for allocating a fresh [client_order_id] each cycle.
        Allocated by {!create}, which gives every instance its own [ref] --
        sharing one across instances would collide their ID streams. It lives
        in the config because the {!Jsip_bot_runtime.Bot_runtime.Bot}
        interface hands the bot the same [Config.t] on every tick, so this
        [ref] is where the bot's only evolving state lives. *)
    }
  [@@deriving sexp_of]

  (** Build a config with a fresh, private [client_order_id] counter.
      [first_id] defaults to [1]. *)
  val create
    :  symbols:Symbol.t list
    -> cycles_per_tick:int
    -> max_in_flight:int
    -> size:int
    -> passive_offset_cents:int
    -> ?first_id:int
    -> unit
    -> t
end

include Jsip_bot_runtime.Bot_runtime.Bot with module Config := Config
