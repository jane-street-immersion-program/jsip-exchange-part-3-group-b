open! Core
open! Async
open Jsip_gateway

(* Wire-shape tests for the exchange's RPC protocol.

   Each test below pins one RPC's *wire contract*: its name, its version, and
   a digest of the [bin_io] shape of every type it puts on the wire — the
   query it receives, the response it sends, and (for streaming pipe RPCs)
   the error type.

   A bin-shape digest is a stable fingerprint of how a value is serialized.
   It changes whenever the serialized layout of a type changes: adding a
   field to [Order.Request.t], adding a variant to [Exchange_event.t], or
   pointing an RPC at a different type all move the digest. Two exchanges can
   only talk to each other over an RPC if they agree on its name, version,
   and these digests, so these tests are the precise statement of "what's on
   the wire."

   Keep them in sync as you build out the protocol: when you change or extend
   an RPC, update its test; when you add an RPC, add a test for it (copy one
   of the blocks below). If a digest changes, read the diff, convince
   yourself the change was intended, then accept it with [dune promote]. *)

let%expect_test "login RPC" =
  print_s
    [%sexp
      (Rpc.Rpc.shapes Rpc_protocol.login_rpc : Async_rpc_kernel.Rpc_shapes.t)];
  [%expect
    {|
    (Rpc (query d9a8da25d5656b016fb4dbdc2e4197fb)
     (response a77b3b6e3753246ce7ec1f3467c939eb))
    |}];
  return ()
;;

let%expect_test "submit-order RPC" =
  print_s
    [%sexp
      (Rpc.Rpc.shapes Rpc_protocol.submit_order_rpc
       : Async_rpc_kernel.Rpc_shapes.t)];
  [%expect
    {|
    (Rpc (query 1e10a37f621cf2c76cdb30f5d8917adb)
     (response 27f76252e5181aab209cd62aa6e42268))
    |}];
  return ()
;;

let%expect_test "cancel-order RPC" =
  print_s
    [%sexp
      (Rpc.Rpc.shapes Rpc_protocol.cancel_order_rpc
       : Async_rpc_kernel.Rpc_shapes.t)];
  [%expect
    {|
    (Rpc (query 698cfa4093fe5e51523842d37b92aeac)
     (response 27f76252e5181aab209cd62aa6e42268))
    |}];
  return ()
;;

let%expect_test "book-query RPC" =
  print_s
    [%sexp
      (Rpc.Rpc.shapes Rpc_protocol.book_query_rpc
       : Async_rpc_kernel.Rpc_shapes.t)];
  [%expect
    {|
    (Rpc (query d9a8da25d5656b016fb4dbdc2e4197fb)
     (response 9bf9d93dd466a19cac18ecff7cd287af))
    |}];
  return ()
;;

let%expect_test "session-feed RPC" =
  print_s
    [%sexp
      (Rpc.Pipe_rpc.shapes Rpc_protocol.session_feed_rpc
       : Async_rpc_kernel.Rpc_shapes.t)];
  [%expect
    {|
    (Streaming_rpc (query 86ba5df747eec837f0b391dd49f33f9e)
     (initial_response 86ba5df747eec837f0b391dd49f33f9e)
     (update_response 047e0befff966636cfdddf2a5b4b0ff3)
     (error 52966f4a49a77bfdff668e9cc61511b3))
    |}];
  return ()
;;

let%expect_test "market-data RPC" =
  print_s
    [%sexp
      (Rpc.Pipe_rpc.shapes Rpc_protocol.market_data_rpc
       : Async_rpc_kernel.Rpc_shapes.t)];
  [%expect
    {|
    (Streaming_rpc (query 296be80010ace497614f92952e5510c4)
     (initial_response 86ba5df747eec837f0b391dd49f33f9e)
     (update_response 047e0befff966636cfdddf2a5b4b0ff3)
     (error 52966f4a49a77bfdff668e9cc61511b3))
    |}];
  return ()
;;

let%expect_test "audit-log RPC" =
  print_s
    [%sexp
      (Rpc.Pipe_rpc.shapes Rpc_protocol.audit_log_rpc
       : Async_rpc_kernel.Rpc_shapes.t)];
  [%expect
    {|
    (Streaming_rpc (query 86ba5df747eec837f0b391dd49f33f9e)
     (initial_response 86ba5df747eec837f0b391dd49f33f9e)
     (update_response 047e0befff966636cfdddf2a5b4b0ff3)
     (error 52966f4a49a77bfdff668e9cc61511b3))
    |}];
  return ()
;;
