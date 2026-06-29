(** A participant on the exchange — anyone who can send orders.

    A production exchange would distinguish between firms (organizations),
    accounts (trading accounts within a firm), and portfolios (sub-groupings
    within an account), each carrying regulatory and settlement metadata.

    We use a single [Participant] type with a unique string name. *)

open! Core

type t [@@deriving sexp, bin_io, compare, equal, hash, string]

include Comparable.S with type t := t
include Hashable.S with type t := t
