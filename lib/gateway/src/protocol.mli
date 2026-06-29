(** Text protocol for communicating with the exchange.

    This module defines how exchange events are formatted for display. On a
    production exchange, this would be a binary protocol like FIX for
    performance and interoperability. We use a simple human-readable text
    format for ease of debugging and interactive use. *)

open! Core
open Jsip_types

(** Format an exchange event as a single line of human-readable text. Shows
    both the server-assigned and client-chosen order IDs — an
    exchange-centric view suitable for operator logs and tests. *)
val format_event : Exchange_event.t -> string

(** Format a list of events, one per line. *)
val format_events : Exchange_event.t list -> string
