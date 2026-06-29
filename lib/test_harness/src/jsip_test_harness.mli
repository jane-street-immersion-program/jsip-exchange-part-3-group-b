(** Shared test utilities for the JSIP exchange.

    [Harness] wraps an in-process matching engine with convenience
    constructors (canonical participants, order builders) and printing
    helpers, for unit and matching-scenario tests.

    [E2e_helpers] spins up a real [Exchange_server] on an OS-assigned port
    and exposes RPC helpers ([connect], [rpc_submit], [rpc_book]) for
    end-to-end tests that need to go over the wire. *)

module Harness = Harness
module E2e_helpers = E2e_helpers
