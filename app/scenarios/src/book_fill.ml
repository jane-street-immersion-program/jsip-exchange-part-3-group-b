open! Core
open Jsip_types
open Jsip_scenario_runner
module Book_filler = Jsip_bots.Book_filler
module Fundamental_oracle = Jsip_fundamental.Fundamental_oracle

let name = "book-fill"

let description =
  "Book-filler pathology: several bots pile deep, non-marketable resting \
   Day orders, growing order-book memory and slowing BBO/snapshot \
   recomputation."
;;

let symbols = [ Symbol.of_string "AAPL"; Symbol.of_string "MSFT" ]

(* A flat fundamental (no volatility, no mean reversion) keeps the touch
   fixed so the fillers' offset band is guaranteed to stay non-marketable for
   the whole run. The book filler doesn't need price movement to do its
   damage. *)
let oracle_config : Fundamental_oracle.Config.t =
  Symbol.Map.of_alist_exn
    (List.map symbols ~f:(fun symbol ->
       ( symbol
       , { Fundamental_oracle.Config.initial_price_cents = 15000
         ; volatility_cents_per_sec = 0.0
         ; mean_reversion_strength = 0.0
         ; tick_interval = Time_ns.Span.of_sec 1.0
         } )))
;;

(* One filler already grows the book without bound; a small crowd across both
   symbols just reaches a painful book size sooner and shows the pathology
   isn't symbol-specific. Each instance is an independent participant with
   its own RNG seed and its own [client_order_id] counter. *)
let num_fillers = 4

let filler_spec ~index : Bot_spec.t =
  let participant =
    Participant.of_string [%string "BookFiller-%{index#Int}"]
  in
  let config =
    Book_filler.Config.create
      ~symbols
      ~orders_per_tick:100
      ~size:1
      ~min_offset_cents:100
      ~max_offset_cents:5000
      ()
  in
  Bot_spec.T
    { bot = (module Book_filler)
    ; config
    ; participant
    ; symbols
    ; rng_seed = 1000 + index
    ; tick_interval = Time_ns.Span.of_ms 100.0
    ; is_marketdata_consumer = false
    }
;;

let configure () : Scenario_config.t =
  { name
  ; symbols
  ; oracle_config
  ; news = []
  ; bots = List.init num_fillers ~f:(fun index -> filler_spec ~index)
  }
;;
