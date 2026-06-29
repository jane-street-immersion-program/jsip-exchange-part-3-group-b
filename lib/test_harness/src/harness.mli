(** Shared test harness for the JSIP exchange.

    Provides a self-contained exchange environment for tests.

    Usage:
    {[
      open Jsip_test_harness

      let%expect_test "my test" =
        let t = Harness.create () in
        Harness.submit t (Harness.buy ~price_cents:15000 ());
        [%expect {| ... |}]
      ;;
    ]} *)

open! Core
open Jsip_types
open Jsip_order_book

(** {2 Constants}

    Pre-registered symbols and participants for use in tests. Using
    consistent names across all tests makes expect output easy to read and
    compare. *)

val aapl : Symbol.t
val tsla : Symbol.t
val goog : Symbol.t
val alice : Participant.t
val bob : Participant.t
val charlie : Participant.t
val market_maker : Participant.t

(** {2 Harness} *)

type t

(** Create a fresh exchange harness with the given symbols. Defaults to
    [[aapl; tsla; goog]]. All symbols and participants are automatically
    registered.

    Also resets the test-only [client_order_id] counter so IDs within a test
    start at [101]. The large offset from the server-assigned [Order_id.t]
    sequence (which starts at [1]) makes the two namespaces visually distinct
    in expect output so that a bug that swaps them would show up immediately. *)
val create : ?symbols:Symbol.t list -> unit -> t

(** Reset the test-only [client_order_id] counter so the next [buy]/[sell]
    call assigns [client_order_id = 101].

    Not normally called from tests directly: [create] calls this
    automatically, and [E2e_helpers.with_server] calls it for e2e tests that
    use a real server (where there's no harness). Exposed here only because
    [E2e_helpers] lives in a separate module and needs access. *)
val reset_client_order_id_counter : unit -> unit

(** The underlying matching engine. *)
val engine : t -> Matching_engine.t

(** {2 Order request builders}

    These build [Order.Request.t] values with sensible defaults:
    - symbol: AAPL
    - size: 100
    - time_in_force: Day
    - client_order_id: the next integer from an internal counter that resets
      in [create], so IDs within a test are [1, 2, 3, ...]. Override
      explicitly to test specific IDs (e.g., duplicates).

    Participant is supplied at submission time (see [submit] below),
    defaulting to Alice. *)

val buy
  :  price_cents:int
  -> ?size:int
  -> ?symbol:Symbol.t
  -> ?time_in_force:Time_in_force.t
  -> ?client_order_id:Client_order_id.t
  -> unit
  -> Order.Request.t

val sell
  :  price_cents:int
  -> ?size:int
  -> ?symbol:Symbol.t
  -> ?time_in_force:Time_in_force.t
  -> ?client_order_id:Client_order_id.t
  -> unit
  -> Order.Request.t

(** {2 Actions}

    These submit orders and immediately print the resulting events, which is
    the common pattern in expect tests.

    [?participant] defaults to [alice]. Multi-participant tests override it. *)

(** Submit an order through the matching engine and print all resulting
    events. Returns the event list for further inspection. *)
val submit
  :  ?participant:Participant.t
  -> t
  -> Order.Request.t
  -> Exchange_event.t list

(** Submit and print, discarding the return value. *)
val submit_ : ?participant:Participant.t -> t -> Order.Request.t -> unit

(** {2 Sample events}

    A standard set of [Exchange_event.t] values — one of each constructor —
    used across tests that need stable, hand-built events (e.g. monitor and
    filter tests). All events use [aapl] as the symbol and the canonical
    [alice]/[bob] participants. *)

(** [sample_events] contains exactly one of each [Exchange_event.t] variant,
    in declaration order: [Order_accept], [Fill], [Order_cancel],
    [Order_reject], [Best_bid_offer_update], [Trade_report]. *)
val sample_events : Exchange_event.t list

(** As [submit], but events are not printed. *)
val submit_quiet
  :  ?participant:Participant.t
  -> t
  -> Order.Request.t
  -> Exchange_event.t list

(** As [submit_quiet], but event are not printed. *)
val submit_quiet_
  :  ?participant:Participant.t
  -> t
  -> Order.Request.t
  -> unit

(** {2 Formatting}

    Control how events and book state are displayed in expect test output. *)

(** Which event fields to include in output. *)
module Show : sig
  type t

  (** Show everything (default). *)
  val all : t

  (** Show only events matching the given filter. *)
  val only : (Exchange_event.t -> bool) -> t

  (** Hide market data events (BBO updates and trade reports). Useful when
      testing matching logic without market data noise. *)
  val no_market_data : t
end

(** Print a list of events. By default prints all events; pass [~show] to
    filter. *)
val print_events : ?show:Show.t -> Exchange_event.t list -> unit

(** Print a single event. *)
val print_event : Exchange_event.t -> unit

(** Print the current order book for a symbol. Shows bids, asks, and the BBO. *)
val print_book : t -> Symbol.t -> unit

(** Print a concise BBO summary for a symbol. *)
val print_bbo : t -> Symbol.t -> unit
