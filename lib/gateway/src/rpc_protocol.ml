open! Core
open! Async
open Jsip_types

let login_rpc =
  Rpc.Rpc.create
    ~name:"login"
    ~version:1
    ~bin_query:String.bin_t
    ~bin_response:[%bin_type_class: Participant.t Or_error.t]
    ~include_in_error_count:Only_on_exn
;;

let submit_order_rpc =
  Rpc.Rpc.create
    ~name:"submit-order"
    ~version:1
    ~bin_query:Order.Request.bin_t
    ~bin_response:[%bin_type_class: unit Or_error.t]
    ~include_in_error_count:Only_on_exn
;;

let cancel_order_rpc =
  Rpc.Rpc.create
    ~name:"cancel-order"
    ~version:1
    ~bin_query:Client_order_id.bin_t
    ~bin_response:[%bin_type_class: unit Or_error.t]
    ~include_in_error_count:Only_on_exn
;;

let book_query_rpc =
  Rpc.Rpc.create
    ~name:"book-query"
    ~version:1
    ~bin_query:Symbol.bin_t
    ~bin_response:[%bin_type_class: Book.t option]
    ~include_in_error_count:Only_on_exn
;;

let market_data_rpc =
  Rpc.Pipe_rpc.create
    ~name:"market-data"
    ~version:1
    ~bin_query:[%bin_type_class: Symbol.t list]
    ~bin_response:Exchange_event.bin_t
    ~bin_error:Error.bin_t
    ()
;;

let audit_log_rpc =
  Rpc.Pipe_rpc.create
    ~name:"audit-log"
    ~version:1
    ~bin_query:Unit.bin_t
    ~bin_response:Exchange_event.bin_t
    ~bin_error:Error.bin_t
    ()
;;

let session_feed_rpc =
  Rpc.Pipe_rpc.create
    ~name:"session-feed"
    ~version:1
    ~bin_query:Unit.bin_t
    ~bin_response:Exchange_event.bin_t
    ~bin_error:Error.bin_t
    ()
;;
