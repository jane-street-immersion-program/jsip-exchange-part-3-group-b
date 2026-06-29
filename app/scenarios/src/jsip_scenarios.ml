open! Core
module Scenario = Scenario
module Calm_day = Calm_day
module Active_day = Active_day
module Earnings_shock = Earnings_shock
module Flash_crash = Flash_crash

let all : (module Scenario.S) list =
  [ (module Calm_day)
  ; (module Active_day)
  ; (module Earnings_shock)
  ; (module Flash_crash)
  ]
;;

let all_names =
  List.map all ~f:(fun (module S : Scenario.S) -> S.name)
  |> List.sort ~compare:String.compare
;;

let find_by_name name =
  match
    List.find all ~f:(fun (module S : Scenario.S) ->
      String.equal S.name name)
  with
  | Some s -> Ok s
  | None ->
    Or_error.error_s
      [%message
        "unknown scenario"
          ~given:(name : string)
          ~known:(all_names : string list)]
;;
