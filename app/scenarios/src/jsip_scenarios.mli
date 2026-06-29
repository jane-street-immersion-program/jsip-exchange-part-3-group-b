(** Registry of all known JSIP scenarios.

    Each scenario module under [app/scenarios/src/] satisfies the
    {!Scenario.S} signature; to add a new one, drop a new [.ml] file into
    this directory and append [(module My_new_scenario)] to {!all} below.

    The scenario runner ([app/scenario_runner/bin/main.ml]) consumes this
    registry to populate the [-scenario] command-line argument and to
    dispatch to the chosen scenario's [configure]. *)

open! Core
module Scenario = Scenario
module Calm_day = Calm_day
module Active_day = Active_day
module Earnings_shock = Earnings_shock
module Flash_crash = Flash_crash

(** All scenarios known to the runner, in the order they should appear in
    [-help] output. *)
val all : (module Scenario.S) list

(** Look up a scenario by its short kebab-cased name (see [Scenario.S.name]).
    Returns an error listing the known names if no match is found. *)
val find_by_name : string -> (module Scenario.S) Or_error.t

(** Sorted list of every scenario's [name], handy for help text and
    diagnostics. *)
val all_names : string list
