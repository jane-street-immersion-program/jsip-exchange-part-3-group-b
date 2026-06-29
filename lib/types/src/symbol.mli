(** A trading symbol identifying a financial instrument (e.g., "AAPL",
    "TSLA").

    A production exchange would support multiple asset classes with different
    symbology formats. We represent symbols as simple uppercase strings. *)

open! Core

type t [@@deriving sexp, bin_io, compare, equal, hash, string]

include Comparable.S with type t := t
include Hashable.S with type t := t
