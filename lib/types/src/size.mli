(** The size (quantity) of an order, in shares or units. Sizes are
    non-negative integers; callers are responsible for ensuring positivity
    where required (e.g. when validating new order requests).

    This is a thin wrapper around [int] that documents intent — when you see
    [Size.t] in a signature, you know it represents a quantity of shares
    rather than an arbitrary integer. *)

open! Core

type t [@@deriving sexp, bin_io, compare, equal, hash, string]

include Comparable.S with type t := t

val zero : t
val to_int : t -> int
val of_int : int -> t
val ( - ) : t -> t -> t
val ( + ) : t -> t -> t
val ( * ) : t -> int -> t
