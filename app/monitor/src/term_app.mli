(** Bonsai_term rendering for the monitor.

    Wraps the pure [Controller] state machine into a bonsai_term component.
    The controller's state lives in a [Bonsai.state_machine] managed inside
    [app]; on graph activation [app] starts draining the supplied [events]
    pipe directly into that state machine. *)

open! Core
open! Async
open Jsip_types
open Bonsai_term

(** The bonsai_term app. Pass to [Bonsai_term.start_with_exit]. [events] is
    the pipe of exchange events the app should drain into its controller
    (typically the reader returned by [Rpc_protocol.audit_log_rpc]). The
    drain starts when the Bonsai graph activates and ends when [events] is
    closed. *)
val app
  :  events:Exchange_event.t Pipe.Reader.t
  -> exit:(unit -> unit Effect.t)
  -> dimensions:Dimensions.t Bonsai.t
  -> local_ Bonsai.graph
  -> view:View.t Bonsai.t * handler:(Event.t -> unit Effect.t) Bonsai.t

module For_testing : sig
  (** Pure renderer from a [Controller.Display.t] to a [View.t]. The view
      arranges filter chips, the substring field, the colored event log, the
      mode indicator, and the help footer inside a single border box.

      [?stuck_to_bottom] (default [true]) controls the auto-scroll indicator
      and the footer hint about the [a] toggle. *)
  val render_display
    :  ?stuck_to_bottom:bool
    -> Controller.Display.t
    -> View.t
end
