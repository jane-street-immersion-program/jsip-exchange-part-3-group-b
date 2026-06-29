open! Core
open! Async
open Jsip_types
open Jsip_gateway

module Config = struct
  type t =
    { participant : Participant.t
    ; symbol : Symbol.t
    ; fair_value_cents : int
    ; half_spread_cents : int
    ; size_per_level : int
    ; num_levels : int
    }
  [@@deriving sexp_of]
end

let seed_book (config : Config.t) conn =
  let submit request =
    let%map result =
      Rpc.Rpc.dispatch_exn Rpc_protocol.submit_order_rpc conn request
    in
    match result with
    | Ok () -> ()
    | Error msg ->
      [%log.error
        "market_maker: submit failed"
          (request : Order.Request.t)
          (msg : Error.t)]
  in
  (* Assign each side at each level a distinct client order ID: level [L]
     gets [2*L + 99] for the bid and [2*L + 100] for the ask. Level one
     assigns IDs 101 and 102. *)
  Deferred.List.iter
    ~how:`Parallel
    (List.init config.num_levels ~f:Fn.id)
    ~f:(fun level_idx ->
      let offset = config.half_spread_cents + level_idx in
      let bid_client_order_id =
        Client_order_id.of_int ((2 * level_idx) + 101)
      in
      let ask_client_order_id =
        Client_order_id.of_int ((2 * level_idx) + 102)
      in
      let%bind () =
        submit
          ({ client_order_id = bid_client_order_id
           ; symbol = config.symbol
           ; side = Buy
           ; price = Price.of_int_cents (config.fair_value_cents - offset)
           ; size = Size.of_int config.size_per_level
           ; time_in_force = Day
           }
           : Order.Request.t)
      and () =
        submit
          ({ client_order_id = ask_client_order_id
           ; symbol = config.symbol
           ; side = Sell
           ; price = Price.of_int_cents (config.fair_value_cents + offset)
           ; size = Size.of_int config.size_per_level
           ; time_in_force = Day
           }
           : Order.Request.t)
      in
      Deferred.unit)
;;
