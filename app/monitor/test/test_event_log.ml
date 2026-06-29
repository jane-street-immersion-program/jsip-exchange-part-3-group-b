open! Core
open Jsip_types
open Jsip_test_harness
open Jsip_monitor
module Event_log = Event_log

let print_lines lines = List.iter lines ~f:print_endline

let print_styled lines =
  List.iter lines ~f:(fun (color, line) ->
    print_endline [%string "[%{color#Event_log.Color}] %{line}"])
;;

(* Build a log preloaded with [Harness.sample_events] — one of each
   exchange-event variant — so every filter test starts from the same shape. *)
let log_with_sample_events () =
  List.fold
    Harness.sample_events
    ~init:(Event_log.create ())
    ~f:Event_log.add_event
;;

(* ----- empty log ----- *)

let%expect_test "fresh log has no events and no visible output" =
  let log = Event_log.create () in
  print_endline [%string "count=%{Event_log.event_count log#Int}"];
  print_lines (Event_log.visible_lines log);
  [%expect {| count=0 |}]
;;

(* ----- adding events ----- *)

let%expect_test "events appear in insertion order" =
  let log = log_with_sample_events () in
  print_endline [%string "count=%{Event_log.event_count log#Int}"];
  print_lines (Event_log.visible_lines log);
  [%expect
    {|
    count=6
    ACCEPTED server_id=1 client_id=1 AAPL BUY 100@$150.00 DAY
    FILL fill_id=1 AAPL $150.00 x100 aggressor=[server_id=2 client_id=2 Alice] BUY resting=[server_id=1 client_id=1 Bob]
    CANCELLED server_id=1 client_id=1 AAPL remaining=50 reason=IOC_REMAINDER
    REJECTED client_id=1 AAPL BUY 100@$150.00 reason=unknown symbol
    BBO AAPL bid=$149.90 x100 ask=$150.10 x200
    TRADE AAPL $150.00 x100
    |}]
;;

(* ----- filter: substring ----- *)

let%expect_test "filter by substring keeps only matching lines" =
  let log = log_with_sample_events () in
  let log =
    Event_log.set_filter log (Event_log.Filter.by_substring "fill")
  in
  print_lines (Event_log.visible_lines log);
  [%expect
    {| FILL fill_id=1 AAPL $150.00 x100 aggressor=[server_id=2 client_id=2 Alice] BUY resting=[server_id=1 client_id=1 Bob] |}]
;;

let%expect_test "substring filter is case-insensitive" =
  let log = log_with_sample_events () in
  let log = Event_log.set_filter log (Event_log.Filter.by_substring "bbo") in
  print_lines (Event_log.visible_lines log);
  [%expect {| BBO AAPL bid=$149.90 x100 ask=$150.10 x200 |}]
;;

(* ----- filter: categories ----- *)

let%expect_test "filter by category groups variants" =
  let log = log_with_sample_events () in
  let log =
    Event_log.set_filter
      log
      (Event_log.Filter.by_categories [ Order_lifecycle ])
  in
  print_lines (Event_log.visible_lines log);
  [%expect
    {|
    ACCEPTED server_id=1 client_id=1 AAPL BUY 100@$150.00 DAY
    CANCELLED server_id=1 client_id=1 AAPL remaining=50 reason=IOC_REMAINDER
    REJECTED client_id=1 AAPL BUY 100@$150.00 reason=unknown symbol
    |}]
;;

let%expect_test "market-data category covers BBO and trade reports" =
  let log = log_with_sample_events () in
  let log =
    Event_log.set_filter log (Event_log.Filter.by_categories [ Market_data ])
  in
  print_lines (Event_log.visible_lines log);
  [%expect
    {|
    BBO AAPL bid=$149.90 x100 ask=$150.10 x200
    TRADE AAPL $150.00 x100
    |}]
;;

(* ----- filter: combining ----- *)

let%expect_test "combined filters intersect" =
  let log = log_with_sample_events () in
  let f =
    Event_log.Filter.combine
      (Event_log.Filter.by_categories [ Market_data ])
      (Event_log.Filter.by_substring "150.00")
  in
  let log = Event_log.set_filter log f in
  print_lines (Event_log.visible_lines log);
  [%expect {| TRADE AAPL $150.00 x100 |}]
;;

(* ----- styled rendering ----- *)

let%expect_test "each event variant renders with its assigned color" =
  let log = log_with_sample_events () in
  print_styled (Event_log.visible_styled_lines log);
  [%expect
    {|
    [green] ACCEPTED server_id=1 client_id=1 AAPL BUY 100@$150.00 DAY
    [cyan] FILL fill_id=1 AAPL $150.00 x100 aggressor=[server_id=2 client_id=2 Alice] BUY resting=[server_id=1 client_id=1 Bob]
    [yellow] CANCELLED server_id=1 client_id=1 AAPL remaining=50 reason=IOC_REMAINDER
    [red] REJECTED client_id=1 AAPL BUY 100@$150.00 reason=unknown symbol
    [blue] BBO AAPL bid=$149.90 x100 ask=$150.10 x200
    [magenta] TRADE AAPL $150.00 x100
    |}]
;;

let print_bbos log =
  List.iter (Event_log.current_bbos log) ~f:(fun (symbol, bbo) ->
    print_endline [%string "%{symbol#Symbol}: %{bbo#Bbo}"])
;;

let%expect_test "current_bbos tracks latest BBO per symbol in \
                 first-appearance order"
  =
  let aapl = Symbol.of_string "AAPL" in
  let tsla = Symbol.of_string "TSLA" in
  let bbo bid_cents ask_cents : Bbo.t =
    { bid =
        Some { price = Price.of_int_cents bid_cents; size = Size.of_int 100 }
    ; ask =
        Some { price = Price.of_int_cents ask_cents; size = Size.of_int 200 }
    }
  in
  let event symbol bbo : Exchange_event.t =
    Best_bid_offer_update { symbol; bbo }
  in
  let log =
    List.fold
      [ event aapl (bbo 14990 15010)
      ; event tsla (bbo 24990 25010)
      ; event aapl (bbo 14995 15005)
      ]
      ~init:(Event_log.create ())
      ~f:Event_log.add_event
  in
  print_bbos log;
  [%expect
    {|
    AAPL: $149.95 x100 / $150.05 x200
    TSLA: $249.90 x100 / $250.10 x200
    |}]
;;

let%expect_test "every variant of [Harness.sample_events] gets a distinct \
                 color"
  =
  let colors = List.map Harness.sample_events ~f:Event_log.Color.of_event in
  let unique =
    List.dedup_and_sort colors ~compare:Event_log.Color.compare
    |> List.length
  in
  [%test_result: int]
    ~message:"Color.of_event should return a unique color per event variant"
    unique
    ~expect:(List.length Harness.sample_events)
;;
