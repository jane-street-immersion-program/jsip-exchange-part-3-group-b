open! Core

type t =
  | Day
  | Ioc
[@@deriving
  sexp
  , bin_io
  , compare
  , equal
  , enumerate
  , hash
  , string ~case_insensitive ~capitalize:"SCREAMING_SNAKE_CASE"]

let rests_on_book = function Day -> true | Ioc -> false
let all_str = String.concat ~sep:"|" (List.map all ~f:to_string)
