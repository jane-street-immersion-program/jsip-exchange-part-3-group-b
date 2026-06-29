(** How long an order remains active on the exchange.

    We start with just [Day] and [Ioc]. A production exchange would also
    support [Fill_or_kill], [Good_till_cancel], [Good_till_date],
    [At_the_opening], [At_the_close], and more. *)

open! Core

type t =
  | Day
  (** Order rests on the book until end of trading day if not filled. *)
  | Ioc
  (** Immediate Or Cancel: Order executes immediately against available
      liquidity. Any unfilled portion is cancelled -- it never rests on the
      book. *)
[@@deriving sexp, bin_io, compare, equal, enumerate, hash, string]

(** Does this time-in-force allow the order to rest on the book? *)
val rests_on_book : t -> bool

val all_str : string
