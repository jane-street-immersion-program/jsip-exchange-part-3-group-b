(** Exchange server for production use and testing.

    Bundles the matching engine, market data bus, and RPC implementations
    into a single server that can be started on any port. Used by the server
    binary, the market maker binary, and integration tests. *)

open! Core
open! Async
open Jsip_types

type t

(** Start a server on the given port with the given symbols. Returns the
    server handle and the port it is actually listening on (useful when you
    pass port 0 to get an OS-assigned port). *)
val start : symbols:Symbol.t list -> port:int -> unit -> t Deferred.t

(** The port the server is listening on. *)
val port : t -> int

(** Stop the server and close all connections. *)
val close : t -> unit Deferred.t

(** Wait until the server's TCP listener is closed. *)
val close_finished : t -> unit Deferred.t
