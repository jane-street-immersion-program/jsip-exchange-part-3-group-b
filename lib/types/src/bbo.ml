open! Core

type t =
  { bid : Level.t option
  ; ask : Level.t option
  }
[@@deriving sexp, bin_io, compare, equal]

let empty = { bid = None; ask = None }

let spread t =
  match t.bid, t.ask with
  | Some bid, Some ask -> Some Price.(ask.price - bid.price)
  | _ -> None
;;

let price t (side : Side.t) =
  match side with
  | Buy -> Option.map t.bid ~f:(fun s -> s.price)
  | Sell -> Option.map t.ask ~f:(fun s -> s.price)
;;

let size t (side : Side.t) =
  match side with
  | Buy -> Option.map t.bid ~f:(fun s -> s.size)
  | Sell -> Option.map t.ask ~f:(fun s -> s.size)
;;

let to_string t =
  [%string "%{Level.opt_to_string t.bid} / %{Level.opt_to_string t.ask}"]
;;
