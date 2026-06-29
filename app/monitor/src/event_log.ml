open! Core
open Jsip_types
open Jsip_gateway

module Category = struct
  type t =
    | Order_lifecycle
    | Trade
    | Market_data
  [@@deriving sexp_of, compare, equal, enumerate]

  let to_string = function
    | Order_lifecycle -> "order-lifecycle"
    | Trade -> "trade"
    | Market_data -> "market-data"
  ;;

  let of_event : Exchange_event.t -> t = function
    | Order_accept _ | Order_cancel _ | Order_reject _ | Cancel_reject _ ->
      Order_lifecycle
    | Fill _ -> Trade
    | Best_bid_offer_update _ | Trade_report _ -> Market_data
  ;;
end

module Color = struct
  type t =
    | Default
    | Red
    | Green
    | Yellow
    | Blue
    | Magenta
    | Cyan
  [@@deriving sexp_of, compare, equal, enumerate]

  let to_string = function
    | Default -> "default"
    | Red -> "red"
    | Green -> "green"
    | Yellow -> "yellow"
    | Blue -> "blue"
    | Magenta -> "magenta"
    | Cyan -> "cyan"
  ;;

  let of_event : Exchange_event.t -> t = function
    | Order_accept _ -> Green
    | Fill _ -> Cyan
    | Order_cancel _ -> Yellow
    | Order_reject _ | Cancel_reject _ -> Red
    | Best_bid_offer_update _ -> Blue
    | Trade_report _ -> Magenta
  ;;
end

module Filter = struct
  (* A filter is stored as a list of independent predicates; [matches] AND's
     them together. This keeps [combine] trivial — just append. *)
  type predicate =
    | Categories of Category.t list
    | Substring of string

  type t = predicate list

  let sexp_of_predicate = function
    | Categories cs ->
      [%sexp Categories (List.map cs ~f:Category.to_string : string list)]
    | Substring s -> [%sexp Substring (s : string)]
  ;;

  let sexp_of_t (t : t) = [%sexp_of: predicate list] t
  let all : t = []
  let by_categories cs : t = [ Categories cs ]
  let by_substring s : t = [ Substring s ]
  let combine a b : t = a @ b

  let predicate_matches event line = function
    | Categories cs ->
      List.mem cs (Category.of_event event) ~equal:Category.equal
    | Substring s -> String.Caseless.is_substring line ~substring:s
  ;;

  let matches t event =
    let line = Protocol.format_event event in
    List.for_all t ~f:(predicate_matches event line)
  ;;
end

type t =
  { events_rev : Exchange_event.t list
  ; filter : Filter.t
  ; (* Ordered by first appearance — newest symbol last. Reorganising on
       every BBO would be visually noisy. *)
    bbos_rev : (Symbol.t * Bbo.t) list
  }

let create () = { events_rev = []; filter = Filter.all; bbos_rev = [] }

let update_bbos bbos_rev symbol bbo =
  let found, updated =
    List.fold_map bbos_rev ~init:false ~f:(fun found (sym, current) ->
      if Symbol.equal sym symbol
      then true, (sym, bbo)
      else found, (sym, current))
  in
  if found then updated else (symbol, bbo) :: bbos_rev
;;

let add_event t event =
  let bbos_rev =
    match (event : Exchange_event.t) with
    | Best_bid_offer_update { symbol; bbo } ->
      update_bbos t.bbos_rev symbol bbo
    | _ -> t.bbos_rev
  in
  { t with events_rev = event :: t.events_rev; bbos_rev }
;;

let event_count t = List.length t.events_rev
let current_bbos t = List.rev t.bbos_rev
let set_filter t filter = { t with filter }
let filter t = t.filter

let visible_events t =
  List.rev_filter t.events_rev ~f:(Filter.matches t.filter)
;;

let visible_lines t = List.map (visible_events t) ~f:Protocol.format_event

let visible_styled_lines t =
  List.map (visible_events t) ~f:(fun event ->
    Color.of_event event, Protocol.format_event event)
;;
