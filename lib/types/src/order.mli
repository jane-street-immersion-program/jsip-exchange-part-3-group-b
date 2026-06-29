(** An order submitted to the exchange.

    A production exchange order would carry extensive metadata: client
    identifiers, regulatory flags, risk group assignment, execution
    instructions, and more. We keep orders simple: a participant wants to buy
    or sell some quantity of a symbol at a given price. *)

open! Core

(** An order as submitted by a participant (before the exchange assigns a
    server-side order ID). This is what the gateway receives. The submitting
    participant is not included here — it is established at connection time
    via [login_rpc] and attached by the server. *)
module Request : sig
  type t =
    { client_order_id : Client_order_id.t
    (** The client's chosen order ID. Used by the client to refer to this
        order (e.g., to cancel it) without waiting for the exchange's
        response. *)
    ; symbol : Symbol.t
    ; side : Side.t
    ; price : Price.t
    ; size : Size.t (** Number of shares/units. Must be positive. *)
    ; time_in_force : Time_in_force.t
    }
  [@@deriving sexp, bin_io]

  val to_string : t -> string
end

(** A live order on the exchange, with an ID assigned by the matching engine
    and mutable remaining size. *)
type t [@@deriving sexp_of, equal, compare]

val to_string : t -> string

(** {2 Construction} *)

(** Create a live order from a request, an assigned order ID, and the
    submitting participant. The [remaining_size] starts equal to the
    request's [size]. *)
val create
  :  Request.t
  -> order_id:Order_id.t
  -> participant:Participant.t
  -> t

(** {2 Accessors} *)

val order_id : t -> Order_id.t
val client_order_id : t -> Client_order_id.t
val symbol : t -> Symbol.t
val participant : t -> Participant.t
val side : t -> Side.t
val price : t -> Price.t
val size : t -> Size.t
val remaining_size : t -> Size.t
val time_in_force : t -> Time_in_force.t

(** {2 Mutation}

    The matching engine updates remaining size as fills occur. *)

(** Reduce the remaining size by [by]. Raises if [by] is larger than
    [remaining_size] or non-positive. *)
val fill : t -> by:Size.t -> unit

(** Is this order fully filled? (remaining_size = 0) *)
val is_fully_filled : t -> bool
