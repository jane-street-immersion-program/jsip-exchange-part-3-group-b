(** Runtime scaffolding for automated trading bots.

    Exposes [Bot_runtime], which owns the per-bot boilerplate (participant
    identity, oracle access, RNG, [submit]/[cancel] RPC closures), drives
    periodic [on_tick] callbacks, and dispatches incoming events to each
    bot's [on_event] handler. Strategy-specific state — BBOs, inventory, open
    quotes — is left to the individual bot. *)

module Bot_runtime = Bot_runtime
