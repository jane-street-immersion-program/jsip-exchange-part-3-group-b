open! Core
open! Async
open Jsip_scenario_runner
open Jsip_scenarios

let scenario_arg =
  Command.Arg_type.of_alist_exn
    ~list_values_in_help:true
    (List.map all ~f:(fun (module S : Scenario.S) ->
       S.name, (module S : Scenario.S)))
;;

let command =
  Command.async
    ~summary:
      "Run a JSIP scenario: boots an exchange and a configured ecosystem of \
       bots."
    (let%map_open.Command (module S : Scenario.S) =
       flag "-scenario" (required scenario_arg) ~doc:"NAME scenario to run"
     and port =
       flag
         "-port"
         (optional_with_default 12345 int)
         ~doc:"PORT TCP port to listen on (default 12345)"
     and seed =
       flag
         "-seed"
         (optional_with_default 0 int)
         ~doc:"INT random seed for reproducible scenarios (default 0)"
     in
     fun () ->
       let config = S.configure () in
       Runner.run config ~port ~seed)
    ~behave_nicely_in_pipeline:false
;;

let () = Command_unix.run command
