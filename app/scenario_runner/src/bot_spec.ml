open! Core
open Jsip_types

(* Existential wrapper around a [Bot_runtime.Bot] module + its [Config.t]
   value, so different bots with different config types can live in the same
   list. Each spec is self-contained: it carries the context the runner needs
   to bring a bot up (the symbols this bot wants market data for, its
   participant identity, an RNG seed, and its tick interval). *)
type t =
  | T :
      { bot :
          (module Jsip_bot_runtime.Bot_runtime.Bot with type Config.t = 'cfg)
      ; config : 'cfg
      ; participant : Participant.t
      ; symbols : Symbol.t list
      ; rng_seed : int
      ; tick_interval : Time_ns.Span.t
      ; is_marketdata_consumer : bool
      }
      -> t
