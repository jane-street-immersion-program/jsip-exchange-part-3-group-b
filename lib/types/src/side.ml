open! Core

type t =
  | Buy
  | Sell
[@@deriving
  sexp
  , bin_io
  , compare
  , equal
  , enumerate
  , hash
  , string ~case_insensitive ~capitalize:"SCREAMING_SNAKE_CASE"]

let flip = function Buy -> Sell | Sell -> Buy
let sign = function Buy -> 1 | Sell -> -1
