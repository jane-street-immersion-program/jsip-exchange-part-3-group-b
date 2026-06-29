(** Central event-routing component for the gateway.

    Owns subscription registries:

    - **Market-data subscribers**, keyed by [Symbol.t]. Each subscriber gets
      a pipe of [Best_bid_offer_update] and [Trade_report] events for the
      symbol they asked about. This is the public market-data feed.

    - **Audit subscribers**, an unfiltered firehose of every event the
      matching engine produces. Intended for the exchange operator's monitor;
      not appropriate to expose to ordinary clients.

    [dispatch] is the single place that decides "for each event, who gets
    it". *)

open! Core
open! Async
open Jsip_types

type t

(** Create a dispatcher.

    Events whose audience is a single participant (order-lifecycle responses
    and [Fill] events) are currently handed to a stub [push_to_session] that
    prints them on stdout, prefixed with the target participant. Wiring this
    up to real [Session] outbound pipes is a week-2 exercise. *)
val create : unit -> t

(** Subscribe to public market data for one or more [symbols]. The same pipe
    receives events for every requested symbol; the dispatcher avoids
    duplicates so a subscriber listed against multiple symbols only sees each
    event once. The pipe is removed from the dispatcher when its reader is
    closed. *)
val subscribe_market_data
  :  t
  -> Symbol.t list
  -> Exchange_event.t Pipe.Reader.t

(** Subscribe to the full unfiltered event firehose. Intended for the monitor
    / admin tools. *)
val subscribe_audit : t -> Exchange_event.t Pipe.Reader.t

(** Route each event to every interested subscriber:

    - Every event is pushed to every audit subscriber.
    - [Best_bid_offer_update] and [Trade_report] are pushed to the
      market-data subscribers that asked for the event's symbol.
    - [Order_accept], [Order_cancel], and [Order_reject] are pushed to the
      session of the order's owning participant (if logged in).
    - [Fill] is pushed to both the aggressor's and the resting party's
      session (if either is logged in).

    Each session lookup is O(1) and independent of subscriber count. *)
val dispatch : t -> Exchange_event.t list -> unit

(** Registers a new session for the given participant, closing and cleaning
    up any existing session for that participant. *)
val set_up_session : t -> Participant.t -> Session.t

val clean_up_session : t -> Session.t -> unit

module For_testing : sig
  val audit_subscriber_count : t -> int
end
