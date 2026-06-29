(** Order book and matching engine for the JSIP exchange.

    Provides the order book data structure that holds resting orders for a
    single symbol, and the matching engine that manages order books across
    all symbols, executes trades, and produces exchange events. *)

module Order_book = Order_book
module Matching_engine = Matching_engine
