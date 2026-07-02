open! Core
open! Async
open Jsip_types
open Jsip_bot_runtime

module Config = struct
  type t =
    { symbols : Symbol.t list
    ; cycles_per_tick : int
    ; size : int
    ; passive_offset_cents : int
    ; next_id : int ref
    }
end

let name = "cancel-storm"
let on_start (_ : Config.t) (_ : Bot_runtime.Context.t) = return ()

let on_event
  (_ : Config.t)
  (_ : Bot_runtime.Context.t)
  (_ : Exchange_event.t)
  =
  return ()
;;

(* One submit-then-cancel cycle: allocate a fresh client order ID, submit a
   passive (non-marketable) buy, and immediately cancel it without waiting
   for the acceptance. The submit and cancel results are ignored on purpose —
   the matching engine's response arrives asynchronously on the session feed,
   which this bot deliberately does not read. *)
let run_cycle (config : Config.t) ctx symbol =
  let client_order_id = Client_order_id.of_int !(config.next_id) in
  incr config.next_id;
  let fundamental = Bot_runtime.Context.fundamental ctx symbol in
  let price =
    Price.of_int_cents
      (Price.to_int_cents fundamental - config.passive_offset_cents)
  in
  let request : Order.Request.t =
    { symbol
    ; participant = Bot_runtime.Context.participant ctx
    ; side = Buy
    ; price
    ; size = Size.of_int config.size
    ; time_in_force = Day
    ; client_order_id
    }
  in
  let%bind (_ : unit Or_error.t) = Bot_runtime.Context.submit ctx request in
  let%bind (_ : unit Or_error.t) =
    Bot_runtime.Context.cancel ctx client_order_id
  in
  return ()
;;

let on_tick (config : Config.t) ctx =
  Deferred.List.iter ~how:`Sequential config.symbols ~f:(fun symbol ->
    Deferred.List.iter
      ~how:`Sequential
      (List.init config.cycles_per_tick ~f:Fn.id)
      ~f:(fun (_ : int) -> run_cycle config ctx symbol))
;;
