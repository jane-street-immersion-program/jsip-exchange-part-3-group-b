(** A price level: a price and the total size available there.

    Used by both [Bbo] (best bid/offer) and [Book] (full book snapshot) to
    represent aggregated resting interest at a single price. *)

open! Core

type t =
  { price : Price.t
  ; size : Size.t
  }
[@@deriving sexp, bin_io, compare, equal]

val to_string : t -> string
val opt_to_string : t option -> string
val of_order : Order.t -> t
