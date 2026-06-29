(** Core types shared across the JSIP exchange.

    Foundational data — sides, prices, sizes, symbols, participants, orders,
    fills, levels, BBO snapshots, full book snapshots, exchange events, and
    cancellation reasons — used by every other layer. *)

module Bbo = Bbo
module Book = Book
module Cancel_reason = Cancel_reason
module Client_order_id = Client_order_id
module Exchange_event = Exchange_event
module Fill = Fill
module Level = Level
module Order = Order
module Order_id = Order_id
module Participant = Participant
module Price = Price
module Side = Side
module Size = Size
module Symbol = Symbol
module Time_in_force = Time_in_force
