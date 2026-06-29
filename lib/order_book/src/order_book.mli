(** A single-symbol order book with a bid side and an ask side.

    An order book is the core data structure of an exchange. It holds all
    resting (unmatched) orders for a given symbol, organized into bids (buy
    orders) and asks (sell orders). When a new order arrives, the matching
    engine queries the book to find compatible resting orders. *)

open! Core
open Jsip_types

type t [@@deriving sexp_of]

(** Create an empty order book for a given symbol. *)
val create : Symbol.t -> t

(** The symbol this book is for. *)
val symbol : t -> Symbol.t

(** {2 Order management} *)

(** Add a resting order to the appropriate side of the book. The order must
    be for this book's symbol and must have remaining size > 0. *)
val add : t -> Order.t -> unit

(** Remove an order by ID. *)
val remove : t -> Order_id.t -> unit

(** Find a resting order by ID. *)
val find : t -> Order_id.t -> Order.t option

(** {2 Matching} *)

(** Find the best resting order that the given incoming order could trade
    against. Returns [None] if no resting order on the opposite side is
    marketable at the incoming order's price.

    "Best" means the most aggressively priced resting order: the lowest ask
    for an incoming buy, or the highest bid for an incoming sell. Among
    orders at the same price, the one that arrived first should be preferred
    (price-time priority). *)
val find_match : t -> Order.t -> Order.t option

(** {2 Book queries} *)

(** All resting orders on the given side. *)
val orders_on_side : t -> Side.t -> Order.t list

(** Is the book completely empty (no bids, no asks)? *)
val is_empty : t -> bool

(** Number of resting orders on a given side. *)
val count : t -> Side.t -> int

(** The best bid and offer: the most aggressive price and total size on each
    side. *)
val best_bid_offer : t -> Bbo.t

(** Create a read-only snapshot of the book suitable for sending over RPC or
    displaying. Orders are sorted by price (best first). *)
val snapshot : t -> Book.t

(** {2 Testing}

    In tests we want to check that the correct order was removed, so we
    expose a version of [remove] that returns the removed order. *)

module For_testing : sig
  val remove : t -> Order_id.t -> Order.t option
end
