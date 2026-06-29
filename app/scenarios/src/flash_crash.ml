open! Core
open Jsip_scenario_runner

let name = "flash-crash"

let description =
  "Tight sequence of large negative shocks plus a sell-heavy whale; market \
   makers pull quotes and liquidity collapses."
;;

let configure () : Scenario_config.t = failwith "TODO: implement Flash_crash"
