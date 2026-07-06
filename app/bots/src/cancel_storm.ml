open! Core
open! Async
open Jsip_types
open Jsip_bot_runtime

module Config = struct
  type t =
    { symbols : Symbol.t list
    ; cycles_per_tick : int
    ; max_in_flight : int
    ; size : int
    ; passive_offset_cents : int
    ; next_id : int ref
    }
  [@@deriving sexp_of]

  let create
    ~symbols
    ~cycles_per_tick
    ~max_in_flight
    ~size
    ~passive_offset_cents
    ?(first_id = 1)
    ()
    =
    { symbols
    ; cycles_per_tick
    ; max_in_flight
    ; size
    ; passive_offset_cents
    ; next_id = ref first_id
    }
  ;;
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

(* Matching-engine rejections (dup ID, etc.) don't surface here — they arrive
   asynchronously on the session feed, which this bot deliberately ignores.
   The [Or_error]s below are only send-side RPC failures. *)
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
  let%bind submit_result = Bot_runtime.Context.submit ctx request in
  (match submit_result with
   | Ok () -> ()
   | Error error ->
     [%log.error "cancel-storm: submit failed" (error : Error.t)]);
  let%bind cancel_result = Bot_runtime.Context.cancel ctx client_order_id in
  (match cancel_result with
   | Ok () -> ()
   | Error error ->
     [%log.error "cancel-storm: cancel failed" (error : Error.t)]);
  return ()
;;

let on_tick (config : Config.t) ctx =
  Deferred.List.iter ~how:`Sequential config.symbols ~f:(fun symbol ->
    Deferred.List.iter
      ~how:(`Max_concurrent_jobs config.max_in_flight)
      (List.init config.cycles_per_tick ~f:Fn.id)
      ~f:(fun (_ : int) -> run_cycle config ctx symbol))
;;
