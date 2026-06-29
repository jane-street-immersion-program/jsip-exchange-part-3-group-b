open! Core
open! Async
open Jsip_types

module Config = struct
  type symbol_config =
    { initial_price_cents : int
    ; volatility_cents_per_sec : float
    ; mean_reversion_strength : float
    ; tick_interval : Time_ns.Span.t
    }
  [@@deriving sexp_of]

  type t = symbol_config Symbol.Map.t [@@deriving sexp_of]
end

(* Box-Muller: two independent uniform(0, 1) samples produce one standard
   normal sample. We discard the second so the call site is simple; this is
   wasteful but the volume is low. *)
let standard_normal rng =
  let u1 =
    (* Avoid log(0). [Splittable_random.float] returns values in [0, 1). *)
    Float.max
      (Splittable_random.float rng ~lo:0.0 ~hi:1.0)
      Float.epsilon_float
  in
  let u2 = Splittable_random.float rng ~lo:0.0 ~hi:1.0 in
  Float.sqrt (-2.0 *. Float.log u1) *. Float.cos (2.0 *. Float.pi *. u2)
;;

type symbol_state =
  { config : Config.symbol_config
  ; mutable price_cents : float
  ; rng : Splittable_random.t
  }

type t = symbol_state Symbol.Map.t

(* The simulated fundamental is clamped to a strictly-positive floor so it
   can never be zero or negative — that would produce nonsensical prices and
   risk dividing by zero in downstream consumers. One cent is the smallest
   representable price tick. *)
let min_price_cents = 1.0

let create (config : Config.t) ~seed =
  let root_rng = Splittable_random.of_int seed in
  Map.mapi config ~f:(fun ~key:_ ~data:symbol_config ->
    { config = symbol_config
    ; price_cents = Float.of_int symbol_config.initial_price_cents
    ; rng = Splittable_random.split root_rng
    })
;;

let symbol_state_exn t symbol =
  match Map.find t symbol with
  | Some symbol_state -> symbol_state
  | None ->
    raise_s
      [%message
        "Fundamental_oracle: symbol not in config" (symbol : Symbol.t)]
;;

let price t symbol =
  let symbol_state = symbol_state_exn t symbol in
  Price.of_int_cents (Float.iround_nearest_exn symbol_state.price_cents)
;;

(* One discretized OU step:

   dp = theta * (mu - p) * dt + sigma * sqrt(dt) * N(0, 1)

   With dt set from [tick_interval] (in seconds). *)
let advance symbol_state =
  let dt =
    Time_ns.Span.to_sec symbol_state.config.tick_interval
    |> Float.max Float.epsilon_float
  in
  let mu = Float.of_int symbol_state.config.initial_price_cents in
  let theta = symbol_state.config.mean_reversion_strength in
  let sigma = symbol_state.config.volatility_cents_per_sec in
  let drift = theta *. (mu -. symbol_state.price_cents) *. dt in
  let shock = sigma *. Float.sqrt dt *. standard_normal symbol_state.rng in
  let next = symbol_state.price_cents +. drift +. shock in
  symbol_state.price_cents <- Float.max min_price_cents next
;;

let start t =
  Map.data t
  |> List.map ~f:(fun symbol_state ->
    Clock_ns.every symbol_state.config.tick_interval (fun () ->
      advance symbol_state);
    Deferred.never ())
  |> Deferred.all_unit
;;

let inject_shock t symbol ~delta_cents =
  let symbol_state = symbol_state_exn t symbol in
  symbol_state.price_cents
  <- Float.max
       min_price_cents
       (symbol_state.price_cents +. Float.of_int delta_cents)
;;

module For_testing = struct
  let advance_step t symbol = advance (symbol_state_exn t symbol)
end
