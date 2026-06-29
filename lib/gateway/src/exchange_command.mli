(** Text commands accepted by the interactive exchange client.

    Each command is a single line of text:
    {v
    LOGIN <participant>
    BUY  <client_id> <symbol> <size> <price> [<time_in_force>]
    SELL <client_id> <symbol> <size> <price> [<time_in_force>]
    CANCEL <client_id>
    BOOK <symbol>
    SUBSCRIBE <symbol>
    v}

    Examples:
    {v
    LOGIN Alice
    BUY 1 AAPL 100 150.25
    SELL 2 TSLA 50 200.00 IOC
    CANCEL 1
    BOOK AAPL
    SUBSCRIBE AAPL
    v}

    The [<client_id>] is chosen by the client and used to correlate
    acknowledgments, fills, and cancellations. Time-in-force defaults to DAY
    if omitted. A participant must log in once per connection before
    submitting or cancelling orders; order and cancel commands implicitly act
    on behalf of the logged-in participant. *)

open! Core
open Jsip_types

type t =
  | Login of { name : string }
  | Submit of Order.Request.t
  | Cancel of { client_order_id : Client_order_id.t }
  | Book of Symbol.t
  | Subscribe of Symbol.t
[@@deriving to_string]

(** Parse a text command. Returns [Error] with a human-readable message if
    the input is malformed. *)
val parse : string -> t Or_error.t
