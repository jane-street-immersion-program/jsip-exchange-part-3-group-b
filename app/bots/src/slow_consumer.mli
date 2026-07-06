(** A pathological bot that subscribes to a feed and then reads it too
    slowly.

    The slow consumer submits no orders. It logs in, the runtime subscribes
    it to market data for the symbols in its [Bot_spec.t] (set
    [is_marketdata_consumer = true] in the spec), and then it drains that
    pipe at the crawl dictated by its [read_behavior] -- either a fixed delay
    per event, or never at all.

    The target is the {b exchange-side buffer} that holds pending events for
    this subscriber. The runtime reads the feed with
    [Pipe.iter pipe ~f:(feed_event bot)], which waits for each [on_event] to
    finish before reading the next element, so a slow [on_event] is a slow
    reader. The exchange, meanwhile, publishes with
    [Pipe.write_without_pushback_if_open] and sets no size budget on the
    subscriber pipe, so events for a subscriber that isn't keeping up pile up
    in the exchange's memory unbounded.

    A single slow consumer already stalls its own pipe, but the collateral
    damage is easiest to see with a crowd: run many of them against a busy
    market so the exchange holds many unbounded buffers at once. The symbols
    to subscribe to, the number of instances, and the traffic that fills the
    feed all live in the scenario -- see [Jsip_scenarios.Slow_consumers]. *)

open! Core
open! Async

(** How the consumer paces its reads. *)
module Read_behavior : sig
  type t =
    | Never
    (** Never drains the pipe: [on_event] returns a deferred that is never
        determined, so the runtime reads at most one event and then all
        further events queue on the exchange side forever. *)
    | Delay_per_event of Time_ns.Span.t
    (** Read one event per span. Larger spans read more slowly and back the
        exchange buffer up faster. *)
  [@@deriving sexp_of]
end

module Config : sig
  type t = { read_behavior : Read_behavior.t } [@@deriving sexp_of]

  (** [read_behavior] is required and has no default. *)
  val create : read_behavior:Read_behavior.t -> t
end

include Jsip_bot_runtime.Bot_runtime.Bot with module Config := Config
