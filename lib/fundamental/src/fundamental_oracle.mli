(** A simulated "true price" process per symbol.

    The matching engine has no concept of fundamental value: prices are
    wherever orders cross. To produce visually-interesting traffic, the bot
    ecosystem needs an exogenous notion of fair value to anchor strategies.
    This oracle simulates one.

    Each symbol's price evolves as a discretized Ornstein-Uhlenbeck process:
    a random walk with optional mean reversion toward [initial_price]. The
    Gaussian noise is drawn from a [Splittable_random.t] seeded at
    construction so a given seed + scenario produces deterministic price
    trajectories.

    Bots read the current price directly via [price]. This is unrealistic
    relative to real markets (where there is no oracle) but is the right
    tradeoff for a teaching prototype: it makes scenarios easy to script and
    bot behavior easy to reason about. *)

open! Core
open! Async
open Jsip_types

type t

module Config : sig
  type symbol_config =
    { initial_price_cents : int (** Long-run mean and starting price. *)
    ; volatility_cents_per_sec : float
    (** Standard deviation of the per-second price change, in cents. Higher =
        more volatile symbol. *)
    ; mean_reversion_strength : float
    (** Per-second mean-reversion rate. [0.0] is a pure random walk; larger
        values pull the price back toward [initial_price_cents] faster.
        Typical values: 0.0 to 0.2. *)
    ; tick_interval : Time_ns.Span.t
    (** How often the process advances. Smaller intervals produce smoother
        curves at the cost of more CPU. *)
    }
  [@@deriving sexp_of]

  type t = symbol_config Symbol.Map.t [@@deriving sexp_of]
end

(** Create an oracle. [seed] controls reproducibility; the same seed and
    config produce the same price trajectory. *)
val create : Config.t -> seed:int -> t

(** The current fundamental price for a symbol. Raises if the symbol is not
    in the config. *)
val price : t -> Symbol.t -> Price.t

(** Start the per-symbol tick loops. Returns a [Deferred.t] that never
    completes (each loop runs forever). Call this once after [create]. *)
val start : t -> unit Deferred.t

(** Apply a one-time additive shock to a symbol's fundamental, in cents. Used
    by the news injector to model events like earnings surprises. Negative
    deltas are allowed but the price is clamped to a minimum of 1 cent. *)
val inject_shock : t -> Symbol.t -> delta_cents:int -> unit

module For_testing : sig
  (** Advance a single symbol by one OU step without going through
      [Async.Clock]. *)
  val advance_step : t -> Symbol.t -> unit
end
