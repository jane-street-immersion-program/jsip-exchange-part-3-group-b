(** Scaffolding for bot tests. *)

open! Core
open! Async
open Jsip_types
open Jsip_fundamental
open Jsip_bot_runtime
open! Jsip_bots

let aapl = Symbol.of_string "AAPL"
let alice = Participant.of_string "Alice"

let oracle_config ~initial_price_cents =
  Symbol.Map.of_alist_exn
    [ ( aapl
      , { Fundamental_oracle.Config.initial_price_cents
        ; volatility_cents_per_sec = 0.0
        ; mean_reversion_strength = 0.0
        ; tick_interval = Time_ns.Span.of_sec 1.0
        } )
    ]
;;

(* Build a runtime around a bot module with a mock submit/cancel that records
   what the bot does. *)
let make_recording_bot
  (type cfg)
  (bot_module : (module Bot_runtime.Bot with type Config.t = cfg))
  (config : cfg)
  ?(initial_price_cents = 15000)
  ()
  =
  let submitted = ref [] in
  let cancelled = ref [] in
  let submit request =
    submitted := request :: !submitted;
    return (Ok ())
  in
  let cancel order_id =
    cancelled := order_id :: !cancelled;
    return (Ok ())
  in
  let oracle =
    Fundamental_oracle.create (oracle_config ~initial_price_cents) ~seed:42
  in
  let bot =
    Bot_runtime.create
      bot_module
      config
      ~participant:alice
      ~oracle
      ~rng:(Splittable_random.of_int 7)
      ~submit
      ~cancel
      ~tick_interval:(Time_ns.Span.of_sec 1.0)
  in
  bot, submitted, cancelled
;;

let print_submitted (submitted : Order.Request.t list ref) =
  let recent = List.rev !submitted in
  List.iter recent ~f:(fun req ->
    printf
      !"%{Side} %{Symbol} %d@%{Price#dollar} %{Time_in_force}\n"
      req.side
      req.symbol
      (Size.to_int req.size)
      req.price
      req.time_in_force)
;;

(* Smoke test: drive the do-nothing reference bot through one event so the
   runtest target exercises the helpers above. Replace or extend with
   bot-specific tests as concrete strategies are added to [Jsip_bots]. *)
module Inert_bot = struct
  module Config = struct
    type t = unit
  end

  let name = "inert"
  let on_start () _ctx = return ()
  let on_tick () _ctx = return ()
  let on_event () _ctx _event = return ()
end

let spammer_config ~orders_per_tick : Spammer.Config.t =
  { symbol = aapl; orders_per_tick; size = 10; next_client_order_id = ref 0 }
;;

(* Like [print_submitted] but also shows the client_order_id, since ID
   uniqueness across ticks is the behavior we most want to see. *)
let print_orders (submitted : Order.Request.t list ref) =
  List.rev !submitted
  |> List.iter ~f:(fun (req : Order.Request.t) ->
    printf
      !"#%{sexp:Client_order_id.t} %{Side} %{Symbol} %d@%{Price#dollar} \
        %{Time_in_force}\n"
      req.client_order_id
      req.side
      req.symbol
      (Size.to_int req.size)
      req.price
      req.time_in_force)
;;

let%expect_test "spammer fires a burst of never-fill orders each tick" =
  let config = spammer_config ~orders_per_tick:3 in
  let bot, submitted, _cancelled =
    make_recording_bot (module Spammer) config ()
  in
  let ctx = Bot_runtime.For_testing.context_of bot in
  (* Two ticks. The second must keep minting fresh IDs (3, 4, 5), not reset to
     0 — that's the persistent-counter fix, and it's what keeps the exchange's
     duplicate-ID path from rejecting the burst. *)
  let%bind () = Spammer.on_tick config ctx in
  let%bind () = Spammer.on_tick config ctx in
  print_orders submitted;
  [%expect {|
    #0 BUY AAPL 10@$0.01 DAY
    #1 SELL AAPL 10@$10000.00 DAY
    #2 BUY AAPL 10@$0.01 DAY
    #3 BUY AAPL 10@$0.01 DAY
    #4 SELL AAPL 10@$10000.00 DAY
    #5 BUY AAPL 10@$0.01 DAY
    |}];
  return ()
;;

let%expect_test "make_recording_bot wires up a runnable bot" =
  let bot, submitted, _cancelled =
    make_recording_bot (module Inert_bot) () ()
  in
  let%bind () =
    Bot_runtime.feed_event
      bot
      (Order_accept
         { order_id = Order_id.For_testing.of_int 1
         ; request =
             { client_order_id = Client_order_id.of_int 1
             ; symbol = aapl
             ; participant = alice
             ; side = Buy
             ; price = Price.of_int_cents 15000
             ; size = Size.of_int 10
             ; time_in_force = Day
             }
         })
  in
  print_submitted submitted;
  [%expect {| |}];
  return ()
;;
