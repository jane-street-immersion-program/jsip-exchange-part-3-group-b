open! Core

type t =
  { fill_id : int
  ; symbol : Symbol.t
  ; price : Price.t
  ; size : Size.t
  ; aggressor_order_id : Order_id.t
  ; aggressor_client_order_id : Client_order_id.t
  ; aggressor_participant : Participant.t
  ; aggressor_side : Side.t
  ; resting_order_id : Order_id.t
  ; resting_client_order_id : Client_order_id.t
  ; resting_participant : Participant.t
  }
[@@deriving sexp, bin_io]

let to_string t =
  let format_ids ~order_id ~client_order_id =
    sprintf
      "server_id=%s client_id=%s"
      (Order_id.to_string order_id)
      (Client_order_id.to_string client_order_id)
  in
  sprintf
    "fill_id=%d %s %s x%d aggressor=[%s %s] %s resting=[%s %s]"
    t.fill_id
    (Symbol.to_string t.symbol)
    (Price.to_string_dollar t.price)
    (Size.to_int t.size)
    (format_ids
       ~order_id:t.aggressor_order_id
       ~client_order_id:t.aggressor_client_order_id)
    (Participant.to_string t.aggressor_participant)
    (Side.to_string t.aggressor_side)
    (format_ids
       ~order_id:t.resting_order_id
       ~client_order_id:t.resting_client_order_id)
    (Participant.to_string t.resting_participant)
;;

let notional_cents t = Price.to_int_cents t.price * Size.to_int t.size
