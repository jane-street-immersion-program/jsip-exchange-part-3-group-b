open! Core
open Jsip_types
open Async_log_kernel.Ppx_log_syntax

module Key = struct
  module T = struct
    type t = Price.t * Order_id.t [@@deriving compare, sexp_of]
  end

  include T
  include Comparable.Make_plain (T)
end

type t =
  { symbol : Symbol.t
  ; mutable bids : Order.t Key.Map.t
  ; mutable asks : Order.t Key.Map.t
  ; reverse_index : (Side.t * Key.t) Order_id.Table.t
  }
[@@deriving sexp_of]

let create symbol =
  { symbol
  ; bids = Key.Map.empty
  ; asks = Key.Map.empty
  ; reverse_index = Order_id.Table.create ()
  }
;;

let symbol t = t.symbol

let side_data t side =
  match (side : Side.t) with Buy -> t.bids | Sell -> t.asks
;;

let set_side t side orders =
  match (side : Side.t) with
  | Buy -> t.bids <- orders
  | Sell -> t.asks <- orders
;;

let add t order =
  let side = Order.side order in
  let order_id = Order.order_id order in
  let key = Order.price order, order_id in
  let existing_orders = side_data t side in
  match Map.add existing_orders ~key ~data:order with
  | `Duplicate -> [%log.info "BUG: duplicate (price * order_id) key"]
  | `Ok new_data ->
    set_side t side new_data;
    Hashtbl.set t.reverse_index ~key:order_id ~data:(side, key)
;;

let remove' t order_id =
  match Hashtbl.find_and_remove t.reverse_index order_id with
  | None -> None
  | Some (side, key) ->
    let side_data = side_data t side in
    let%bind.Option order = Map.find side_data key in
    let updated_side = Map.remove side_data key in
    set_side t side updated_side;
    Some order
;;

let remove t order_id = ignore (remove' t order_id)

let find t order_id =
  let%bind.Option side, key = Hashtbl.find t.reverse_index order_id in
  let data = side_data t side in
  Map.find data key
;;

(* NOTE: This walks the list front-to-back and returns the *first* tradable
   order, not the best-priced one. Orders are in reverse insertion order
   (newest first), so this matches against whatever was most recently added,
   regardless of price. See test_matching_engine.ml for a test that
   demonstrates why this is wrong. *)
let find_match t incoming =
  let incoming_side = Order.side incoming in
  let opposite_side = Side.flip incoming_side in
  let resting_orders = side_data t opposite_side in
  let%bind.Option (best_price, _order_id), best_resting_order =
    match opposite_side with
    | Buy -> Map.max_elt resting_orders
    | Sell -> Map.min_elt resting_orders
  in
  Option.some_if
    (Price.is_marketable
       incoming_side
       ~price:(Order.price incoming)
       ~resting_price:best_price)
    best_resting_order
;;

let orders_on_side t side = side_data t side |> Map.data
let is_empty t = Map.is_empty t.bids && Map.is_empty t.asks
let count t side = Map.length (side_data t side)

let best_price t side =
  let resting_orders = side_data t side in
  (match side with
   | Buy -> Map.max_elt resting_orders
   | Sell -> Map.min_elt resting_orders)
  |> Option.map ~f:(fun ((price, _order_id), _order) -> price)
;;

let best_level t side : Level.t option =
  let resting_orders = side_data t side in
  match best_price t side with
  | None -> None
  | Some price ->
    let total_size =
      Map.sumi
        (module Size)
        resting_orders
        ~f:(fun ~key:(price', _) ~data:order ->
          if Price.equal price price'
          then Order.remaining_size order
          else Size.zero)
    in
    Some { price; size = total_size }
;;

let best_bid_offer t : Bbo.t =
  { bid = best_level t Buy; ask = best_level t Sell }
;;

let snapshot_side t (side : Side.t) =
  let compare =
    match side with
    | Buy -> Comparable.reverse Level.compare
    | Sell -> Level.compare
  in
  orders_on_side t side |> List.map ~f:Level.of_order |> List.sort ~compare
;;

let snapshot t =
  { Book.symbol = symbol t
  ; bids = snapshot_side t Buy
  ; asks = snapshot_side t Sell
  ; bbo = best_bid_offer t
  }
;;

module For_testing = struct
  let remove = remove'
end
