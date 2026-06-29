(** A read-only snapshot of an order book.

    Contains the symbol, all resting price levels on each side (aggregated by
    price), and the BBO. *)

open! Core

type t =
  { symbol : Symbol.t
  ; bids : Level.t list
  ; asks : Level.t list
  ; bbo : Bbo.t
  }
[@@deriving sexp, bin_io]

val to_string : t -> string
