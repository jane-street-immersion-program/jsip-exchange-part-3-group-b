(** End-to-end tests with a real server and RPC clients.

    These tests spin up an actual exchange server on a local port, connect
    one or more clients via RPC, log them in, and verify the full path:
    client -> network -> server -> matching engine -> dispatcher -> session
    feed -> client. *)

open! Core
open! Async
open Jsip_types
open Jsip_gateway
open Jsip_test_harness
open E2e_helpers

(* ---------------------------------------------------------------- *)
(* Multiple client tests *)
(* ---------------------------------------------------------------- *)

let%expect_test "e2e: two clients trade with each other" =
  with_server ~symbols:[ Harness.aapl ] (fun ~server:_ ~port ->
    let%bind alice = connect_as ~port ~participant:Harness.alice in
    let%bind bob = connect_as ~port ~participant:Harness.bob in
    (* Bob places a sell *)
    let%bind () = rpc_submit bob (Harness.sell ~price_cents:15000 ()) in
    [%expect
      {| [Bob] ACCEPTED server_id=1 client_id=101 AAPL SELL 100@$150.00 DAY |}];
    (* Alice places a buy — should cross *)
    let%bind () = rpc_submit alice (Harness.buy ~price_cents:15000 ()) in
    [%expect
      {|
      [Alice] ACCEPTED server_id=2 client_id=102 AAPL BUY 100@$150.00 DAY
      [Alice] FILL fill_id=1 AAPL $150.00 x100 aggressor=[server_id=2 client_id=102 Alice] BUY resting=[server_id=1 client_id=101 Bob]
      [Bob] FILL fill_id=1 AAPL $150.00 x100 aggressor=[server_id=2 client_id=102 Alice] BUY resting=[server_id=1 client_id=101 Bob]
      |}];
    return ())
;;

let%expect_test "e2e: three clients, sequential orders, shared book" =
  with_server ~symbols:[ Harness.aapl ] (fun ~server:_ ~port ->
    let%bind alice = connect_as ~port ~participant:Harness.alice in
    let%bind bob = connect_as ~port ~participant:Harness.bob in
    let%bind charlie = connect_as ~port ~participant:Harness.charlie in
    (* Bob posts a sell *)
    let%bind () =
      rpc_submit bob (Harness.sell ~price_cents:15000 ~size:50 ())
    in
    [%expect
      {| [Bob] ACCEPTED server_id=1 client_id=101 AAPL SELL 50@$150.00 DAY |}];
    (* Charlie posts a sell at a higher price *)
    let%bind () =
      rpc_submit charlie (Harness.sell ~price_cents:15010 ~size:50 ())
    in
    [%expect
      {| [Charlie] ACCEPTED server_id=2 client_id=102 AAPL SELL 50@$150.10 DAY |}];
    (* Alice buys 80 — should sweep through both *)
    let%bind () =
      rpc_submit alice (Harness.buy ~price_cents:15010 ~size:80 ())
    in
    [%expect
      {|
      [Alice] ACCEPTED server_id=3 client_id=103 AAPL BUY 80@$150.10 DAY
      [Alice] FILL fill_id=1 AAPL $150.00 x50 aggressor=[server_id=3 client_id=103 Alice] BUY resting=[server_id=1 client_id=101 Bob]
      [Alice] FILL fill_id=2 AAPL $150.10 x30 aggressor=[server_id=3 client_id=103 Alice] BUY resting=[server_id=2 client_id=102 Charlie]
      [Bob] FILL fill_id=1 AAPL $150.00 x50 aggressor=[server_id=3 client_id=103 Alice] BUY resting=[server_id=1 client_id=101 Bob]
      [Charlie] FILL fill_id=2 AAPL $150.10 x30 aggressor=[server_id=3 client_id=103 Alice] BUY resting=[server_id=2 client_id=102 Charlie]
      |}];
    (* Verify book state *)
    let%bind book = rpc_book alice Harness.aapl in
    print_endline (Option.value_exn book |> Book.to_string);
    [%expect
      {|
      === AAPL ===
        BIDS: (empty)
        ASKS:
          $150.10 x20
        BBO: - / $150.10 x20
      |}];
    return ())
;;

(* ---------------------------------------------------------------- *)
(* Market data subscription tests *)
(* ---------------------------------------------------------------- *)

let%expect_test "e2e: market data subscriber receives trade and BBO updates" =
  with_server ~symbols:[ Harness.aapl ] (fun ~server:_ ~port ->
    let%bind sub =
      connect_as ~port ~participant:(Participant.of_string "Sub")
    in
    let%bind bob = connect_as ~port ~participant:Harness.bob in
    let%bind result =
      Rpc.Pipe_rpc.dispatch
        Rpc_protocol.market_data_rpc
        (connection sub)
        [ Harness.aapl ]
    in
    let reader =
      match result with
      | Ok (Ok (reader, _id)) -> reader
      | _ -> failwith "subscribe failed"
    in
    don't_wait_for
      (Pipe.iter_without_pushback reader ~f:(fun event ->
         let e = Protocol.format_event event in
         print_endline [%string "[MD Subscriber] %{e}"]));
    (* Post a sell *)
    let%bind () = rpc_submit bob (Harness.sell ~price_cents:15000 ()) in
    [%expect
      {|
      [Bob] ACCEPTED server_id=1 client_id=101 AAPL SELL 100@$150.00 DAY
      [MD Subscriber] BBO AAPL bid=- ask=$150.00 x100
      |}];
    (* Cross it with a buy — Alice logs in on a separate connection *)
    let%bind alice = connect_as ~port ~participant:Harness.alice in
    let%bind () = rpc_submit alice (Harness.buy ~price_cents:15000 ()) in
    [%expect
      {|
      [Alice] ACCEPTED server_id=2 client_id=102 AAPL BUY 100@$150.00 DAY
      [Alice] FILL fill_id=1 AAPL $150.00 x100 aggressor=[server_id=2 client_id=102 Alice] BUY resting=[server_id=1 client_id=101 Bob]
      [Bob] FILL fill_id=1 AAPL $150.00 x100 aggressor=[server_id=2 client_id=102 Alice] BUY resting=[server_id=1 client_id=101 Bob]
      [MD Subscriber] TRADE AAPL $150.00 x100
      [MD Subscriber] BBO AAPL bid=- ask=-
      |}];
    return ())
;;

let%expect_test "e2e: subscriber only sees events for subscribed symbol" =
  with_server ~symbols:[ Harness.aapl; Harness.tsla ] (fun ~server:_ ~port ->
    let%bind sub =
      connect_as ~port ~participant:(Participant.of_string "Sub")
    in
    let%bind bob = connect_as ~port ~participant:Harness.bob in
    let%bind result =
      Rpc.Pipe_rpc.dispatch
        Rpc_protocol.market_data_rpc
        (connection sub)
        [ Harness.aapl ]
    in
    let reader =
      match result with
      | Ok (Ok (reader, _id)) -> reader
      | _ -> failwith "subscribe failed"
    in
    don't_wait_for
      (Pipe.iter_without_pushback reader ~f:(fun event ->
         let e = Protocol.format_event event in
         print_endline [%string "[MD Subscriber] %{e}"]));
    (* Post on TSLA — subscriber should NOT see this *)
    let%bind () =
      rpc_submit
        bob
        (Harness.sell ~price_cents:20000 ~symbol:Harness.tsla ())
    in
    [%expect
      {| [Bob] ACCEPTED server_id=1 client_id=101 TSLA SELL 100@$200.00 DAY |}];
    (* Post on AAPL — subscriber SHOULD see this *)
    let%bind () = rpc_submit bob (Harness.sell ~price_cents:15000 ()) in
    [%expect
      {|
      [Bob] ACCEPTED server_id=2 client_id=102 AAPL SELL 100@$150.00 DAY
      [MD Subscriber] BBO AAPL bid=- ask=$150.00 x100
      |}];
    return ())
;;

(* ---------------------------------------------------------------- *)
(* Login tests *)
(* ---------------------------------------------------------------- *)
let print_login_result = function
  | Ok participant ->
    print_s [%message "Logged in as" ~_:(participant : Participant.t)]
  | Error error -> print_s [%sexp (error : Error.t)]
;;

let connect_and_log_in' name ~port =
  let%bind client = connect ~port in
  let%map result =
    Rpc.Rpc.dispatch_exn Rpc_protocol.login_rpc (connection client) name
  in
  print_login_result result;
  client
;;

let connect_and_log_in name ~port = connect_and_log_in' name ~port >>| ignore

let rec connect_and_log_in_when_available name ~port ~attempts_remaining =
  let%bind client = connect ~port in
  let conn = connection client in
  let%bind result = Rpc.Rpc.dispatch_exn Rpc_protocol.login_rpc conn name in
  match result with
  | Ok _ ->
    print_login_result result;
    return ()
  | Error _ when attempts_remaining > 0 ->
    let%bind () = Rpc.Connection.close conn in
    let%bind () = Rpc.Connection.close_finished conn in
    let%bind () = Async.Scheduler.yield_until_no_jobs_remain () in
    connect_and_log_in_when_available
      name
      ~port
      ~attempts_remaining:(attempts_remaining - 1)
  | Error _ ->
    print_login_result result;
    return ()
;;

let%expect_test "reject actions if not logged in" =
  with_server ~symbols:[ Harness.aapl ] (fun ~server:_ ~port ->
    let%bind client = connect ~port in
    let%bind () =
      Expect_test_helpers_async.require_does_raise_async (fun () ->
        rpc_submit client (Harness.buy ~price_cents:15000 ()))
    in
    [%expect {| "not logged in" |}];
    return ())
;;

let%expect_test "reject login if name is empty" =
  with_server ~symbols:[ Harness.aapl ] (fun ~server:_ ~port ->
    let%bind () = connect_and_log_in "" ~port in
    [%expect {| "login name must not be empty" |}];
    return ())
;;

let%expect_test "reject duplicate participant names across connections" =
  with_server ~symbols:[ Harness.aapl ] (fun ~server:_ ~port ->
    let name = "Alice" in
    (* Once alice logs in, *)
    let%bind () = connect_and_log_in name ~port in
    [%expect {| ("Logged in as" Alice) |}];
    (* The name is not available in new connections *)
    let%bind () = connect_and_log_in name ~port in
    [%expect {| ("participant name already taken" (participant Alice)) |}];
    (* But other names are still available in new connections *)
    let%bind () = connect_and_log_in "Bob" ~port in
    [%expect {| ("Logged in as" Bob) |}];
    return ())
;;

let%expect_test "logout frees participant name for reuse" =
  with_server ~symbols:[ Harness.aapl ] (fun ~server:_ ~port ->
    let name = "Alice" in
    let%bind conn = connect_and_log_in' name ~port >>| connection in
    [%expect {| ("Logged in as" Alice) |}];
    let%bind () = Rpc.Connection.close conn in
    let%bind () = Rpc.Connection.close_finished conn in
    (* Once alice logs out, the name is available in new connections.
       Server-side connection cleanup happens asynchronously, so retry
       without printing transient failures until the name has been released. *)
    let%bind () =
      connect_and_log_in_when_available name ~port ~attempts_remaining:10
    in
    [%expect {| ("Logged in as" Alice) |}];
    return ())
;;

let%expect_test "reject repeat login attempts in the same connection" =
  with_server ~symbols:[ Harness.aapl ] (fun ~server:_ ~port ->
    let retry_login client name =
      let%map result =
        Rpc.Rpc.dispatch_exn Rpc_protocol.login_rpc (connection client) name
      in
      print_login_result result
    in
    (* Once this connection logs in, *)
    let%bind client = connect_and_log_in' "Alice" ~port in
    [%expect {| ("Logged in as" Alice) |}];
    (* It cannot log in again, *)
    let%bind () = retry_login client "Alice" in
    [%expect {| ("already logged in" (existing Alice)) |}];
    (* Even as a different user *)
    let%bind () = retry_login client "Bob" in
    [%expect {| ("already logged in" (existing Alice)) |}];
    return ())
;;

(* ---------------------------------------------------------------- *)
(* Cancel via RPC *)
(* ---------------------------------------------------------------- *)

let%expect_test "e2e: cancel an order via RPC" =
  with_server ~symbols:[ Harness.aapl ] (fun ~server:_ ~port ->
    let%bind alice_conn = connect_as ~port ~participant:Harness.alice in
    let cid = Client_order_id.of_int 42 in
    let%bind () =
      rpc_submit
        alice_conn
        (Harness.buy ~price_cents:15000 ~client_order_id:cid ())
    in
    [%expect
      {| [Alice] ACCEPTED server_id=1 client_id=42 AAPL BUY 100@$150.00 DAY |}];
    let%bind () = rpc_cancel alice_conn cid in
    [%expect
      {| [Alice] CANCELLED server_id=1 client_id=42 AAPL remaining=100 reason=PARTICIPANT_REQUESTED |}];
    return ())
;;

let%expect_test "e2e: cancel rejected when not logged in" =
  with_server ~symbols:[ Harness.aapl ] (fun ~server:_ ~port ->
    let%bind conn = connect ~port in
    let%bind () =
      Expect_test_helpers_async.require_does_raise_async (fun () ->
        rpc_cancel conn (Client_order_id.of_int 1))
    in
    [%expect {| "not logged in" |}];
    return ())
;;

let%expect_test "e2e: cancel rejected when order not found" =
  with_server ~symbols:[ Harness.aapl ] (fun ~server:_ ~port ->
    let%bind alice_conn = connect_as ~port ~participant:Harness.alice in
    let cid = Client_order_id.of_int 42 in
    let%bind _result = rpc_cancel alice_conn cid in
    [%expect
      {| [Alice] CANCEL REJECTED client_id=42 reason=order not found |}];
    return ())
;;

(* ---------------------------------------------------------------- *)
(* Concurrent submission test *)
(* ---------------------------------------------------------------- *)

let%expect_test "e2e: many clients submit orders concurrently" =
  with_server ~symbols:[ Harness.aapl ] (fun ~server:_ ~port ->
    let%bind seed_client = connect_as ~port ~participant:Harness.bob in
    let%bind () =
      Deferred.List.iter
        (List.init 10 ~f:Fn.id)
        ~how:`Sequential
        ~f:(fun i ->
          let%bind _ =
            rpc_submit seed_client (Harness.sell ~price_cents:(15000 + i) ())
          in
          return ())
    in
    let%bind () =
      Deferred.List.iter (List.init 5 ~f:Fn.id) ~how:`Parallel ~f:(fun i ->
        let participant = Participant.of_string [%string "Trader%{i#Int}"] in
        let%bind client = connect_as ~port ~participant in
        rpc_submit client (Harness.buy ~price_cents:15010 ()))
    in
    (* Session-feed prints land on stdout in an order that depends on which
       parallel buy was processed first. Swallow the trace and assert on the
       deterministic remaining book state instead: 10 sells went in, the 5
       buys at $150.10 each hit the lowest-priced sell, so 5 sells should
       remain. *)
    let (_ : string) = [%expect.output] in
    let%bind book = rpc_book seed_client Harness.aapl in
    let book = Option.value_exn book in
    let remaining_orders = List.length book.bids + List.length book.asks in
    [%test_result: int] remaining_orders ~expect:5;
    return ())
;;

(* ---------------------------------------------------------------- *)
(* Audit log subscription tests *)
(* ---------------------------------------------------------------- *)

let%expect_test "e2e: audit log subscriber sees full unfiltered stream \
                 across symbols"
  =
  with_server ~symbols:[ Harness.aapl; Harness.tsla ] (fun ~server:_ ~port ->
    let%bind sub =
      connect_as ~port ~participant:(Participant.of_string "Auditor")
    in
    let%bind alice = connect_as ~port ~participant:Harness.alice in
    let%bind bob = connect_as ~port ~participant:Harness.bob in
    let%bind result =
      Rpc.Pipe_rpc.dispatch Rpc_protocol.audit_log_rpc (connection sub) ()
    in
    let reader =
      match result with
      | Ok (Ok (reader, _id)) -> reader
      | _ -> failwith "subscribe failed"
    in
    don't_wait_for
      (Pipe.iter_without_pushback reader ~f:(fun event ->
         let e = Protocol.format_event event in
         print_endline [%string "[AUDIT] %{e}"]));
    (* Post a sell on AAPL — audit subscriber should see ACCEPTED and BBO. *)
    let%bind () = rpc_submit bob (Harness.sell ~price_cents:15000 ()) in
    [%expect
      {|
      [AUDIT] ACCEPTED server_id=1 client_id=101 AAPL SELL 100@$150.00 DAY
      [AUDIT] BBO AAPL bid=- ask=$150.00 x100
      [Bob] ACCEPTED server_id=1 client_id=101 AAPL SELL 100@$150.00 DAY
      |}];
    (* Post a sell on TSLA — audit subscriber should see this too
       (multi-symbol). *)
    let%bind () =
      rpc_submit
        bob
        (Harness.sell ~price_cents:20000 ~symbol:Harness.tsla ())
    in
    [%expect
      {|
      [AUDIT] ACCEPTED server_id=2 client_id=102 TSLA SELL 100@$200.00 DAY
      [AUDIT] BBO TSLA bid=- ask=$200.00 x100
      [Bob] ACCEPTED server_id=2 client_id=102 TSLA SELL 100@$200.00 DAY
      |}];
    (* Cross the AAPL sell — the audit log should see ACCEPTED + FILL + BBO. *)
    let%bind () = rpc_submit alice (Harness.buy ~price_cents:15000 ()) in
    [%expect
      {|
      [AUDIT] ACCEPTED server_id=3 client_id=103 AAPL BUY 100@$150.00 DAY
      [AUDIT] FILL fill_id=1 AAPL $150.00 x100 aggressor=[server_id=3 client_id=103 Alice] BUY resting=[server_id=1 client_id=101 Bob]
      [AUDIT] TRADE AAPL $150.00 x100
      [AUDIT] BBO AAPL bid=- ask=-
      [Alice] ACCEPTED server_id=3 client_id=103 AAPL BUY 100@$150.00 DAY
      [Alice] FILL fill_id=1 AAPL $150.00 x100 aggressor=[server_id=3 client_id=103 Alice] BUY resting=[server_id=1 client_id=101 Bob]
      [Bob] FILL fill_id=1 AAPL $150.00 x100 aggressor=[server_id=3 client_id=103 Alice] BUY resting=[server_id=1 client_id=101 Bob]
      |}];
    return ())
;;

let%expect_test "dispatcher: closing a subscriber's reader removes the \
                 writer"
  =
  let dispatcher = Dispatcher.create () in
  print_s
    [%message
      "initial"
        ~count:
          (Dispatcher.For_testing.audit_subscriber_count dispatcher : int)];
  [%expect {| (initial (count 0)) |}];
  let reader_a = Dispatcher.subscribe_audit dispatcher in
  let reader_b = Dispatcher.subscribe_audit dispatcher in
  print_s
    [%message
      "after subscribe"
        ~count:
          (Dispatcher.For_testing.audit_subscriber_count dispatcher : int)];
  [%expect {| ("after subscribe" (count 2)) |}];
  Pipe.close_read reader_a;
  let%bind () = Async.Scheduler.yield_until_no_jobs_remain () in
  print_s
    [%message
      "after closing reader_a"
        ~count:
          (Dispatcher.For_testing.audit_subscriber_count dispatcher : int)];
  [%expect {| ("after closing reader_a" (count 1)) |}];
  Pipe.close_read reader_b;
  let%bind () = Async.Scheduler.yield_until_no_jobs_remain () in
  print_s
    [%message
      "after closing reader_b"
        ~count:
          (Dispatcher.For_testing.audit_subscriber_count dispatcher : int)];
  [%expect {| ("after closing reader_b" (count 0)) |}];
  return ()
;;
