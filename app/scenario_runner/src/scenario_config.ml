open! Core
open Jsip_types

type t =
  { name : string
  ; symbols : Symbol.t list
  ; oracle_config : Jsip_fundamental.Fundamental_oracle.Config.t
  ; news : Jsip_news_injector.News_injector.Event.t list
  ; bots : Bot_spec.t list
  }
