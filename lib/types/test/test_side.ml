open! Core
open Jsip_types

let%expect_test "flip: Buy <-> Sell" =
  [%test_result: Side.t] (Side.flip Buy) ~expect:Sell;
  [%test_result: Side.t] (Side.flip Sell) ~expect:Buy
;;

let%expect_test "sign: Buy = 1, Sell = -1" =
  [%test_result: int] (Side.sign Buy) ~expect:1;
  [%test_result: int] (Side.sign Sell) ~expect:(-1)
;;
