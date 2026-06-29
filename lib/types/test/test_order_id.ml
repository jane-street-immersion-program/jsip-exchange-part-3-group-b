open! Core
open Jsip_types
open Expect_test_helpers_core

let%expect_test "Generator: produces sequential IDs starting at 1" =
  let gen = Order_id.Generator.create () in
  let id1 = Order_id.Generator.next gen in
  let id2 = Order_id.Generator.next gen in
  let id3 = Order_id.Generator.next gen in
  [%test_result: int] (Order_id.For_testing.to_int id1) ~expect:1;
  [%test_result: int] (Order_id.For_testing.to_int id2) ~expect:2;
  [%test_result: int] (Order_id.For_testing.to_int id3) ~expect:3
;;

let%expect_test "Generator: separate generators are independent" =
  let gen1 = Order_id.Generator.create () in
  let gen2 = Order_id.Generator.create () in
  let id1 = Order_id.Generator.next gen1 in
  let id2 = Order_id.Generator.next gen2 in
  require (Order_id.For_testing.to_int id1 = Order_id.For_testing.to_int id2)
;;
