open! Core
open! Async
open Jsip_types
module Fundamental_oracle = Jsip_fundamental.Fundamental_oracle

module Event = struct
  type t =
    { at : Time_ns.Span.t
    ; symbol : Symbol.t
    ; delta_cents : int
    ; description : string
    }
  [@@deriving sexp_of]
end

type t =
  { oracle : Fundamental_oracle.t
  ; events : Event.t list
  }

let create oracle events =
  let events =
    List.sort events ~compare:(fun (a : Event.t) (b : Event.t) ->
      Time_ns.Span.compare a.at b.at)
  in
  { oracle; events }
;;

let fire t (event : Event.t) =
  printf
    !"[news] %{Time_ns.Span} %s (%{Symbol} %+d cents)\n"
    event.at
    event.description
    event.symbol
    event.delta_cents;
  Fundamental_oracle.inject_shock
    t.oracle
    event.symbol
    ~delta_cents:event.delta_cents
;;

let start t =
  Deferred.List.iter ~how:`Parallel t.events ~f:(fun event ->
    let%map () = Clock_ns.after event.at in
    fire t event)
;;
