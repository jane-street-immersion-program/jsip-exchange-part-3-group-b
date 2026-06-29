(** A logged-in client's outbound event channel.

    One [Session.t] is created per logged-in connection. It holds the
    participant identity established at login plus a pipe that the
    [Dispatcher] writes to whenever a matching-engine event involving this
    participant is produced ([Order_accept], [Order_cancel], [Order_reject],
    [Fill] as aggressor or resting party).

    The reader half is handed back to the client via [session_feed_rpc]; the
    client drains it asynchronously. *)

open! Core
open! Async
open Jsip_types

type t

val create : Participant.t -> t

(** The participant this session belongs to. *)
val participant : t -> Participant.t

(** Hand the reader to the client (via [session_feed_rpc]). Returns the same
    reader every time it's called — there is only one outbound stream per
    session. *)
val reader : t -> Exchange_event.t Pipe.Reader.t

(** Push an event onto the session's outbound pipe. *)
val push : t -> Exchange_event.t -> unit

(** Close the outbound pipe. Subsequent reads on [reader t] will drain any
    remaining buffered events and then EOF. *)
val close : t -> unit

(** [true] iff [close] has been called. *)
val is_closed : t -> bool
