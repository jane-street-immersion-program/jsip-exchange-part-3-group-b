open! Core
open! Async
open Jsip_types
module Context = Jsip_bot_runtime.Bot_runtime.Context

module Config = struct
  type t =
    { symbols : Symbol.t list
    ; orders_per_tick : int
    ; size : int
    ; min_offset_cents : int
    ; max_offset_cents : int
    ; next_client_order_id : int ref
    }
  [@@deriving sexp_of]

  let create
    ~symbols
    ~orders_per_tick
    ~size
    ~min_offset_cents
    ~max_offset_cents
    ?(first_client_order_id = 1)
    ()
    =
    { symbols
    ; orders_per_tick
    ; size
    ; min_offset_cents
    ; max_offset_cents
    ; next_client_order_id = ref first_client_order_id
    }
  ;;
end

let name = "book-filler"
let on_start (_config : Config.t) (_ctx : Context.t) = return ()

let on_event
  (_config : Config.t)
  (_ctx : Context.t)
  (_event : Exchange_event.t)
  =
  return ()
;;

(* Each order needs a client order ID this participant hasn't used before, or
   the matching engine rejects it as a duplicate and nothing new rests. The
   counter lives in [Config] because the bot has no other per-instance state;
   [Config.create] allocates a fresh [ref] so two instances never share one. *)
let next_client_order_id (config : Config.t) =
  let id = !(config.next_client_order_id) in
  incr config.next_client_order_id;
  Client_order_id.of_int id
;;

(* Place the order deep on one side, [offset] cents away from the current
   fundamental: bids strictly below, asks strictly above. As long as the
   configured offset band keeps orders on both sides clear of the touch, they
   are never marketable, so they rest forever instead of trading -- exactly
   the "pile, don't fill" behavior we want. *)
let build_request (config : Config.t) (ctx : Context.t) symbol
  : Order.Request.t
  =
  let rng = Context.random ctx in
  let side : Side.t =
    if Splittable_random.int rng ~lo:0 ~hi:1 = 0 then Buy else Sell
  in
  let offset =
    Splittable_random.int
      rng
      ~lo:config.min_offset_cents
      ~hi:config.max_offset_cents
  in
  let fundamental_cents =
    Price.to_int_cents (Context.fundamental ctx symbol)
  in
  let price_cents =
    match side with
    | Buy -> fundamental_cents - offset
    | Sell -> fundamental_cents + offset
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
  (* Build every request synchronously first (so ID allocation and RNG draws
     happen in a fixed order), then fire them all at once to maximize the
     burst of resting orders hitting the book on this tick. *)
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
        "book_filler: submit failed"
          (request : Order.Request.t)
          (error : Error.t)])
;;
