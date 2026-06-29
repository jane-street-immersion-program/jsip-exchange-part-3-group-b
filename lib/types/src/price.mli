(** Fixed-point price representation.

    Prices are represented as an integer number of cents. For example, the
    price $150.25 is stored as the integer 15025.

    A real exchange might use higher-precision fixed-point arithmetic (e.g.,
    9 decimal places) to support fractional-cent pricing. Our integer-cents
    representation is sufficient for equity-like instruments with penny tick
    sizes. *)

open! Core

type t [@@deriving sexp, bin_io, compare, equal, hash, string]

include Comparable.S with type t := t

(** {2 Construction} *)

(** [of_int_cents n] creates a price from an integer number of cents. For
    example, [of_int_cents 15025] represents $150.25. *)
val of_int_cents : int -> t

(** [of_float_exn f] creates a price from a float dollar amount. Raises if
    the float does not represent an exact number of cents. Prefer
    [of_int_cents] when possible to avoid float issues. *)
val of_float_exn : float -> t

(** {2 Accessors} *)

(** Returns the price as an integer number of cents. *)
val to_int_cents : t -> int

(** Returns the price as a float dollar amount (e.g., 150.25). *)
val to_float : t -> float

(** {2 Arithmetic} *)

val zero : t
val ( + ) : t -> t -> t
val ( - ) : t -> t -> t

(** Multiply a price by an integer quantity. Useful for computing notional
    value: [price * size] gives you the total dollar value in cents. *)
val ( * ) : t -> int -> t

(** {2 Comparison} *)

(** Returns whether a price is "more aggressive" for the given side. For a
    buyer, a higher price is more aggressive (willing to pay more). For a
    seller, a lower price is more aggressive (willing to accept less).

    [is_more_aggressive side ~price ~than] returns [true] when [price] would
    execute before [than] in a price-priority order book.

    Currently unimplemented — raises [Failure]. Filling this in is one of the
    project's exercises. *)
val is_more_aggressive : Side.t -> price:t -> than:t -> bool

(** Would an order on the given side trade against a resting order at
    [resting_price]? A buy order is marketable if its price >= the resting
    ask price. A sell order is marketable if its price <= the resting bid
    price.

    Currently unimplemented — raises [Failure]. Filling this in is one of the
    project's exercises. *)
val is_marketable : Side.t -> price:t -> resting_price:t -> bool

(** {2 Display} *)

(** Pretty-prints as a dollar amount, e.g., "$150.25". *)
val to_string_dollar : t -> string
