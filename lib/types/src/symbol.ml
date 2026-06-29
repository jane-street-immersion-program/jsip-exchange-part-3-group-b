open! Core

module T = struct
  type t = string [@@deriving sexp, bin_io, compare, equal, hash, string]
end

include T
include Comparable.Make (T)
include Hashable.Make (T)

let of_string s =
  if String.is_empty s
  then raise_s [%message "Symbol.of_string: symbol must be non-empty"];
  s
;;
