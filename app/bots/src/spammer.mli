(** A pathological load-generating bot.

    The spammer has no view on price and no interest in trading. On every
    [on_tick] it fires a burst of [orders_per_tick] order submissions in
    parallel, spread round-robin across its configured symbols — each a
    resting [Day] order priced far outside the market (a bid at $0.01, an ask
    at $10,000.00) so it never crosses resting liquidity and never fills. It
    ignores every event it receives.

    Behavior over time: with a tick every [t] and [n] orders per tick, the
    exchange sees a burst of [n] submissions arrive roughly every [t], and
    the book grows without bound because nothing the spammer sends ever
    leaves it. This is designed to stress the request queue / gateway
    dispatcher (one RPC to decode and route per order), order-book memory
    (every order rests forever), and subscriber-pipe bandwidth (every
    accepted order fans out as an event to all market-data / audit-log
    subscribers).

    Because its orders never fill, the spammer needs no counterparty; the
    {!Jsip_scenarios.Order_spam} scenario runs it solo and controls the
    intensity — how many spammer instances, and each instance's
    [orders_per_tick] and tick interval.

    This module satisfies {!Jsip_bot_runtime.Bot_runtime.Bot}. *)

open! Core
open! Async
open Jsip_types

(** Everything the {!Jsip_scenarios.Order_spam} scenario tunes when it wires
    up a spammer instance. There are no in-module defaults — the scenario
    supplies every field. The values the current scenario uses are noted
    below as a reference point. *)
module Config : sig
  type t =
    { symbols : Symbol.t list
    (** The symbols to spam. Each tick's burst is spread round-robin across
        this list, so with [n] symbols every book receives roughly
        [orders_per_tick / n] of the load. Must be non-empty — [on_start]
        raises on an empty list. *)
    ; orders_per_tick : int
    (** Burst size: how many submissions [on_tick] fires in parallel each
        tick. The primary intensity knob. Must be [>= 0]; the scenario
        currently uses 50. *)
    ; size : int
    (** Shares per order, in whole shares. Scenario currently uses 10. *)
    ; next_client_order_id : int ref
    (** Not a tuning knob: a mutable counter [on_tick] reads-and-increments
        to mint a unique [client_order_id] per order, so submissions never
        collide across ticks (which would trip the exchange's duplicate-ID
        rejection and stall the burst). Each spammer instance must get its
        own fresh [ref] — the scenario allocates one per instance. *)
    }
  [@@deriving sexp_of]
end

include Jsip_bot_runtime.Bot_runtime.Bot with module Config := Config
