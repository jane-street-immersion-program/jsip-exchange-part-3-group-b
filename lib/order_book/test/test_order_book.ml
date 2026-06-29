open! Core
open Jsip_types
open Jsip_order_book
open Jsip_test_harness

let make_order
  ~side
  ~price_cents
  ~order_id
  ?(size = 100)
  ?(participant = Harness.alice)
  ()
  =
  Order.create
    ({ client_order_id = Client_order_id.of_int order_id
     ; symbol = Harness.aapl
     ; side
     ; price = Price.of_int_cents price_cents
     ; size = Size.of_int size
     ; time_in_force = Day
     }
     : Order.Request.t)
    ~order_id:(Order_id.For_testing.of_int order_id)
    ~participant
;;

(* --- add / find / remove --- *)

let%expect_test "add and find an order" =
  let book = Order_book.create Harness.aapl in
  let order = make_order ~side:Buy ~price_cents:15000 ~order_id:1 () in
  Order_book.add book order;
  [%test_result: Order.t option]
    (Order_book.find book (Order.order_id order))
    ~expect:(Some order)
;;

let%expect_test "find returns None for unknown order" =
  let book = Order_book.create Harness.aapl in
  [%test_result: _ option]
    (Order_book.find book (Order_id.For_testing.of_int 1))
    ~expect:None
;;

let%expect_test "remove an order" =
  let book = Order_book.create Harness.aapl in
  let order = make_order ~side:Sell ~price_cents:15100 ~order_id:1 () in
  Order_book.add book order;
  [%test_result: int] (Order_book.count book Sell) ~expect:1;
  let removed = Order_book.For_testing.remove book (Order.order_id order) in
  [%test_result: Order.t option] removed ~expect:(Some order);
  [%test_result: int] (Order_book.count book Sell) ~expect:0;
  [%test_result: _ option]
    (Order_book.find book (Order_id.For_testing.of_int 1))
    ~expect:None
;;

let%expect_test "remove returns None for unknown order" =
  let book = Order_book.create Harness.aapl in
  [%test_result: _ option]
    (Order_book.For_testing.remove book (Order_id.For_testing.of_int 1))
    ~expect:None
;;

(* --- is_empty / count --- *)

let%expect_test "is_empty on fresh book" =
  let book = Order_book.create Harness.aapl in
  [%test_result: bool] (Order_book.is_empty book) ~expect:true
;;

let%expect_test "count tracks orders on each side independently" =
  let book = Order_book.create Harness.aapl in
  Order_book.add
    book
    (make_order ~side:Buy ~price_cents:15000 ~order_id:1 ());
  Order_book.add
    book
    (make_order ~side:Buy ~price_cents:14900 ~order_id:2 ());
  Order_book.add
    book
    (make_order ~side:Sell ~price_cents:15100 ~order_id:3 ());
  [%test_result: int] (Order_book.count book Buy) ~expect:2;
  [%test_result: int] (Order_book.count book Sell) ~expect:1;
  [%test_result: bool] (Order_book.is_empty book) ~expect:false
;;

(* --- orders_on_side --- *)

let%expect_test "orders_on_side returns all orders on a side" =
  let book = Order_book.create Harness.aapl in
  Order_book.add
    book
    (make_order ~side:Buy ~price_cents:15000 ~order_id:1 ());
  Order_book.add
    book
    (make_order ~side:Buy ~price_cents:14900 ~order_id:2 ());
  Order_book.add
    book
    (make_order ~side:Sell ~price_cents:15100 ~order_id:3 ());
  let bid_ids =
    Order_book.orders_on_side book Buy
    |> List.map ~f:(fun o -> Order.order_id o)
    |> List.sort ~compare:Order_id.compare
  in
  let ask_ids =
    Order_book.orders_on_side book Sell
    |> List.map ~f:(fun o -> Order.order_id o)
    |> List.sort ~compare:Order_id.compare
  in
  let bid_str =
    List.map bid_ids ~f:Order_id.to_string |> String.concat ~sep:", "
  in
  let ask_str =
    List.map ask_ids ~f:Order_id.to_string |> String.concat ~sep:", "
  in
  print_endline [%string "bid order ids: %{bid_str}"];
  print_endline [%string "ask order ids: %{ask_str}"];
  [%expect {|
    bid order ids: 1, 2
    ask order ids: 3
    |}]
;;

(* --- find_match --- *)

let%expect_test "find_match returns None for empty book" =
  let book = Order_book.create Harness.aapl in
  let order = make_order ~side:Buy ~price_cents:15000 ~order_id:1 () in
  [%test_result: _ option] (Order_book.find_match book order) ~expect:None
;;

let%expect_test "find_match finds a tradable resting order" =
  let book = Order_book.create Harness.aapl in
  let resting = make_order ~side:Sell ~price_cents:15000 ~order_id:1 () in
  Order_book.add book resting;
  let incoming = make_order ~side:Buy ~price_cents:15000 ~order_id:2 () in
  let matched = Order_book.find_match book incoming in
  [%test_result: Order_id.t]
    (Order.order_id (Option.value_exn matched))
    ~expect:(Order.order_id resting)
;;

let%expect_test "find_match returns None when prices don't cross" =
  let book = Order_book.create Harness.aapl in
  Order_book.add
    book
    (make_order ~side:Sell ~price_cents:15100 ~order_id:1 ());
  let incoming = make_order ~side:Buy ~price_cents:15000 ~order_id:2 () in
  [%test_result: _ option] (Order_book.find_match book incoming) ~expect:None
;;

let%expect_test "find_match: buy matches against asks, not bids" =
  let book = Order_book.create Harness.aapl in
  Order_book.add
    book
    (make_order ~side:Buy ~price_cents:15000 ~order_id:1 ());
  let ask = make_order ~side:Sell ~price_cents:15000 ~order_id:2 () in
  Order_book.add book ask;
  let incoming = make_order ~side:Buy ~price_cents:15000 ~order_id:3 () in
  let matched = Order_book.find_match book incoming in
  [%test_result: Order_id.t]
    (Order.order_id (Option.value_exn matched))
    ~expect:(Order.order_id ask)
;;

(* --- best_bid_offer --- *)

let%expect_test "best_bid_offer: highest bid, lowest ask" =
  let book = Order_book.create Harness.aapl in
  let high_bid = 15050 in
  let low_ask = 15100 in
  Order_book.add
    book
    (make_order ~side:Buy ~price_cents:(high_bid - 50) ~order_id:1 ());
  Order_book.add
    book
    (make_order ~side:Buy ~price_cents:high_bid ~order_id:2 ());
  Order_book.add
    book
    (make_order ~side:Sell ~price_cents:(low_ask + 100) ~order_id:3 ());
  Order_book.add
    book
    (make_order ~side:Sell ~price_cents:low_ask ~order_id:4 ());
  let bbo = Order_book.best_bid_offer book in
  [%test_result: Price.t option]
    (Bbo.price bbo Buy)
    ~expect:(Some (Price.of_int_cents high_bid));
  [%test_result: Price.t option]
    (Bbo.price bbo Sell)
    ~expect:(Some (Price.of_int_cents low_ask))
;;

let%expect_test "best_bid_offer: empty book" =
  let book = Order_book.create Harness.aapl in
  [%test_result: Bbo.t] (Order_book.best_bid_offer book) ~expect:Bbo.empty
;;

let%expect_test "best_bid_offer: aggregates size at best level" =
  let book = Order_book.create Harness.aapl in
  let size1 = 50 in
  let size2 = 75 in
  Order_book.add
    book
    (make_order ~side:Sell ~price_cents:15000 ~order_id:1 ~size:size1 ());
  Order_book.add
    book
    (make_order ~side:Sell ~price_cents:15000 ~order_id:2 ~size:size2 ());
  Order_book.add
    book
    (make_order ~side:Sell ~price_cents:15100 ~order_id:3 ~size:200 ());
  let bbo = Order_book.best_bid_offer book in
  [%test_result: Level.t option]
    bbo.ask
    ~expect:
      (Some
         { price = Price.of_int_cents 15000
         ; size = Size.of_int (size1 + size2)
         })
;;

let%expect_test "best_bid_offer: tracks changes as orders are added" =
  let book = Order_book.create Harness.aapl in
  let buy_price = 14990 in
  let sell_price = 15010 in
  let print_bbo () =
    let bbo = Order_book.best_bid_offer book |> Bbo.to_string in
    print_endline [%string "BBO: %{bbo}"]
  in
  print_bbo ();
  Order_book.add
    book
    (make_order ~side:Buy ~price_cents:buy_price ~order_id:1 ());
  print_bbo ();
  Order_book.add
    book
    (make_order ~side:Sell ~price_cents:sell_price ~order_id:2 ());
  print_bbo ();
  [%expect
    {|
    BBO: - / -
    BBO: $149.90 x100 / -
    BBO: $149.90 x100 / $150.10 x100
    |}]
;;

(* --- snapshot --- *)

let%expect_test "snapshot lists levels in price-time priority order" =
  let book = Order_book.create Harness.aapl in
  (* Add bids and asks at varying prices, deliberately out of price order. *)
  Order_book.add
    book
    (make_order ~side:Buy ~price_cents:15000 ~order_id:1 ());
  Order_book.add
    book
    (make_order ~side:Buy ~price_cents:14990 ~order_id:2 ());
  Order_book.add
    book
    (make_order ~side:Buy ~price_cents:14995 ~order_id:3 ());
  Order_book.add
    book
    (make_order ~side:Sell ~price_cents:15010 ~order_id:4 ());
  Order_book.add
    book
    (make_order ~side:Sell ~price_cents:15005 ~order_id:5 ());
  Order_book.add
    book
    (make_order ~side:Sell ~price_cents:15015 ~order_id:6 ());
  print_endline (Order_book.snapshot book |> Book.to_string);
  (* The bids and asks below come out in reverse insertion order, not
     best-price-first. Once the book stores orders in price-time priority,
     bids should appear highest-first and asks lowest-first. *)
  [%expect
    {|
    === AAPL ===
      BIDS:
        $150.00 x100
        $149.95 x100
        $149.90 x100
      ASKS:
        $150.05 x100
        $150.10 x100
        $150.15 x100
      BBO: $150.00 x100 / $150.05 x100
    |}]
;;
