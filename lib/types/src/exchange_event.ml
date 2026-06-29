open! Core

type t =
  | Order_accept of
      { order_id : Order_id.t
      ; participant : Participant.t
      ; request : Order.Request.t
      }
  | Fill of Fill.t
  | Order_cancel of
      { order_id : Order_id.t
      ; client_order_id : Client_order_id.t
      ; participant : Participant.t
      ; symbol : Symbol.t
      ; remaining_size : Size.t
      ; reason : Cancel_reason.t
      }
  | Order_reject of
      { participant : Participant.t
      ; request : Order.Request.t
      ; reason : string
      }
  | Cancel_reject of
      { participant : Participant.t
      ; client_order_id : Client_order_id.t
      ; reason : string
      }
  | Best_bid_offer_update of
      { symbol : Symbol.t
      ; bbo : Bbo.t
      }
  | Trade_report of
      { symbol : Symbol.t
      ; price : Price.t
      ; size : Size.t
      }
[@@deriving sexp, bin_io]

let is_market_data = function
  | Best_bid_offer_update _ | Trade_report _ -> true
  | Order_accept _ | Fill _ | Order_cancel _ | Order_reject _
  | Cancel_reject _ ->
    false
;;

let symbol_of_market_data = function
  | Best_bid_offer_update { symbol; bbo = _ }
  | Trade_report { symbol; price = _; size = _ } ->
    Some symbol
  | Order_accept _ | Fill _ | Order_cancel _ | Order_reject _
  | Cancel_reject _ ->
    None
;;
