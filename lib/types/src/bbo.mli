(** Best bid and offer (BBO) for a symbol.

    Represents the best available prices on each side of the order book,
    along with the total size available at each price. *)

open! Core

type t =
  { bid : Level.t option
  ; ask : Level.t option
  }
[@@deriving sexp, bin_io, compare, equal]

val empty : t

(** The spread (ask price minus bid price), or [None] if either side is
    empty. *)
val spread : t -> Price.t option

val price : t -> Side.t -> Price.t option
val size : t -> Side.t -> Size.t option
val to_string : t -> string
