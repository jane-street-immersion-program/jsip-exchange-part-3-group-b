(** Glue that boots a scenario into a running exchange + ecosystem of bots. *)

open! Core
open! Async

(** Boot the exchange on [port], spin up the oracle/news/bots described by
    [config], and return a deferred that resolves only when the server is
    closed. The deferred for each bot's tick loop is leaked via
    [don't_wait_for]. *)
val run : Scenario_config.t -> port:int -> seed:int -> unit Deferred.t
