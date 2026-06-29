open! Core
open Jsip_types
open Jsip_fundamental

let aapl = Symbol.of_string "AAPL"
let tsla = Symbol.of_string "TSLA"

let calm_config =
  Symbol.Map.of_alist_exn
    [ ( aapl
      , { Fundamental_oracle.Config.initial_price_cents = 15000
        ; volatility_cents_per_sec = 5.0
        ; mean_reversion_strength = 0.05
        ; tick_interval = Time_ns.Span.of_sec 0.1
        } )
    ; ( tsla
      , { initial_price_cents = 25000
        ; volatility_cents_per_sec = 20.0
        ; mean_reversion_strength = 0.0
        ; tick_interval = Time_ns.Span.of_sec 0.1
        } )
    ]
;;

let print_prices oracle =
  print_s
    [%message
      ""
        ~aapl:(Fundamental_oracle.price oracle aapl : Price.t)
        ~tsla:(Fundamental_oracle.price oracle tsla : Price.t)]
;;

let%expect_test "trajectory is deterministic for a given seed" =
  let oracle = Fundamental_oracle.create calm_config ~seed:42 in
  print_prices oracle;
  [%expect {| ((aapl 15000) (tsla 25000)) |}];
  for _ = 1 to 20 do
    Fundamental_oracle.For_testing.advance_step oracle aapl;
    Fundamental_oracle.For_testing.advance_step oracle tsla
  done;
  print_prices oracle;
  [%expect {| ((aapl 15006) (tsla 25030)) |}]
;;

let%expect_test "same seed produces same trajectory" =
  let trajectory seed =
    let oracle = Fundamental_oracle.create calm_config ~seed in
    for _ = 1 to 50 do
      Fundamental_oracle.For_testing.advance_step oracle aapl
    done;
    Fundamental_oracle.price oracle aapl
  in
  let a = trajectory 7 in
  let b = trajectory 7 in
  let c = trajectory 8 in
  print_s [%message "" ~a:(a : Price.t) ~b:(b : Price.t) ~c:(c : Price.t)];
  [%expect {| ((a 14992) (b 14992) (c 15017)) |}]
;;

let%expect_test "shock shifts price by the requested delta" =
  let oracle = Fundamental_oracle.create calm_config ~seed:42 in
  print_prices oracle;
  [%expect {| ((aapl 15000) (tsla 25000)) |}];
  Fundamental_oracle.inject_shock oracle aapl ~delta_cents:500;
  print_prices oracle;
  [%expect {| ((aapl 15500) (tsla 25000)) |}];
  Fundamental_oracle.inject_shock oracle tsla ~delta_cents:(-2000);
  print_prices oracle;
  [%expect {| ((aapl 15500) (tsla 23000)) |}]
;;

let%expect_test "price never falls below 1 cent under heavy negative shocks" =
  let oracle = Fundamental_oracle.create calm_config ~seed:42 in
  Fundamental_oracle.inject_shock oracle aapl ~delta_cents:(-1_000_000);
  print_prices oracle;
  [%expect {| ((aapl 1) (tsla 25000)) |}]
;;

let%expect_test "no-volatility, no-reversion config produces a flat line" =
  let flat_config =
    Symbol.Map.of_alist_exn
      [ ( aapl
        , { Fundamental_oracle.Config.initial_price_cents = 15000
          ; volatility_cents_per_sec = 0.0
          ; mean_reversion_strength = 0.0
          ; tick_interval = Time_ns.Span.of_sec 0.1
          } )
      ]
  in
  let oracle = Fundamental_oracle.create flat_config ~seed:1 in
  for _ = 1 to 100 do
    Fundamental_oracle.For_testing.advance_step oracle aapl
  done;
  print_s [%sexp (Fundamental_oracle.price oracle aapl : Price.t)];
  [%expect {| 15000 |}]
;;
