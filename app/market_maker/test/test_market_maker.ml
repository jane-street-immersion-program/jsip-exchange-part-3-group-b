(** Tests for the market maker, using a real exchange server. *)

open! Core
open! Async
open Jsip_test_harness
open Jsip_market_maker
open E2e_helpers

let default_config : Market_maker.Config.t =
  { participant = Harness.market_maker
  ; symbol = Harness.aapl
  ; fair_value_cents = 15000
  ; half_spread_cents = 10
  ; size_per_level = 100
  ; num_levels = 3
  }
;;

let%expect_test "seed_book: places symmetric bids and asks around fair value"
  =
  with_server ~symbols:[ Harness.aapl ] (fun ~server:_ ~port ->
    let%bind mm = connect_as ~port ~participant:Harness.market_maker in
    let%bind () = Market_maker.seed_book default_config (connection mm) in
    [%expect
      {|
      [MarketMaker] ACCEPTED server_id=1 client_id=101 AAPL BUY 100@$149.90 DAY
      [MarketMaker] ACCEPTED server_id=2 client_id=102 AAPL SELL 100@$150.10 DAY
      [MarketMaker] ACCEPTED server_id=3 client_id=103 AAPL BUY 100@$149.89 DAY
      [MarketMaker] ACCEPTED server_id=4 client_id=104 AAPL SELL 100@$150.11 DAY
      [MarketMaker] ACCEPTED server_id=5 client_id=105 AAPL BUY 100@$149.88 DAY
      [MarketMaker] ACCEPTED server_id=6 client_id=106 AAPL SELL 100@$150.12 DAY
      |}];
    return ())
;;
