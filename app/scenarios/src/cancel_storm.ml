open! Core
open Jsip_types
open Jsip_scenario_runner

let name = "cancel-storm"

let description =
  "A crowd of bots that submit-then-immediately-cancel in a tight loop, \
   hammering the cancel path and duplicate-ID bookkeeping."
;;

let symbol = Symbol.of_string "AAPL"
let num_bots = 4

let oracle_config : Jsip_fundamental.Fundamental_oracle.Config.t =
  Symbol.Map.of_alist_exn
    [ ( symbol
      , { Jsip_fundamental.Fundamental_oracle.Config.initial_price_cents =
            15000
        ; volatility_cents_per_sec = 0.0
        ; mean_reversion_strength = 0.0
        ; tick_interval = Time_ns.Span.of_sec 1.0
        } )
    ]
;;

(* Each bot gets its own participant, RNG seed, and (crucially) its own
   [next_id] ref, so their fresh-ID counters are independent. *)
let storm_bot index : Bot_spec.t =
  let config =
    Jsip_bots.Cancel_storm.Config.create
      ~symbols:[ symbol ]
      ~cycles_per_tick:50
      ~max_in_flight:10
      ~size:100
      ~passive_offset_cents:100
      ()
  in
  T
    { bot = (module Jsip_bots.Cancel_storm)
    ; config
    ; participant =
        Participant.of_string [%string "CancelStorm-%{index#Int}"]
    ; symbols = [ symbol ]
    ; rng_seed = index
    ; tick_interval = Time_ns.Span.of_ms 100.0
    ; is_marketdata_consumer = false
    }
;;

let configure () : Scenario_config.t =
  { name
  ; symbols = [ symbol ]
  ; oracle_config
  ; news = []
  ; bots = List.init num_bots ~f:storm_bot
  }
;;
