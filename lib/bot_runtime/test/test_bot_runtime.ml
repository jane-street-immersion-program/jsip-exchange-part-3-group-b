open! Core
open! Async
open Jsip_types
open Jsip_fundamental
open Jsip_bot_runtime

let aapl = Symbol.of_string "AAPL"
let alice = Participant.of_string "Alice"
let bob = Participant.of_string "Bob"

let oracle_config =
  Symbol.Map.of_alist_exn
    [ ( aapl
      , { Fundamental_oracle.Config.initial_price_cents = 15000
        ; volatility_cents_per_sec = 0.0
        ; mean_reversion_strength = 0.0
        ; tick_interval = Time_ns.Span.of_sec 1.0
        } )
    ]
;;

(* A bot that records every event passed to [on_event], so we can assert what
   the runtime forwards. *)
module Recording_bot = struct
  module Config = struct
    type t = { observed : Exchange_event.t list ref }
  end

  let name = "recording"
  let on_start _ _ctx = return ()
  let on_tick _ _ctx = return ()

  let on_event (cfg : Config.t) _ctx event =
    cfg.observed := event :: !(cfg.observed);
    return ()
  ;;
end

let make_recording_bot ~participant =
  let oracle = Fundamental_oracle.create oracle_config ~seed:1 in
  let submit _req = return (Ok ()) in
  let cancel _id = return (Ok ()) in
  let observed = ref [] in
  let bot =
    Bot_runtime.create
      (module Recording_bot)
      { observed }
      ~participant
      ~oracle
      ~rng:(Splittable_random.of_int 0)
      ~submit
      ~cancel
      ~tick_interval:(Time_ns.Span.of_sec 1.0)
  in
  bot, observed
;;

let bbo_event : Exchange_event.t =
  Best_bid_offer_update
    { symbol = aapl
    ; bbo =
        { bid =
            Some { price = Price.of_int_cents 14990; size = Size.of_int 100 }
        ; ask =
            Some { price = Price.of_int_cents 15010; size = Size.of_int 200 }
        }
    }
;;

let fill_event : Exchange_event.t =
  Fill
    { fill_id = 1
    ; symbol = aapl
    ; price = Price.of_int_cents 15000
    ; size = Size.of_int 50
    ; aggressor_order_id = Order_id.For_testing.of_int 1
    ; aggressor_client_order_id = Client_order_id.of_int 1
    ; aggressor_participant = alice
    ; aggressor_side = Buy
    ; resting_order_id = Order_id.For_testing.of_int 2
    ; resting_client_order_id = Client_order_id.of_int 2
    ; resting_participant = bob
    }
;;

let accepted_event : Exchange_event.t =
  Order_accept
    { order_id = Order_id.For_testing.of_int 1
    ; participant = alice
    ; request =
        { client_order_id = Client_order_id.of_int 1
        ; symbol = aapl
        ; side = Buy
        ; price = Price.of_int_cents 15000
        ; size = Size.of_int 10
        ; time_in_force = Day
        }
    }
;;

let print_observed observed =
  let events = List.rev !observed in
  print_s [%sexp (events : Exchange_event.t list)]
;;

let%expect_test "feed_event forwards every event verbatim to on_event" =
  (* The runtime does not filter — the gateway's Dispatcher routes events to
     the right session pipe, so whatever the runtime receives is what the
     bot's [on_event] sees. *)
  let bot, observed = make_recording_bot ~participant:alice in
  let%bind () = Bot_runtime.feed_event bot bbo_event in
  let%bind () = Bot_runtime.feed_event bot fill_event in
  let%bind () = Bot_runtime.feed_event bot accepted_event in
  print_observed observed;
  [%expect
    {|
    ((Best_bid_offer_update (symbol AAPL)
      (bbo
       ((bid (((price 14990) (size 100)))) (ask (((price 15010) (size 200)))))))
     (Fill
      ((fill_id 1) (symbol AAPL) (price 15000) (size 50) (aggressor_order_id 1)
       (aggressor_client_order_id 1) (aggressor_participant Alice)
       (aggressor_side Buy) (resting_order_id 2) (resting_client_order_id 2)
       (resting_participant Bob)))
     (Order_accept (order_id 1) (participant Alice)
      (request
       ((client_order_id 1) (symbol AAPL) (side Buy) (price 15000) (size 10)
        (time_in_force Day)))))
    |}];
  return ()
;;

let%expect_test "fundamental price is read from the oracle" =
  let bot, _observed = make_recording_bot ~participant:alice in
  let ctx = Bot_runtime.For_testing.context_of bot in
  print_s [%sexp (Bot_runtime.Context.fundamental ctx aapl : Price.t)];
  [%expect {| 15000 |}];
  return ()
;;
