open! Core
open Jsip_types
open Jsip_scenario_runner
module Bot_runtime = Jsip_bot_runtime.Bot_runtime
module Fundamental_oracle = Jsip_fundamental.Fundamental_oracle

(** Drives the {!Jsip_bots.Spammer}.

    A fresh exchange booted with just this scenario should exhibit the
    request-queue / pipe-bandwidth pathology within ~30s. The spammer rests
    wildly-priced orders that never fill (see {!Jsip_bots.Spammer}), so it
    needs no counterparty to misbehave — the cast is just the spammer(s)
    themselves. Bump {!num_spammers} or {!orders_per_tick} to turn up the
    heat, or shorten {!tick_interval} to fire bursts more often. *)

let name = "order-spam"

let description =
  "A burst-submitting spammer that floods the request queue and subscriber \
   pipes with resting orders that never fill."
;;

(* The symbols to spam. Each fundamental sits between the spammer's
   never-marketable bid/ask, so nothing the spammer sends can cross. Add
   tickers to this list to spread the flood over several order books at once. *)
let symbols = [ Symbol.of_string "SPAM" ]
let fundamental_price_cents = 10_000

(* Load knobs — the things you'll actually turn while testing on_tick. *)
let num_spammers = 1
let orders_per_tick = 50
let size_per_order = 10
let tick_interval = Time_ns.Span.of_sec 1.0

(* Build one spammer [Bot_spec.t]. Each instance gets its own participant
   name, RNG seed, and — crucially — its own [next_client_order_id] counter,
   so two spammers never mint the same id. *)
let spammer_spec ~participant ~rng_seed : Bot_spec.t =
  let config : Jsip_bots.Spammer.Config.t =
    { symbols
    ; orders_per_tick
    ; size = size_per_order
    ; next_client_order_id = ref 0
    }
  in
  Bot_spec.T
    { bot = (module Jsip_bots.Spammer)
    ; config
    ; participant
    ; symbols
    ; rng_seed
    ; tick_interval
    ; is_marketdata_consumer = false
    }
;;

let configure () : Scenario_config.t =
  let oracle_config : Fundamental_oracle.Config.t =
    let symbol_config : Fundamental_oracle.Config.symbol_config =
      { initial_price_cents = fundamental_price_cents
      ; volatility_cents_per_sec = 5.0
      ; mean_reversion_strength = 0.1
      ; tick_interval = Time_ns.Span.of_sec 0.5
      }
    in
    Symbol.Map.of_alist_exn
      (List.map symbols ~f:(fun symbol -> symbol, symbol_config))
  in
  let bots =
    List.init num_spammers ~f:(fun i ->
      spammer_spec
        ~participant:(Participant.of_string [%string "spammer-%{i#Int}"])
        ~rng_seed:i)
  in
  { name; symbols; oracle_config; news = []; bots }
;;
