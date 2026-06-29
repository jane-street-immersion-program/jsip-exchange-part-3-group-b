(** Scripted news events for the JSIP exchange's scenario runner.

    Exposes [News_injector], which schedules pre-configured shocks against a
    [Fundamental_oracle] at fixed offsets from a scenario's start. *)

module News_injector = News_injector
