open! Core
open! Async
open Jsip_types
module Context = Jsip_bot_runtime.Bot_runtime.Context

module Config = struct
  type t =
    { symbols : Symbol.t list
    ; orders_per_tick : int
    ; jitter_cents : int
    ; size : int
    ; next_client_order_id : int ref
    }
  [@@deriving sexp_of]

  let create
    ~symbols
    ~orders_per_tick
    ~jitter_cents
    ~size
    ?(first_client_order_id = 1)
    ()
    =
    { symbols
    ; orders_per_tick
    ; jitter_cents
    ; size
    ; next_client_order_id = ref first_client_order_id
    }
  ;;
end

let name = "noise-trader"
let on_start (_config : Config.t) (_ctx : Context.t) = return ()

let on_event
  (_config : Config.t)
  (_ctx : Context.t)
  (_event : Exchange_event.t)
  =
  return ()
;;

let next_client_order_id (config : Config.t) =
  let id = !(config.next_client_order_id) in
  incr config.next_client_order_id;
  Client_order_id.of_int id
;;

(* Fire an order priced right around the fundamental, on a random side. Buys
   bid up to [jitter_cents] above fair and sells offer down to [jitter_cents]
   below it, so orders from different instances overlap around the touch and
   frequently cross -- producing a steady stream of [Trade_report]s and
   top-of-book changes. That churn is the point: it is what feeds the
   market-data firehose the slow consumers then fail to drain. *)
let build_request (config : Config.t) (ctx : Context.t) symbol
  : Order.Request.t
  =
  let rng = Context.random ctx in
  let side : Side.t =
    if Splittable_random.int rng ~lo:0 ~hi:1 = 0 then Buy else Sell
  in
  let offset = Splittable_random.int rng ~lo:0 ~hi:config.jitter_cents in
  let fundamental_cents =
    Price.to_int_cents (Context.fundamental ctx symbol)
  in
  let price_cents =
    match side with
    | Buy -> fundamental_cents + offset
    | Sell -> fundamental_cents - offset
  in
  { client_order_id = next_client_order_id config
  ; symbol
  ; participant = Context.participant ctx
  ; side
  ; price = Price.of_int_cents price_cents
  ; size = Size.of_int config.size
  ; time_in_force = Day
  }
;;

let on_tick (config : Config.t) (ctx : Context.t) =
  let requests =
    List.concat_map config.symbols ~f:(fun symbol ->
      List.init config.orders_per_tick ~f:(fun (_ : int) ->
        build_request config ctx symbol))
  in
  Deferred.List.iter ~how:`Parallel requests ~f:(fun request ->
    match%map Context.submit ctx request with
    | Ok () -> ()
    | Error error ->
      [%log.error
        "noise_trader: submit failed"
          (request : Order.Request.t)
          (error : Error.t)])
;;
