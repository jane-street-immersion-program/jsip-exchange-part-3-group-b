(** [jsip-monitor]: a bonsai_term TUI that subscribes to the exchange's audit
    log and renders a filterable, color-coded stream of every event the
    matching engine produces.

    Connects to an exchange server at the given host/port, subscribes via
    [Rpc_protocol.audit_log_rpc], and hands the resulting pipe to
    [Term_app.app], which drains it directly into its Bonsai state machine. *)

open! Core
open! Async
open Jsip_gateway
open Jsip_monitor

let connect_to_exchange ~host ~port =
  let%map result =
    Rpc.Connection.client
      (Tcp.Where_to_connect.of_host_and_port { host; port })
  in
  match result with
  | Ok conn -> conn
  | Error exn ->
    raise_s
      [%message
        "failed to connect to exchange"
          (host : string)
          (port : int)
          (exn : Exn.t)]
;;

let subscribe_audit_log ~connection ~host ~port =
  match%map
    Rpc.Pipe_rpc.dispatch Rpc_protocol.audit_log_rpc connection ()
  with
  | Error err | Ok (Error err) ->
    raise_s
      [%message
        "audit-log failed" (host : string) (port : int) (err : Error.t)]
  | Ok (Ok (pipe, _md)) -> pipe
;;

let main ~host ~port () =
  let%bind connection = connect_to_exchange ~host ~port in
  let%bind events = subscribe_audit_log ~connection ~host ~port in
  let%map result =
    Bonsai_term.start_with_exit (fun ~exit ~dimensions graph ->
      Term_app.app ~events ~exit ~dimensions graph)
  in
  ok_exn result
;;

let command =
  Command.async
    ~summary:
      "Bonsai_term monitor that subscribes to the audit log of a JSIP \
       exchange server and renders a filterable, color-coded event stream."
    (let%map_open.Command host =
       flag
         "-host"
         (optional_with_default "localhost" string)
         ~doc:"HOST exchange server hostname (default localhost)"
     and port =
       flag
         "-port"
         (optional_with_default 12345 int)
         ~doc:"PORT exchange server port (default 12345)"
     in
     fun () -> main ~host ~port ())
    ~behave_nicely_in_pipeline:false
;;

let () = Command_unix.run command
