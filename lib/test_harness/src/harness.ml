open! Core
open Jsip_types
open Jsip_order_book
open Jsip_gateway

(* --- Constants --- *)

let aapl = Symbol.of_string "AAPL"
let tsla = Symbol.of_string "TSLA"
let goog = Symbol.of_string "GOOG"
let alice = Participant.of_string "Alice"
let bob = Participant.of_string "Bob"
let charlie = Participant.of_string "Charlie"
let market_maker = Participant.of_string "MarketMaker"

(* --- Harness --- *)

type t = { engine : Matching_engine.t }

(* Test-only counter that supplies fresh [Client_order_id.t]s to [buy]/[sell]
   when the caller doesn't specify one. Lives at module scope because
   [buy]/[sell] don't take [t]. Reset on every [Harness.create] so IDs are
   deterministic per test.

   We deliberately start the counter at [100] so assigned IDs are
   [101, 102, ...] while server-assigned [Order_id.t]s start at [1, 2, ...].
   The large offset makes it obvious in expect output that the client and
   server ID namespaces are distinct — a bug that swapped them (or used one
   where the other was intended) would show up immediately in test output
   rather than slipping by behind identical numbers. *)
let client_order_id_offset = 100
let client_order_id_counter = ref client_order_id_offset

let next_client_order_id () =
  incr client_order_id_counter;
  Client_order_id.of_int !client_order_id_counter
;;

let reset_client_order_id_counter () =
  client_order_id_counter := client_order_id_offset
;;

let create ?(symbols = [ aapl; tsla; goog ]) () =
  reset_client_order_id_counter ();
  { engine = Matching_engine.create symbols }
;;

let engine t = t.engine

(* --- Builders --- *)

let make_request
  ~side
  ~price_cents
  ?(size = 100)
  ?(symbol = aapl)
  ?(time_in_force = Time_in_force.Day)
  ?(client_order_id = next_client_order_id ())
  ()
  : Order.Request.t
  =
  { client_order_id
  ; symbol
  ; side
  ; price = Price.of_int_cents price_cents
  ; size = Size.of_int size
  ; time_in_force
  }
;;

let buy ~price_cents ?size ?symbol ?time_in_force ?client_order_id () =
  make_request
    ~side:Buy
    ~price_cents
    ?size
    ?symbol
    ?time_in_force
    ?client_order_id
    ()
;;

let sell ~price_cents ?size ?symbol ?time_in_force ?client_order_id () =
  make_request
    ~side:Sell
    ~price_cents
    ?size
    ?symbol
    ?time_in_force
    ?client_order_id
    ()
;;

(* --- Formatting --- *)

module Show = struct
  type t = Exchange_event.t -> bool

  let all _ = true
  let only f = f
  let no_market_data event = not (Exchange_event.is_market_data event)
end

let print_events ?(show = Show.all) events =
  List.iter events ~f:(fun event ->
    if show event then print_endline (Protocol.format_event event))
;;

let print_event event = print_endline (Protocol.format_event event)

let submit ?(participant = alice) t request =
  let events = Matching_engine.submit t.engine ~participant request in
  print_events events;
  events
;;

let submit_ ?participant t request =
  ignore (submit ?participant t request : Exchange_event.t list)
;;

let submit_quiet ?(participant = alice) t request =
  Matching_engine.submit (engine t) ~participant request
;;

let sample_events : Exchange_event.t list =
  let order_request : Order.Request.t =
    { client_order_id = Client_order_id.of_int 1
    ; symbol = aapl
    ; side = Buy
    ; price = Price.of_int_cents 15000
    ; size = Size.of_int 100
    ; time_in_force = Day
    }
  in
  [ Order_accept
      { order_id = Order_id.For_testing.of_int 1
      ; participant = alice
      ; request = order_request
      }
  ; Fill
      { fill_id = 1
      ; symbol = aapl
      ; price = Price.of_int_cents 15000
      ; size = Size.of_int 100
      ; aggressor_order_id = Order_id.For_testing.of_int 2
      ; aggressor_client_order_id = Client_order_id.of_int 2
      ; aggressor_participant = alice
      ; aggressor_side = Buy
      ; resting_order_id = Order_id.For_testing.of_int 1
      ; resting_client_order_id = Client_order_id.of_int 1
      ; resting_participant = bob
      }
  ; Order_cancel
      { order_id = Order_id.For_testing.of_int 1
      ; client_order_id = Client_order_id.of_int 1
      ; participant = alice
      ; symbol = aapl
      ; remaining_size = Size.of_int 50
      ; reason = Ioc_remainder
      }
  ; Order_reject
      { request = order_request
      ; participant = alice
      ; reason = "unknown symbol"
      }
  ; Best_bid_offer_update
      { symbol = aapl
      ; bbo =
          { bid =
              Some
                { price = Price.of_int_cents 14990; size = Size.of_int 100 }
          ; ask =
              Some
                { price = Price.of_int_cents 15010; size = Size.of_int 200 }
          }
      }
  ; Trade_report
      { symbol = aapl
      ; price = Price.of_int_cents 15000
      ; size = Size.of_int 100
      }
  ]
;;

let submit_quiet_ ?participant t request =
  ignore (submit_quiet ?participant t request : Exchange_event.t list)
;;

let print_book t symbol =
  match Matching_engine.book t.engine symbol with
  | None -> print_endline [%string "unknown symbol %{symbol#Symbol}"]
  | Some book -> Order_book.snapshot book |> Book.to_string |> print_endline
;;

let print_bbo t symbol =
  match Matching_engine.book t.engine symbol with
  | None -> print_endline [%string "BBO %{symbol#Symbol}: unknown symbol"]
  | Some book ->
    let bbo = Order_book.best_bid_offer book |> Bbo.to_string in
    print_endline [%string "BBO %{symbol#Symbol}: %{bbo}"]
;;
