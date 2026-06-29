(** The matching engine: receives order requests, manages order books, and
    produces exchange events.

    The engine is the heart of the exchange. It assigns order IDs, determines
    which orders can trade against each other, executes fills, and manages
    the lifecycle of resting orders. *)

open! Core
open Jsip_types

type t [@@deriving sexp_of]

(** Create a matching engine for the given symbols. Each symbol gets its own
    order book. *)
val create : Symbol.t list -> t

(** {2 Order submission} *)

(** Submit a new order request on behalf of [participant]. Returns the list
    of exchange events produced: an acceptance or rejection, followed by any
    fills, and possibly a cancellation of unfilled remainder (for IOC
    orders).

    A request is rejected (with a single [Order_reject] event) if:

    - the [(participant, client_order_id)] pair has already been used by a
      prior accepted submission — even if that order is now fully filled or
      cancelled. IDs are never reused within the lifetime of the engine.
    - the request's [symbol] is not traded on this engine.

    The event list is always non-empty (at minimum an acceptance or
    rejection). *)
val submit
  :  t
  -> participant:Participant.t
  -> Order.Request.t
  -> Exchange_event.t list

(** {2 Queries} *)

(** The order book for a given symbol, or [None] if the symbol is not traded
    on this engine. *)
val book : t -> Symbol.t -> Order_book.t option

(* NOTE: Both errors produce the same "order not found" message as per the
   spec and the client cannot distinguish them. Here are some design notes in
   case students ask or want to do something different.

   Advantages:
   - Client handling is simpler. In both cases the client should stop
     tracking this order. It's generally discouraged to parse [Error.t]s so
     distinguishing between them rarely changes client behavior.
   - Mild information hiding. A client who guesses an ID they never used
     can't probe to learn which IDs were valid for them.

   Disadvantages:
   - Debugging is harder. When an order is not found, it's not clear whether
     there was a typo or whether the order was already filled.

   Real-world exchanges vary. Venues that implement the FIX protocol tend to
   use granular reject reasons, though some still lump multiple error reasons
   into a single "99 Other" reject. REST API venues like many crypto
   exchanges tend to have less granularity. A future exercise could extend
   the error taxonomy to distinguish these cases.
*)

(** Cancel a resting order submitted by [participant] under
    [client_order_id].

    On success, returns the events to publish — at minimum an [Order_cancel]
    with [Participant_requested] reason, plus a [Best_bid_offer_update] if
    the cancellation changed the BBO.

    Returns [Cancel_reject] with an "order not found" reason when:
    - [participant] never submitted an order under [client_order_id], or
    - an order was submitted but is no longer in the book (fully filled, or
      previously cancelled). *)
val cancel
  :  t
  -> participant:Participant.t
  -> client_order_id:Client_order_id.t
  -> Exchange_event.t list
