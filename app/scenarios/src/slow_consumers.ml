open! Core
open Jsip_types
open Jsip_scenario_runner
module Noise_trader = Jsip_bots.Noise_trader
module Slow_consumer = Jsip_bots.Slow_consumer
module Fundamental_oracle = Jsip_fundamental.Fundamental_oracle

let name = "slow-consumers"

let description =
  "Slow-consumer pathology: a crowd of market-data subscribers that never \
   drain their pipes, so the exchange-side buffers holding events for them \
   grow without bound while noise traders keep the feed busy."
;;

let symbols = [ Symbol.of_string "AAPL" ]

let oracle_config : Fundamental_oracle.Config.t =
  Symbol.Map.of_alist_exn
    (List.map symbols ~f:(fun symbol ->
       ( symbol
       , { Fundamental_oracle.Config.initial_price_cents = 15000
         ; volatility_cents_per_sec = 5.0
         ; mean_reversion_strength = 0.1
         ; tick_interval = Time_ns.Span.of_sec 0.25
         } )))
;;

(* The noise traders exist only to fill the market-data feed. A handful,
   quoting around the touch on a fast tick, cross each other constantly and
   produce a steady stream of trades and BBO updates. *)
let num_noise_traders = 4

let noise_trader_spec ~index : Bot_spec.t =
  let participant = Participant.of_string [%string "Noise-%{index#Int}"] in
  let config =
    Noise_trader.Config.create
      ~symbols
      ~orders_per_tick:10
      ~jitter_cents:25
      ~size:10
      ()
  in
  Bot_spec.T
    { bot = (module Noise_trader)
    ; config
    ; participant
    ; symbols
    ; rng_seed = 100 + index
    ; tick_interval = Time_ns.Span.of_ms 50.0
    ; is_marketdata_consumer = false
    }
;;

(* The pathology. Each one subscribes to market data (so the exchange opens
   an unbounded per-subscriber buffer for it) and then never reads it. One
   would stall its own pipe; running a crowd makes the aggregate memory the
   exchange is forced to hold obvious within seconds. *)
let num_slow_consumers = 30

let slow_consumer_spec ~index : Bot_spec.t =
  let participant = Participant.of_string [%string "Slow-%{index#Int}"] in
  let config =
    Slow_consumer.Config.create
      ~read_behavior:Slow_consumer.Read_behavior.Never
  in
  Bot_spec.T
    { bot = (module Slow_consumer)
    ; config
    ; participant
    ; symbols
    ; rng_seed = index
    ; tick_interval = Time_ns.Span.of_sec 1.0
    ; is_marketdata_consumer = true
    }
;;

let configure () : Scenario_config.t =
  { name
  ; symbols
  ; oracle_config
  ; news = []
  ; bots =
      List.init num_noise_traders ~f:(fun index -> noise_trader_spec ~index)
      @ List.init num_slow_consumers ~f:(fun index ->
        slow_consumer_spec ~index)
  }
;;
