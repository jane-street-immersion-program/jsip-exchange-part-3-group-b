(** A named, runnable scenario.

    Each scenario module under [app/scenarios/src/] satisfies this signature.
    The scenario runner picks one from the command line by [config.name] and
    hands [config] to [Jsip_scenario_runner.Runner]. *)

open! Core
open Jsip_scenario_runner

module type S = sig
  (** Short kebab-cased identifier used to pick this scenario from the
      command line (e.g. ["calm-day"]). This is what students type after
      [-scenario] when launching the runner. *)
  val name : string

  (** A short one-line description shown in [--help] output beside the
      scenario's name. *)
  val description : string

  (** The scenario's full configuration: symbols, oracle, news events, and
      bots. A thunk rather than a value so an unimplemented scenario's
      [failwith "TODO"] doesn't blow up module initialization for the whole
      registry — only the scenario actually selected on the command line is
      forced. *)
  val configure : unit -> Scenario_config.t
end
