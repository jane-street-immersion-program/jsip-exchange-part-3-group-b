open! Core
open Jsip_types

type t =
  { books : Order_book.t Symbol.Map.t
  ; order_id_gen : Order_id.Generator.t
  ; mutable next_fill_id : int
  ; (* Tracks every [Client_order_id.t] that has ever been accepted from each
       participant, so we can reject duplicate submissions. Once an ID is in
       this table it is never removed — a fully-filled, IOC-cancelled, or
       (eventually) participant-cancelled order keeps its slot occupied to
       prevent ID reuse, which preserves the audit trail. *)
    orders_by_client_id : Order.t Client_order_id.Table.t Participant.Table.t
  }
[@@deriving sexp_of]

let create symbols =
  let books =
    List.map symbols ~f:(fun sym -> sym, Order_book.create sym)
    |> Symbol.Map.of_alist_exn
  in
  { books
  ; order_id_gen = Order_id.Generator.create ()
  ; next_fill_id = 1
  ; orders_by_client_id = Participant.Table.create ()
  }
;;

(* Look up the order a participant submitted under [client_order_id], if any.
   Returns [Some order] if the client has ever submitted that ID, [None]
   otherwise. Note that the returned order may no longer be in the book — it
   may have been fully filled or cancelled. Callers that care about liveness
   should check [Order_book.find] too. *)
let find_order t ~participant ~client_order_id =
  match Hashtbl.find t.orders_by_client_id participant with
  | None -> None
  | Some inner -> Hashtbl.find inner client_order_id
;;

(* Atomically reserve [(participant, client_order_id)] by associating it with
   [order]. Returns [`Duplicate] without modifying state if the slot was
   already taken; [`Ok] if the reservation succeeded.

   Design note: this is called after we've already allocated an [Order_id.t]
   from the generator, so a duplicate submission burns a server order ID and
   leaves a gap in the generator's ID sequence.

   Two tempting alternatives are worth considering, especially for students
   who see the gap and want to close it:

   - Pre-checking with [find_order] and raising on the [`Duplicate] case
     here. Trades wasted IDs for an implicit "caller must check first"
     invariant plus a server crash if ever violated. This solution is
     probably fine.
   - Adding an [Order_id.Generator.undo_next] so we can roll the counter back
     on rejection. Closes the gap but breaks the generator's core "monotonic
     and never repeated" invariant — a misused [undo_next] would silently let
     the program run with repeated IDs, breaking the audit trail we try to
     maintain. We should probably discourage this solution.

   Real exchanges have gaps in server-assigned IDs routinely: rejections,
   cancels, and internal bookkeeping all consume sequence numbers. Accepting
   gaps here matches that behaviour and keeps the code straightforward. *)
let try_reserve_client_order_id t ~participant ~client_order_id ~order =
  let inner =
    Hashtbl.find_or_add t.orders_by_client_id participant ~default:(fun () ->
      Client_order_id.Table.create ())
  in
  Hashtbl.add inner ~key:client_order_id ~data:order
;;

let book t symbol = Map.find t.books symbol

(** Run the matching loop: repeatedly find a compatible resting order and
    fill against it. Returns the list of Fill and Trade_report events
    produced, and the next fill_id to use. *)
let rec match_loop ~book ~order ~fill_id =
  if Size.( <= ) (Order.remaining_size order) Size.zero
  then [], fill_id
  else (
    match Order_book.find_match book order with
    | None -> [], fill_id
    | Some resting ->
      let fill_size =
        Size.min (Order.remaining_size order) (Order.remaining_size resting)
      in
      Order.fill order ~by:fill_size;
      Order.fill resting ~by:fill_size;
      if Order.is_fully_filled resting
      then Order_book.remove book (Order.order_id resting);
      let fill_event =
        Exchange_event.Fill
          { fill_id
          ; symbol = Order.symbol order
          ; price = Order.price resting
          ; size = fill_size
          ; aggressor_order_id = Order.order_id order
          ; aggressor_client_order_id = Order.client_order_id order
          ; aggressor_participant = Order.participant order
          ; aggressor_side = Order.side order
          ; resting_order_id = Order.order_id resting
          ; resting_client_order_id = Order.client_order_id resting
          ; resting_participant = Order.participant resting
          }
      in
      let trade_event =
        Exchange_event.Trade_report
          { symbol = Order.symbol order
          ; price = Order.price resting
          ; size = fill_size
          }
      in
      let remaining_events, next_fill_id =
        match_loop ~book ~order ~fill_id:(fill_id + 1)
      in
      fill_event :: trade_event :: remaining_events, next_fill_id)
;;

let reject ~participant ~request ~reason =
  [ Exchange_event.Order_reject { participant; request; reason } ]
;;

let submit t ~participant (request : Order.Request.t) =
  match Map.find t.books request.symbol with
  | None -> reject ~participant ~request ~reason:"unknown symbol"
  | Some book ->
    let order_id = Order_id.Generator.next t.order_id_gen in
    let order = Order.create request ~order_id ~participant in
    (match
       try_reserve_client_order_id
         t
         ~participant
         ~client_order_id:request.client_order_id
         ~order
     with
     | `Duplicate ->
       reject ~participant ~request ~reason:"duplicate client order id"
     | `Ok ->
       let accepted =
         Exchange_event.Order_accept { order_id; participant; request }
       in
       (* Snapshot BBO before matching so we can detect changes. *)
       let bbo_before = Order_book.best_bid_offer book in
       (* Match *)
       let fill_events, next_fill_id =
         match_loop ~book ~order ~fill_id:t.next_fill_id
       in
       t.next_fill_id <- next_fill_id;
       (* Post-match: rest on book or cancel unfilled remainder. *)
       let post_events =
         if Size.( > ) (Order.remaining_size order) Size.zero
         then (
           match Order.time_in_force order with
           | Day ->
             Order_book.add book order;
             []
           | Ioc ->
             [ Exchange_event.Order_cancel
                 { order_id
                 ; client_order_id = Order.client_order_id order
                 ; participant = Order.participant order
                 ; symbol = Order.symbol order
                 ; remaining_size = Order.remaining_size order
                 ; reason = Ioc_remainder
                 }
             ])
         else []
       in
       (* Emit BBO update if the best bid or ask changed. *)
       let bbo_after = Order_book.best_bid_offer book in
       let bbo_events =
         if Bbo.equal bbo_before bbo_after
         then []
         else
           [ Exchange_event.Best_bid_offer_update
               { symbol = Order.symbol order; bbo = bbo_after }
           ]
       in
       List.concat [ [ accepted ]; fill_events; post_events; bbo_events ])
;;

let order_not_found ~participant ~client_order_id =
  Exchange_event.Cancel_reject
    { participant; client_order_id; reason = "order not found" }
;;

let cancel t ~participant ~client_order_id =
  match find_order t ~participant ~client_order_id with
  | None -> [ order_not_found ~participant ~client_order_id ]
  | Some order ->
    let symbol = Order.symbol order in
    let order_id = Order.order_id order in
    let book = Map.find_exn t.books symbol in
    (match Order_book.find book order_id with
     | None ->
       (* The order was submitted under this [(participant, client_order_id)]
          at some point, but it's no longer in the book — either fully filled
          or previously cancelled. Per the exercise spec, both are reported
          as "not found" so the client can't distinguish them. *)
       [ order_not_found ~participant ~client_order_id ]
     | Some (_ : Order.t) ->
       let bbo_before = Order_book.best_bid_offer book in
       Order_book.remove book order_id;
       let bbo_after = Order_book.best_bid_offer book in
       let cancel_event =
         Exchange_event.Order_cancel
           { order_id
           ; client_order_id
           ; participant
           ; symbol
           ; remaining_size = Order.remaining_size order
           ; reason = Participant_requested
           }
       in
       let bbo_events =
         if Bbo.equal bbo_before bbo_after
         then []
         else
           [ Exchange_event.Best_bid_offer_update { symbol; bbo = bbo_after }
           ]
       in
       cancel_event :: bbo_events)
;;
