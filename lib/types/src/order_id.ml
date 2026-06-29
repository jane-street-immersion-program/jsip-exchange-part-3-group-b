open! Core

module T = struct
  type t = int [@@deriving sexp, bin_io, compare, equal, hash, string]
end

include T
include Comparable.Make (T)
include Hashable.Make (T)

module Generator = struct
  type t = { mutable next : int } [@@deriving sexp_of]

  let create () = { next = 1 }

  let next t =
    let id = t.next in
    t.next <- t.next + 1;
    id
  ;;
end

module For_testing = struct
  let to_int t = t
  let of_int t = t
end
