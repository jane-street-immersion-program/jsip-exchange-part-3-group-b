(** A bonsai_term-based monitor for the JSIP exchange.

    [Event_log] is the pure filterable model of the exchange event stream.
    [Controller] sits on top of it and adds the UI state machine (enabled
    filter chips, substring edit buffer, quit flag) that the bonsai_term
    layer renders. [Term_app] wraps the controller into a bonsai_term
    component that an exchange binary can hand to
    [Bonsai_term.start_with_exit]. *)

module Controller = Controller
module Event_log = Event_log
module Term_app = Term_app
