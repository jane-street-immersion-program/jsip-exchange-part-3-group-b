open! Core
open! Async
open Jsip_types
open Jsip_fundamental
open Jsip_news_injector

let aapl = Symbol.of_string "AAPL"
let tsla = Symbol.of_string "TSLA"

let oracle_config =
  Symbol.Map.of_alist_exn
    [ ( aapl
      , { Fundamental_oracle.Config.initial_price_cents = 15000
        ; volatility_cents_per_sec = 0.0
        ; mean_reversion_strength = 0.0
        ; tick_interval = Time_ns.Span.of_sec 1.0
        } )
    ; ( tsla
      , { initial_price_cents = 25000
        ; volatility_cents_per_sec = 0.0
        ; mean_reversion_strength = 0.0
        ; tick_interval = Time_ns.Span.of_sec 1.0
        } )
    ]
;;

let%expect_test "events fire in time order and shift the fundamental" =
  let oracle = Fundamental_oracle.create oracle_config ~seed:1 in
  let events =
    [ { News_injector.Event.at = Time_ns.Span.of_sec 0.05
      ; symbol = aapl
      ; delta_cents = 500
      ; description = "AAPL earnings beat"
      }
    ; { at = Time_ns.Span.of_sec 0.02
      ; symbol = tsla
      ; delta_cents = -1000
      ; description = "TSLA recall"
      }
    ]
  in
  let injector = News_injector.create oracle events in
  let%bind () = News_injector.start injector in
  print_s
    [%message
      ""
        ~aapl:(Fundamental_oracle.price oracle aapl : Price.t)
        ~tsla:(Fundamental_oracle.price oracle tsla : Price.t)];
  [%expect
    {|
    [news] 20ms TSLA recall (TSLA -1000 cents)
    [news] 50ms AAPL earnings beat (AAPL +500 cents)
    ((aapl 15500) (tsla 24000))
    |}];
  return ()
;;
