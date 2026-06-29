open! Core

module T = struct
  type t = int [@@deriving sexp, bin_io, compare, equal, hash]
end

include T
include Comparable.Make (T)

let cents_per_dollar = 100
let of_int_cents n = n
let to_int_cents t = t

let of_float_exn f =
  let cents = Float.round_nearest (f *. Float.of_int cents_per_dollar) in
  let int_cents = Float.to_int cents in
  if Float.( <> ) (Float.of_int int_cents) cents
  then
    raise_s
      [%message
        "Price.of_float_exn: not representable as exact cents" (f : float)];
  int_cents
;;

let to_float t = Float.of_int t /. Float.of_int cents_per_dollar
let zero = 0
let ( + ) = Int.( + )
let ( - ) = Int.( - )
let ( * ) price qty = price * qty

let is_more_aggressive (side : Side.t) ~price ~than =
  match side with Buy -> price > than | Sell -> price < than
;;

let is_marketable (side : Side.t) ~price ~resting_price =
  match side with
  | Buy -> price >= resting_price
  | Sell -> price <= resting_price
;;

let to_string_dollar t =
  let is_negative = t < 0 in
  let t_abs = Int.abs t in
  let dollars = t_abs / cents_per_dollar in
  let cents = t_abs mod cents_per_dollar in
  sprintf "%s$%d.%02d" (if is_negative then "-" else "") dollars cents
;;

let to_string = to_string_dollar

let of_string s =
  let s = String.chop_prefix_if_exists s ~prefix:"$" in
  of_float_exn (Float.of_string s)
;;
