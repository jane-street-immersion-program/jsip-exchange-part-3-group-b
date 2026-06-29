(** Schedules pre-configured shocks against a [Fundamental_oracle].

    A scenario's "news" is just a list of timed [Event.t]s: at offset [at]
    from start, apply [delta_cents] to a symbol's fundamental and print
    [description] to stdout for demo narration. Used by scenarios like
    "earnings shock" and "flash crash" to produce visible step-changes in the
    price stream. *)

open! Core
open! Async
open Jsip_types

module Event : sig
  type t =
    { at : Time_ns.Span.t (** Offset from [start] when the shock fires. *)
    ; symbol : Symbol.t
    ; delta_cents : int
    ; description : string
    }
  [@@deriving sexp_of]
end

type t

val create : Jsip_fundamental.Fundamental_oracle.t -> Event.t list -> t

(** Schedules each event with [Async.Clock_ns.run_after] relative to the
    current time. Returns a [Deferred.t] that becomes determined once all
    events have fired. *)
val start : t -> unit Deferred.t
