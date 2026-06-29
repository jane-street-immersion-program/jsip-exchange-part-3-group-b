open! Core
open! Async
open Jsip_types
open Jsip_gateway

let with_server ~symbols f =
  (* Without this reset, IDs would depend on expect-test order *)
  Harness.reset_client_order_id_counter ();
  let%bind server = Exchange_server.start ~symbols ~port:0 () in
  let port = Exchange_server.port server in
  Monitor.protect
    (fun () -> f ~server ~port)
    ~finally:(fun () -> Exchange_server.close server)
;;

type client = { conn : Rpc.Connection.t }

let connect ~port =
  let where =
    Tcp.Where_to_connect.of_host_and_port { host = "localhost"; port }
  in
  let%map conn = Rpc.Connection.client where >>| Result.ok_exn in
  { conn }
;;

let login conn participant =
  Rpc.Rpc.dispatch_exn
    Rpc_protocol.login_rpc
    conn
    (Participant.to_string participant)
  >>| ok_exn
;;

let connect_as ~port ~participant =
  let%bind client = connect ~port in
  let%bind (_ : Participant.t) = login client.conn participant in
  let%bind session_feed, _metadata =
    Rpc.Pipe_rpc.dispatch_exn Rpc_protocol.session_feed_rpc client.conn ()
  in
  don't_wait_for
    (Pipe.iter_without_pushback session_feed ~f:(fun event ->
       let e = Protocol.format_event event in
       print_endline [%string "[%{participant#Participant}] %{e}"]));
  return client
;;

let connection client = client.conn

let rpc_submit client request =
  Rpc.Rpc.dispatch_exn Rpc_protocol.submit_order_rpc client.conn request
  >>| ok_exn
;;

let rpc_cancel client client_order_id =
  Rpc.Rpc.dispatch_exn
    Rpc_protocol.cancel_order_rpc
    client.conn
    client_order_id
  >>| ok_exn
;;

let rpc_book client symbol =
  Rpc.Rpc.dispatch_exn Rpc_protocol.book_query_rpc client.conn symbol
;;
