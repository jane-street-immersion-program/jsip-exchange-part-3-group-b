open! Core
open Jsip_scenario_runner

module type S = sig
  val name : string
  val description : string
  val configure : unit -> Scenario_config.t
end
