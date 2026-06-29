(** The side of an order: whether the participant wants to buy or sell. *)

open! Core

type t =
  | Buy
  | Sell
[@@deriving sexp, bin_io, compare, equal, enumerate, hash, string]

(** The opposite side: [Buy] becomes [Sell] and vice versa. *)
val flip : t -> t

(** [sign t] returns [1] for [Buy] and [-1] for [Sell]. Useful for position
    arithmetic: a buy of 100 shares changes your position by
    [sign Buy * 100 = +100]. *)
val sign : t -> int
