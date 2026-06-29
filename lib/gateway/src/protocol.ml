open! Core
open Jsip_types

let format_ids ~order_id ~client_order_id =
  sprintf
    "server_id=%s client_id=%s"
    (Order_id.to_string order_id)
    (Client_order_id.to_string client_order_id)
;;

let format_event = function
  | Exchange_event.Order_accept { order_id; participant = _; request } ->
    sprintf
      "ACCEPTED %s %s %s %d@%s %s"
      (format_ids ~order_id ~client_order_id:request.client_order_id)
      (Symbol.to_string request.symbol)
      (Side.to_string request.side)
      (Size.to_int request.size)
      (Price.to_string_dollar request.price)
      (Time_in_force.to_string request.time_in_force)
  | Fill fill -> [%string "FILL %{fill#Fill}"]
  | Order_cancel
      { order_id
      ; client_order_id
      ; participant = _
      ; symbol
      ; remaining_size
      ; reason
      } ->
    sprintf
      "CANCELLED %s %s remaining=%d reason=%s"
      (format_ids ~order_id ~client_order_id)
      (Symbol.to_string symbol)
      (Size.to_int remaining_size)
      (Cancel_reason.to_string reason)
  | Order_reject { participant = _; request; reason } ->
    sprintf
      "REJECTED client_id=%s %s %s %d@%s reason=%s"
      (Client_order_id.to_string request.client_order_id)
      (Symbol.to_string request.symbol)
      (Side.to_string request.side)
      (Size.to_int request.size)
      (Price.to_string_dollar request.price)
      reason
  | Cancel_reject { participant = _; client_order_id; reason } ->
    sprintf
      "CANCEL REJECTED client_id=%s reason=%s"
      (Client_order_id.to_string client_order_id)
      reason
  | Best_bid_offer_update { symbol; bbo } ->
    let bid = Level.opt_to_string bbo.bid in
    let ask = Level.opt_to_string bbo.ask in
    [%string "BBO %{symbol#Symbol} bid=%{bid} ask=%{ask}"]
  | Trade_report { symbol; price; size } ->
    let size = Size.to_int size in
    [%string "TRADE %{symbol#Symbol} %{price#Price} x%{size#Int}"]
;;

let format_events events =
  List.map events ~f:format_event |> String.concat ~sep:"\n"
;;
