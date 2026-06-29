(** Runtime scaffolding for automated trading bots.

    A bot is a strategy module that decides what orders to send and when. The
    runtime owns the boilerplate: it exposes the bot's identity, the
    fundamental oracle, a private RNG, and a [submit]/[cancel] interface,
    drives the bot's [on_tick] callback on a periodic clock, and dispatches
    incoming session-feed events to the bot's [on_event] callback. Tracking
    quotes, inventory, BBOs, or any other strategy-specific state is left to
    the individual bot.

    Bots interact with the exchange through RPC closures supplied at
    construction time. The runtime does not care whether those closures
    dispatch over a real TCP connection or shortcut to an in-process server —
    that detail belongs to whoever constructed the bot (typically
    [Jsip_scenario_runner.Runner]). *)

open! Core
open! Async
open Jsip_types

(** A bot's view of the world. *)
module Context : sig
  type t

  val participant : t -> Participant.t

  (** Current fundamental price from the oracle. *)
  val fundamental : t -> Symbol.t -> Price.t

  (** Bot-private random-number source for stochastic strategies. *)
  val random : t -> Splittable_random.t

  (** Submit an order via the exchange's RPC. The RPC is one-way: it returns
      [Ok ()] once the server has enqueued the request, or an error string if
      the call itself failed (e.g. the connection isn't logged in). The
      matching engine's response — [Order_accept], [Fill], [Order_reject],
      etc. — arrives asynchronously on the bot's session feed, which the
      runtime delivers to [on_event]. *)
  val submit : t -> Order.Request.t -> unit Deferred.Or_error.t

  (** Cancel one of this bot's resting orders via the exchange's RPC. Same
      one-way shape as [submit]: success/failure of the cancel attempt
      arrives as an event on the session feed. *)
  val cancel : t -> Client_order_id.t -> unit Deferred.Or_error.t
end

module type Bot = sig
  module Config : sig
    type t
  end

  val name : string

  (** Called exactly once, before the first tick fires and before any events
      are delivered. Use this for one-time startup work that needs the
      context — for example, a market maker seeding its initial ladder, or a
      momentum trader priming its sliding-window state. Bots that don't need
      startup work can return [Deferred.unit]. *)
  val on_start : Config.t -> Context.t -> unit Deferred.t

  (** Called periodically. The bot reads from the context and submits /
      cancels orders. *)
  val on_tick : Config.t -> Context.t -> unit Deferred.t

  (** Called for every event delivered on the bot's session feed and
      market-data subscription: [Order_accept], [Order_cancel],
      [Order_reject], and [Fill] events involving the bot, plus [BBO] and
      [Trade_report] events for symbols the runtime subscribes to. Bots that
      do not need event-level reactivity can return [Deferred.unit]. *)
  val on_event : Config.t -> Context.t -> Exchange_event.t -> unit Deferred.t
end

(** A running bot. *)
type t

(** Construct a bot. The runtime closes over [submit] and [cancel] so the
    strategy code does not need to know whether they dispatch over a real RPC
    connection or shortcut to an in-process server. *)
val create
  :  (module Bot with type Config.t = 'cfg)
  -> 'cfg
  -> participant:Participant.t
  -> oracle:Jsip_fundamental.Fundamental_oracle.t
  -> rng:Splittable_random.t
  -> submit:(Order.Request.t -> unit Deferred.Or_error.t)
  -> cancel:(Client_order_id.t -> unit Deferred.Or_error.t)
  -> tick_interval:Time_ns.Span.t
  -> t

(** Deliver an event to the bot's [on_event] handler. *)
val feed_event : t -> Exchange_event.t -> unit Deferred.t

(** The bot's identity (for routing/debugging). *)
val participant : t -> Participant.t

(** Run [on_tick] in a forever-loop on the configured interval. Returns a
    never-determined [Deferred.t]. *)
val start : t -> unit Deferred.t

module For_testing : sig
  val context_of : t -> Context.t
end
