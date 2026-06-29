open! Core
open Jsip_types
open Expect_test_helpers_core

let make_request
  ?(symbol = "AAPL")
  ?(side = Side.Buy)
  ?(price_cents = 15000)
  ?(size = 100)
  ?(time_in_force = Time_in_force.Day)
  ?(client_order_id = 1)
  ()
  : Order.Request.t
  =
  { client_order_id = Client_order_id.of_int client_order_id
  ; symbol = Symbol.of_string symbol
  ; side
  ; price = Price.of_int_cents price_cents
  ; size = Size.of_int size
  ; time_in_force
  }
;;

let make_order
  ?symbol
  ?(participant = "Alice")
  ?side
  ?price_cents
  ?size
  ?time_in_force
  ()
  =
  let gen = Order_id.Generator.create () in
  Order.create
    (make_request ?symbol ?side ?price_cents ?size ?time_in_force ())
    ~order_id:(Order_id.Generator.next gen)
    ~participant:(Participant.of_string participant)
;;

let%expect_test "create: remaining_size starts equal to size" =
  let order = make_order ~size:75 () in
  [%test_result: Size.t] (Order.size order) ~expect:(Size.of_int 75);
  [%test_result: Size.t]
    (Order.remaining_size order)
    ~expect:(Size.of_int 75)
;;

let%expect_test "create: rejects non-positive size" =
  require_does_raise (fun () -> make_order ~size:0 ());
  [%expect {| ("Order.create: size must be positive" (req.size 0)) |}];
  require_does_raise (fun () -> make_order ~size:(-5) ());
  [%expect {| ("Order.create: size must be positive" (req.size -5)) |}]
;;

let%expect_test "fill: reduces remaining size" =
  let order = make_order ~size:100 () in
  Order.fill order ~by:(Size.of_int 30);
  [%test_result: Size.t]
    (Order.remaining_size order)
    ~expect:(Size.of_int 70);
  Order.fill order ~by:(Size.of_int 70);
  [%test_result: Size.t] (Order.remaining_size order) ~expect:Size.zero
;;

let%expect_test "fill: rejects zero or negative fill" =
  let order = make_order ~size:100 () in
  require_does_raise (fun () -> Order.fill order ~by:Size.zero);
  [%expect {| ("Order.fill: fill size must be positive" (by 0)) |}];
  require_does_raise (fun () -> Order.fill order ~by:(Size.of_int (-10)));
  [%expect {| ("Order.fill: fill size must be positive" (by -10)) |}]
;;

let%expect_test "fill: rejects overfill" =
  let order = make_order ~size:50 () in
  require_does_raise (fun () -> Order.fill order ~by:(Size.of_int 51));
  [%expect
    {|
    ("Order.fill: fill size exceeds remaining"
      (by               51)
      (t.remaining_size 50)
      (t.order_id       1))
    |}]
;;

let%expect_test "is_fully_filled: true only when remaining = 0" =
  let order = make_order ~size:100 () in
  [%test_result: bool] (Order.is_fully_filled order) ~expect:false;
  Order.fill order ~by:(Size.of_int 50);
  [%test_result: bool] (Order.is_fully_filled order) ~expect:false;
  Order.fill order ~by:(Size.of_int 50);
  [%test_result: bool] (Order.is_fully_filled order) ~expect:true
;;
