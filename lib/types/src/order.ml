open! Core

module Request = struct
  type t =
    { client_order_id : Client_order_id.t
    ; symbol : Symbol.t
    ; side : Side.t
    ; price : Price.t
    ; size : Size.t
    ; time_in_force : Time_in_force.t
    }
  [@@deriving sexp, bin_io]

  let to_string { client_order_id; symbol; side; price; size; time_in_force }
    =
    let price = Price.to_string_dollar price in
    let size = Size.to_int size in
    [%string
      "%{side#Side} %{client_order_id#Client_order_id} %{symbol#Symbol} \
       %{size#Int}@%{price} %{time_in_force#Time_in_force}"]
  ;;
end

type t =
  { order_id : Order_id.t
  ; client_order_id : Client_order_id.t
  ; symbol : Symbol.t
  ; participant : Participant.t
  ; side : Side.t
  ; price : Price.t
  ; size : Size.t
  ; mutable remaining_size : Size.t
  ; time_in_force : Time_in_force.t
  }
[@@deriving sexp_of, equal, compare]

let to_string
  ({ order_id
   ; client_order_id
   ; symbol = _
   ; participant
   ; side = _
   ; price
   ; size = _
   ; remaining_size
   ; time_in_force = _
   } :
    t)
  =
  let price = Price.to_string_dollar price in
  let size = Size.to_int remaining_size in
  [%string
    "%{price} x%{size#Int} (server_id=%{order_id#Order_id}, \
     client_id=%{client_order_id#Client_order_id}, \
     %{participant#Participant})"]
;;

let create (req : Request.t) ~order_id ~participant =
  if Size.( <= ) req.size Size.zero
  then
    raise_s
      [%message "Order.create: size must be positive" (req.size : Size.t)];
  { order_id
  ; client_order_id = req.client_order_id
  ; symbol = req.symbol
  ; participant
  ; side = req.side
  ; price = req.price
  ; size = req.size
  ; remaining_size = req.size
  ; time_in_force = req.time_in_force
  }
;;

let order_id t = t.order_id
let client_order_id t = t.client_order_id
let symbol t = t.symbol
let participant t = t.participant
let side t = t.side
let price t = t.price
let size t = t.size
let remaining_size t = t.remaining_size
let time_in_force t = t.time_in_force

let fill t ~by =
  if Size.( <= ) by Size.zero
  then
    raise_s [%message "Order.fill: fill size must be positive" (by : Size.t)];
  if Size.( > ) by t.remaining_size
  then
    raise_s
      [%message
        "Order.fill: fill size exceeds remaining"
          (by : Size.t)
          (t.remaining_size : Size.t)
          (t.order_id : Order_id.t)];
  t.remaining_size <- Size.( - ) t.remaining_size by
;;

let is_fully_filled t = Size.equal t.remaining_size Size.zero
