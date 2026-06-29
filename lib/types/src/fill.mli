(** A fill (execution) produced by the matching engine when two orders trade.

    Every fill involves exactly two sides: the "aggressor" (the incoming
    order that caused the match) and the "resting" order (which was already
    on the book). Both sides see the fill, but from their own perspective.

    A production exchange fill would carry additional metadata: liquidity
    flags, regulatory indicators, fee codes, timestamps, etc. *)

type t =
  { fill_id : int
  (** Unique fill identifier, assigned sequentially by the matching engine. *)
  ; symbol : Symbol.t
  ; price : Price.t (** The price at which the trade occurred. *)
  ; size : Size.t (** The number of shares/units traded. *)
  ; aggressor_order_id : Order_id.t
  ; aggressor_client_order_id : Client_order_id.t
  ; aggressor_participant : Participant.t
  ; aggressor_side : Side.t
  ; resting_order_id : Order_id.t
  ; resting_client_order_id : Client_order_id.t
  ; resting_participant : Participant.t
  }
[@@deriving sexp, bin_io]

(** Renders a fill showing both the server-side and client-side order IDs for
    each party for exchange-centric views. *)
val to_string : t -> string

(** {2 Convenience accessors} *)

(** The total notional value of the fill in cents (price * size). *)
val notional_cents : t -> int
