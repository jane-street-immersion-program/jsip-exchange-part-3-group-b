open! Core

type t =
  { (* Important that price is defined first for the purposes of the derived
       comparison function *)
    price : Price.t
  ; size : Size.t
  }
[@@deriving sexp, bin_io, compare, equal]

let to_string { price; size } = [%string "%{price#Price} x%{size#Size}"]
let opt_to_string = function None -> "-" | Some level -> to_string level

let of_order order =
  { price = Order.price order; size = Order.remaining_size order }
;;
