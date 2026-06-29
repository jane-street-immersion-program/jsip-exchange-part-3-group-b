open! Core
open Jsip_types
open Jsip_order_book
open Jsip_gateway

let print_parse line =
  match Exchange_command.parse line with
  | Error msg -> print_endline [%string "ERROR: %{Error.to_string_hum msg}"]
  | Ok cmd -> print_endline [%string "%{cmd#Exchange_command}"]
;;

(* --- Successful parsing --- *)

let%expect_test "parse: basic buy" =
  print_parse "BUY 1 AAPL 100 150.25";
  [%expect
    {| (Submit((client_order_id 1)(symbol AAPL)(side Buy)(price 15025)(size 100)(time_in_force Day))) |}]
;;

let%expect_test "parse: basic sell" =
  print_parse "SELL 2 TSLA 50 200.00";
  [%expect
    {| (Submit((client_order_id 2)(symbol TSLA)(side Sell)(price 20000)(size 50)(time_in_force Day))) |}]
;;

let%expect_test "parse: case insensitive command keyword" =
  print_parse "login Alice";
  print_parse "buy 1 AAPL 100 150.00";
  print_parse "Buy 2 AAPL 100 150.00";
  [%expect
    {|
    (Login(name Alice))
    (Submit((client_order_id 1)(symbol AAPL)(side Buy)(price 15000)(size 100)(time_in_force Day)))
    (Submit((client_order_id 2)(symbol AAPL)(side Buy)(price 15000)(size 100)(time_in_force Day)))
    |}]
;;

let%expect_test "parse: with IOC time-in-force" =
  print_parse "BUY 1 AAPL 100 150.00 IOC";
  [%expect
    {| (Submit((client_order_id 1)(symbol AAPL)(side Buy)(price 15000)(size 100)(time_in_force Ioc))) |}]
;;

let%expect_test "parse: with explicit DAY" =
  print_parse "SELL 7 AAPL 200 151.00 DAY";
  [%expect
    {| (Submit((client_order_id 7)(symbol AAPL)(side Sell)(price 15100)(size 200)(time_in_force Day))) |}]
;;

let%expect_test "parse: symbol is uppercased" =
  print_parse "BUY 1 aapl 100 150.00";
  [%expect
    {| (Submit((client_order_id 1)(symbol aapl)(side Buy)(price 15000)(size 100)(time_in_force Day))) |}]
;;

let%expect_test "parse: extra whitespace is ignored" =
  print_parse "  BUY   1   AAPL   100   150.00  ";
  [%expect
    {| (Submit((client_order_id 1)(symbol AAPL)(side Buy)(price 15000)(size 100)(time_in_force Day))) |}]
;;

let%expect_test "parse: price with dollar sign" =
  print_parse "BUY 1 AAPL 100 $150.25";
  [%expect
    {| (Submit((client_order_id 1)(symbol AAPL)(side Buy)(price 15025)(size 100)(time_in_force Day))) |}]
;;

let%expect_test "parse: login" =
  print_parse "LOGIN Alice";
  [%expect {| (Login(name Alice)) |}]
;;

let%expect_test "parse: cancel" =
  print_parse "CANCEL 42";
  [%expect {| (Cancel(client_order_id 42)) |}]
;;

let%expect_test "parse: book with symbol" =
  print_parse "BOOK AAPL";
  [%expect {| (Book AAPL) |}]
;;

let%expect_test "parse: subscribe case-insensitive" =
  print_parse "SUBSCRIBE aapl";
  [%expect {| (Subscribe aapl) |}]
;;

(* --- Parse errors --- *)

let%expect_test "parse error: empty string" =
  print_parse "";
  print_parse "   ";
  [%expect {|
    ERROR: empty command
    ERROR: empty command
    |}]
;;

let%expect_test "parse error: unknown command" =
  print_parse "HOLD AAPL 100 150.00";
  [%expect {| ERROR: unrecognized command: HOLD |}]
;;

let%expect_test "parse error: missing fields" =
  print_parse "BUY 1 AAPL";
  print_parse "BUY";
  [%expect
    {|
    ERROR: expected: BUY|SELL <client_id> <symbol> <size> <price> [DAY|IOC]
    ERROR: expected: BUY|SELL <client_id> <symbol> <size> <price> [DAY|IOC]
    |}]
;;

let%expect_test "parse error: invalid client order id" =
  print_parse "BUY AAPL 100 150.00";
  print_parse "BUY -1 AAPL 100 150.00";
  [%expect
    {|
    ERROR: expected: BUY|SELL <client_id> <symbol> <size> <price> [DAY|IOC]
    ERROR: client order id must be non-negative
    |}]
;;

let%expect_test "parse error: invalid size" =
  print_parse "BUY 1 AAPL abc 150.00";
  print_parse "BUY 1 AAPL 0 150.00";
  print_parse "BUY 1 AAPL -5 150.00";
  [%expect
    {|
    ERROR: invalid size: abc
    ERROR: size must be positive
    ERROR: size must be positive
    |}]
;;

let%expect_test "parse error: invalid price" =
  print_parse "BUY 1 AAPL 100 xyz";
  [%expect
    {|
    ERROR: invalid price: xyz
    exception: (Invalid_argument "Float.of_string xyz")
    |}]
;;

let%expect_test "parse error: unknown time-in-force" =
  print_parse "BUY 1 AAPL 100 150.00 QQQ";
  [%expect {| ERROR: unknown time-in-force: QQQ (expected [DAY|IOC]) |}]
;;

let%expect_test "parse error: LOGIN missing name" =
  print_parse "LOGIN";
  [%expect {| ERROR: expected: LOGIN <participant_name> |}]
;;

let%expect_test "parse error: CANCEL missing id" =
  print_parse "CANCEL";
  [%expect {| ERROR: expected: CANCEL <client_order_id> |}]
;;

let%expect_test "parse error: trailing arguments after order" =
  print_parse "BUY 1 AAPL 100 150.00 DAY extra stuff";
  [%expect {| ERROR: unexpected trailing arguments: DAY extra stuff |}]
;;

(* --- Event formatting --- *)

let%expect_test "format_event: all event types" =
  let events =
    [ Exchange_event.Order_accept
        { order_id = Order_id.of_string "1"
        ; participant = Participant.of_string "Alice"
        ; request =
            { client_order_id = Client_order_id.of_int 10
            ; symbol = Symbol.of_string "AAPL"
            ; side = Buy
            ; price = Price.of_int_cents 15000
            ; size = Size.of_int 100
            ; time_in_force = Day
            }
        }
    ; Fill
        { fill_id = 1
        ; symbol = Symbol.of_string "AAPL"
        ; price = Price.of_int_cents 15000
        ; size = Size.of_int 100
        ; aggressor_order_id = Order_id.of_string "2"
        ; aggressor_client_order_id = Client_order_id.of_int 20
        ; aggressor_participant = Participant.of_string "Alice"
        ; aggressor_side = Buy
        ; resting_order_id = Order_id.of_string "1"
        ; resting_client_order_id = Client_order_id.of_int 17
        ; resting_participant = Participant.of_string "Bob"
        }
    ; Order_cancel
        { order_id = Order_id.of_string "3"
        ; client_order_id = Client_order_id.of_int 7
        ; participant = Participant.of_string "Charlie"
        ; symbol = Symbol.of_string "TSLA"
        ; remaining_size = Size.of_int 50
        ; reason = Ioc_remainder
        }
    ; Order_reject
        { participant = Participant.of_string "Alice"
        ; request =
            { client_order_id = Client_order_id.of_int 42
            ; symbol = Symbol.of_string "GOOG"
            ; side = Sell
            ; price = Price.of_int_cents 28000
            ; size = Size.of_int 10
            ; time_in_force = Day
            }
        ; reason = "unknown symbol"
        }
    ; Cancel_reject
        { participant = Participant.of_string "Alice"
        ; client_order_id = Client_order_id.of_int 42
        ; reason = "order not found"
        }
    ; Best_bid_offer_update
        { symbol = Symbol.of_string "AAPL"
        ; bbo =
            { bid =
                Some
                  { price = Price.of_int_cents 14990
                  ; size = Size.of_int 200
                  }
            ; ask =
                Some
                  { price = Price.of_int_cents 15010
                  ; size = Size.of_int 100
                  }
            }
        }
    ; Best_bid_offer_update
        { symbol = Symbol.of_string "AAPL"; bbo = Bbo.empty }
    ; Trade_report
        { symbol = Symbol.of_string "AAPL"
        ; price = Price.of_int_cents 15000
        ; size = Size.of_int 100
        }
    ]
  in
  List.iter events ~f:(fun e -> print_endline (Protocol.format_event e));
  [%expect
    {|
    ACCEPTED server_id=1 client_id=10 AAPL BUY 100@$150.00 DAY
    FILL fill_id=1 AAPL $150.00 x100 aggressor=[server_id=2 client_id=20 Alice] BUY resting=[server_id=1 client_id=17 Bob]
    CANCELLED server_id=3 client_id=7 TSLA remaining=50 reason=IOC_REMAINDER
    REJECTED client_id=42 GOOG SELL 10@$280.00 reason=unknown symbol
    CANCEL REJECTED client_id=42 reason=order not found
    BBO AAPL bid=$149.90 x200 ask=$150.10 x100
    BBO AAPL bid=- ask=-
    TRADE AAPL $150.00 x100
    |}]
;;

(* --- Round-trip: parse then format --- *)

let%expect_test "round-trip: parse a command, submit, format result" =
  let open Jsip_test_harness in
  let t = Harness.create () in
  Harness.submit_
    ~participant:Harness.bob
    t
    (Harness.sell ~price_cents:15000 ());
  (match Exchange_command.parse "BUY 2 AAPL 100 150.00" with
   | Error msg -> printf "parse error: %s\n" (Error.to_string_hum msg)
   | Ok (Submit request) ->
     let events =
       Matching_engine.submit
         (Harness.engine t)
         ~participant:Harness.alice
         request
     in
     printf "%s\n" (Protocol.format_events events)
   | Ok cmd ->
     print_string [%string "unexpected command: %{cmd#Exchange_command}\n"]);
  [%expect
    {|
    ACCEPTED server_id=1 client_id=101 AAPL SELL 100@$150.00 DAY
    BBO AAPL bid=- ask=$150.00 x100
    ACCEPTED server_id=2 client_id=2 AAPL BUY 100@$150.00 DAY
    FILL fill_id=1 AAPL $150.00 x100 aggressor=[server_id=2 client_id=2 Alice] BUY resting=[server_id=1 client_id=101 Bob]
    TRADE AAPL $150.00 x100
    BBO AAPL bid=- ask=-
    |}]
;;
