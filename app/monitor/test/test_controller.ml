open! Core
open Jsip_test_harness
open Jsip_monitor
module Controller = Controller
module Key = Bonsai_term.Event.Key

let feed_all c =
  List.fold Harness.sample_events ~init:c ~f:Controller.feed_event
;;

let press c key = Controller.handle_key c (key : Key.t)

let press_chars c chars =
  List.fold chars ~init:c ~f:(fun c ch -> press c (Key.ASCII ch))
;;

(* Render the same [View.t] the bonsai_term loop renders, but through Notty's
   "dumb" capability so the snapshot is plain ASCII rather than escape codes.
   Color information is lost — that is verified separately at the
   [Controller.Display.t] level via [visible_events]. *)
let render_to_string view =
  let { Bonsai_term.Dimensions.height; width } =
    Bonsai_term.View.dimensions view
  in
  let buf = Buffer.create (width * height) in
  let img = Bonsai_term.View.Private.notty_image view in
  Notty.Render.to_buffer buf Notty.Cap.dumb (0, 0) (width, height) img;
  Buffer.contents buf
;;

let show c =
  print_endline
    (render_to_string
       (Term_app.For_testing.render_display (Controller.display c)))
;;

(* ---------- Initial state ---------- *)

let%expect_test "initial state has every chip enabled and no events" =
  let c = Controller.create () in
  show c;
  [%expect
    {|
    JSIP Exchange Monitor   0 of 0 events   auto-scroll ↓
    BBO:        (no quotes yet)
    Categories: [1 order-lifecycle]  [2 trade]  [3 market-data]
    Substring:  (empty)
    ──────────────────────────────────────────────────────────────────────
      (no events visible)
    ──────────────────────────────────────────────────────────────────────
    Footer:      q=quit  r=reset  1-3=categories  /=substring  a=auto-scroll
    |}]
;;

(* ---------- Feeding events ---------- *)

let%expect_test "feeding sample events populates the display" =
  let c = feed_all (Controller.create ()) in
  show c;
  [%expect
    {|
    JSIP Exchange Monitor   6 of 6 events   auto-scroll ↓
    BBO:        AAPL: $149.90 x100 / $150.10 x200
    Categories: [1 order-lifecycle]  [2 trade]  [3 market-data]
    Substring:  (empty)
    ──────────────────────────────────────────────────────────────────────
    ACCEPTED server_id=1 client_id=1 AAPL BUY 100@$150.00 DAY
    FILL fill_id=1 AAPL $150.00 x100 aggressor=[server_id=2 client_id=2 Alice] BUY resting=[server_id=1 client_id=1 Bob]
    CANCELLED server_id=1 client_id=1 AAPL remaining=50 reason=IOC_REMAINDER
    REJECTED client_id=1 AAPL BUY 100@$150.00 reason=unknown symbol
    BBO AAPL bid=$149.90 x100 ask=$150.10 x200
    TRADE AAPL $150.00 x100
    ──────────────────────────────────────────────────────────────────────
    Footer:      q=quit  r=reset  1-3=categories  /=substring  a=auto-scroll
    |}]
;;

(* ---------- Quit ---------- *)

let exits_after_press key =
  let c = Controller.create () in
  let c = Controller.handle_key c key in
  Controller.should_exit c
;;

let%expect_test "pressing q sets should_exit" =
  [%test_result: bool] (exits_after_press (Key.ASCII 'q')) ~expect:true
;;

let%expect_test "no other browsing-mode key sets should_exit" =
  let check_no_exit key =
    [%test_result: bool]
      ~message:(Sexp.to_string [%sexp (key : Key.t)])
      (exits_after_press key)
      ~expect:false
  in
  check_no_exit (Key.ASCII 'c');
  check_no_exit (Key.ASCII 'r');
  check_no_exit (Key.ASCII '1');
  check_no_exit (Key.ASCII '/');
  check_no_exit Key.Escape;
  check_no_exit Key.Enter
;;

(* ---------- Category toggles ---------- *)

let%expect_test "pressing 1 toggles the order-lifecycle category off and \
                 back on"
  =
  let c = feed_all (Controller.create ()) in
  let c = press c (ASCII '1') in
  show c;
  print_endline "----- toggle 1 again -----";
  let c = press c (ASCII '1') in
  show c;
  [%expect
    {|
    JSIP Exchange Monitor   3 of 6 events   auto-scroll ↓
    BBO:        AAPL: $149.90 x100 / $150.10 x200
    Categories: (1 order-lifecycle)  [2 trade]  [3 market-data]
    Substring:  (empty)
    ──────────────────────────────────────────────────────────────────────
    FILL fill_id=1 AAPL $150.00 x100 aggressor=[server_id=2 client_id=2 Alice] BUY resting=[server_id=1 client_id=1 Bob]
    BBO AAPL bid=$149.90 x100 ask=$150.10 x200
    TRADE AAPL $150.00 x100
    ──────────────────────────────────────────────────────────────────────
    Footer:      q=quit  r=reset  1-3=categories  /=substring  a=auto-scroll
    ----- toggle 1 again -----
    JSIP Exchange Monitor   6 of 6 events   auto-scroll ↓
    BBO:        AAPL: $149.90 x100 / $150.10 x200
    Categories: [1 order-lifecycle]  [2 trade]  [3 market-data]
    Substring:  (empty)
    ──────────────────────────────────────────────────────────────────────
    ACCEPTED server_id=1 client_id=1 AAPL BUY 100@$150.00 DAY
    FILL fill_id=1 AAPL $150.00 x100 aggressor=[server_id=2 client_id=2 Alice] BUY resting=[server_id=1 client_id=1 Bob]
    CANCELLED server_id=1 client_id=1 AAPL remaining=50 reason=IOC_REMAINDER
    REJECTED client_id=1 AAPL BUY 100@$150.00 reason=unknown symbol
    BBO AAPL bid=$149.90 x100 ask=$150.10 x200
    TRADE AAPL $150.00 x100
    ──────────────────────────────────────────────────────────────────────
    Footer:      q=quit  r=reset  1-3=categories  /=substring  a=auto-scroll
    |}]
;;

let%expect_test "pressing 2 toggles trade; 3 toggles market-data" =
  let c = feed_all (Controller.create ()) in
  let c = press c (ASCII '2') in
  let c = press c (ASCII '3') in
  show c;
  [%expect
    {|
    JSIP Exchange Monitor   3 of 6 events   auto-scroll ↓
    BBO:        AAPL: $149.90 x100 / $150.10 x200
    Categories: [1 order-lifecycle]  (2 trade)  (3 market-data)
    Substring:  (empty)
    ──────────────────────────────────────────────────────────────────────
    ACCEPTED server_id=1 client_id=1 AAPL BUY 100@$150.00 DAY
    CANCELLED server_id=1 client_id=1 AAPL remaining=50 reason=IOC_REMAINDER
    REJECTED client_id=1 AAPL BUY 100@$150.00 reason=unknown symbol
    ──────────────────────────────────────────────────────────────────────
    Footer:      q=quit  r=reset  1-3=categories  /=substring  a=auto-scroll
    |}]
;;

let%expect_test "disabling every category hides every event" =
  let c = feed_all (Controller.create ()) in
  let c = press_chars c [ '1'; '2'; '3' ] in
  show c;
  [%expect
    {|
    JSIP Exchange Monitor   0 of 6 events   auto-scroll ↓
    BBO:        AAPL: $149.90 x100 / $150.10 x200
    Categories: (1 order-lifecycle)  (2 trade)  (3 market-data)
    Substring:  (empty)
    ──────────────────────────────────────────────────────────────────────
      (no events visible)
    ──────────────────────────────────────────────────────────────────────
    Footer:      q=quit  r=reset  1-3=categories  /=substring  a=auto-scroll
    |}]
;;

(* ---------- Substring filter editing ---------- *)

let%expect_test "pressing / enters editing mode with empty buffer" =
  let c = feed_all (Controller.create ()) in
  let c = press c (ASCII '/') in
  show c;
  [%expect
    {|
    JSIP Exchange Monitor   6 of 6 events   auto-scroll ↓
    BBO:        AAPL: $149.90 x100 / $150.10 x200
    Categories: [1 order-lifecycle]  [2 trade]  [3 market-data]
    Substring:  _  (editing)
    [editing substring]
    ──────────────────────────────────────────────────────────────────────
    ACCEPTED server_id=1 client_id=1 AAPL BUY 100@$150.00 DAY
    FILL fill_id=1 AAPL $150.00 x100 aggressor=[server_id=2 client_id=2 Alice] BUY resting=[server_id=1 client_id=1 Bob]
    CANCELLED server_id=1 client_id=1 AAPL remaining=50 reason=IOC_REMAINDER
    REJECTED client_id=1 AAPL BUY 100@$150.00 reason=unknown symbol
    BBO AAPL bid=$149.90 x100 ask=$150.10 x200
    TRADE AAPL $150.00 x100
    ──────────────────────────────────────────────────────────────────────
    Footer:      Enter=commit  ESC=cancel  Backspace=delete  (other keys append)
    |}]
;;

let%expect_test "typing in edit mode appends to the buffer" =
  let c = feed_all (Controller.create ()) in
  let c = press c (ASCII '/') in
  let c = press_chars c [ 'f'; 'i'; 'l'; 'l' ] in
  show c;
  [%expect
    {|
    JSIP Exchange Monitor   1 of 6 events   auto-scroll ↓
    BBO:        AAPL: $149.90 x100 / $150.10 x200
    Categories: [1 order-lifecycle]  [2 trade]  [3 market-data]
    Substring:  fill_  (editing)
    [editing substring]
    ──────────────────────────────────────────────────────────────────────
    FILL fill_id=1 AAPL $150.00 x100 aggressor=[server_id=2 client_id=2 Alice] BUY resting=[server_id=1 client_id=1 Bob]
    ──────────────────────────────────────────────────────────────────────
    Footer:      Enter=commit  ESC=cancel  Backspace=delete  (other keys append)
    |}]
;;

let%expect_test "Enter commits the substring filter and returns to browsing" =
  let c = feed_all (Controller.create ()) in
  let c = press c (ASCII '/') in
  let c = press_chars c [ 'f'; 'i'; 'l'; 'l' ] in
  let c = press c Key.Enter in
  show c;
  [%expect
    {|
    JSIP Exchange Monitor   1 of 6 events   auto-scroll ↓
    BBO:        AAPL: $149.90 x100 / $150.10 x200
    Categories: [1 order-lifecycle]  [2 trade]  [3 market-data]
    Substring:  fill
    ──────────────────────────────────────────────────────────────────────
    FILL fill_id=1 AAPL $150.00 x100 aggressor=[server_id=2 client_id=2 Alice] BUY resting=[server_id=1 client_id=1 Bob]
    ──────────────────────────────────────────────────────────────────────
    Footer:      q=quit  r=reset  1-3=categories  /=substring  a=auto-scroll
    |}]
;;

let%expect_test "Escape cancels edit mode and reverts the buffer" =
  let c = feed_all (Controller.create ()) in
  let c = press c (ASCII '/') in
  let c = press_chars c [ 'b'; 'b'; 'o' ] in
  let c = press c Key.Escape in
  show c;
  [%expect
    {|
    JSIP Exchange Monitor   6 of 6 events   auto-scroll ↓
    BBO:        AAPL: $149.90 x100 / $150.10 x200
    Categories: [1 order-lifecycle]  [2 trade]  [3 market-data]
    Substring:  (empty)
    ──────────────────────────────────────────────────────────────────────
    ACCEPTED server_id=1 client_id=1 AAPL BUY 100@$150.00 DAY
    FILL fill_id=1 AAPL $150.00 x100 aggressor=[server_id=2 client_id=2 Alice] BUY resting=[server_id=1 client_id=1 Bob]
    CANCELLED server_id=1 client_id=1 AAPL remaining=50 reason=IOC_REMAINDER
    REJECTED client_id=1 AAPL BUY 100@$150.00 reason=unknown symbol
    BBO AAPL bid=$149.90 x100 ask=$150.10 x200
    TRADE AAPL $150.00 x100
    ──────────────────────────────────────────────────────────────────────
    Footer:      q=quit  r=reset  1-3=categories  /=substring  a=auto-scroll
    |}]
;;

let%expect_test "Backspace in edit mode pops the last character" =
  let c = feed_all (Controller.create ()) in
  let c = press c (ASCII '/') in
  let c = press_chars c [ 'f'; 'i'; 'z'; 'z' ] in
  let c = press c Key.Backspace in
  let c = press c Key.Backspace in
  show c;
  [%expect
    {|
    JSIP Exchange Monitor   1 of 6 events   auto-scroll ↓
    BBO:        AAPL: $149.90 x100 / $150.10 x200
    Categories: [1 order-lifecycle]  [2 trade]  [3 market-data]
    Substring:  fi_  (editing)
    [editing substring]
    ──────────────────────────────────────────────────────────────────────
    FILL fill_id=1 AAPL $150.00 x100 aggressor=[server_id=2 client_id=2 Alice] BUY resting=[server_id=1 client_id=1 Bob]
    ──────────────────────────────────────────────────────────────────────
    Footer:      Enter=commit  ESC=cancel  Backspace=delete  (other keys append)
    |}]
;;

(* ---------- Reset ---------- *)

let%expect_test "pressing r clears every filter back to defaults" =
  let c = feed_all (Controller.create ()) in
  let c = press c (ASCII '1') in
  let c = press c (ASCII '/') in
  let c = press_chars c [ 'f'; 'i'; 'l'; 'l' ] in
  let c = press c Key.Enter in
  print_endline "----- after toggling and committing 'fill' -----";
  show c;
  let c = press c (ASCII 'r') in
  print_endline "----- after r -----";
  show c;
  [%expect
    {|
    ----- after toggling and committing 'fill' -----
    JSIP Exchange Monitor   1 of 6 events   auto-scroll ↓
    BBO:        AAPL: $149.90 x100 / $150.10 x200
    Categories: (1 order-lifecycle)  [2 trade]  [3 market-data]
    Substring:  fill
    ──────────────────────────────────────────────────────────────────────
    FILL fill_id=1 AAPL $150.00 x100 aggressor=[server_id=2 client_id=2 Alice] BUY resting=[server_id=1 client_id=1 Bob]
    ──────────────────────────────────────────────────────────────────────
    Footer:      q=quit  r=reset  1-3=categories  /=substring  a=auto-scroll
    ----- after r -----
    JSIP Exchange Monitor   6 of 6 events   auto-scroll ↓
    BBO:        AAPL: $149.90 x100 / $150.10 x200
    Categories: [1 order-lifecycle]  [2 trade]  [3 market-data]
    Substring:  (empty)
    ──────────────────────────────────────────────────────────────────────
    ACCEPTED server_id=1 client_id=1 AAPL BUY 100@$150.00 DAY
    FILL fill_id=1 AAPL $150.00 x100 aggressor=[server_id=2 client_id=2 Alice] BUY resting=[server_id=1 client_id=1 Bob]
    CANCELLED server_id=1 client_id=1 AAPL remaining=50 reason=IOC_REMAINDER
    REJECTED client_id=1 AAPL BUY 100@$150.00 reason=unknown symbol
    BBO AAPL bid=$149.90 x100 ask=$150.10 x200
    TRADE AAPL $150.00 x100
    ──────────────────────────────────────────────────────────────────────
    Footer:      q=quit  r=reset  1-3=categories  /=substring  a=auto-scroll
    |}]
;;

(* ---------- Counter ---------- *)

let%expect_test "counter reflects visible / total even when filters are \
                 active"
  =
  let c = feed_all (Controller.create ()) in
  let c = press c (ASCII '/') in
  let c = press_chars c [ 'b'; 'b'; 'o' ] in
  let c = press c Key.Enter in
  show c;
  [%expect
    {|
    JSIP Exchange Monitor   1 of 6 events   auto-scroll ↓
    BBO:        AAPL: $149.90 x100 / $150.10 x200
    Categories: [1 order-lifecycle]  [2 trade]  [3 market-data]
    Substring:  bbo
    ──────────────────────────────────────────────────────────────────────
    BBO AAPL bid=$149.90 x100 ask=$150.10 x200
    ──────────────────────────────────────────────────────────────────────
    Footer:      q=quit  r=reset  1-3=categories  /=substring  a=auto-scroll
    |}]
;;
