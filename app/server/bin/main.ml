(** Exchange server.

    Runs the matching engine and listens for RPC connections from clients..

    Run with: dune exec app/server/bin/main.exe -- -port 12345

    Optionally seed the book with a market maker: dune exec
    app/server/bin/main.exe -- -port 12345 -seed-market-maker *)

open! Core
open! Async
open Jsip_types
open Jsip_gateway
open Jsip_market_maker

let default_symbols =
  [ Symbol.of_string "AAPL"
  ; Symbol.of_string "TSLA"
  ; Symbol.of_string "GOOG"
  ; Symbol.of_string "MSFT"
  ]
;;

let connect_as ~where_to_connect participant =
  (* TODO: once login_rpc exists (week 2, exercise 1), dispatch it here so
     the server knows which participant this connection belongs to. For now
     we just open the TCP connection. *)
  ignore participant;
  Rpc.Connection.client where_to_connect >>| Result.ok_exn
;;

let seed_market_maker ~where_to_connect =
  let aapl = Symbol.of_string "AAPL" in
  let mm_participant = Participant.of_string "MarketMaker" in
  let config : Market_maker.Config.t =
    { participant = mm_participant
    ; symbol = aapl
    ; fair_value_cents = 15000
    ; half_spread_cents = 10
    ; size_per_level = 100
    ; num_levels = 5
    }
  in
  let%bind conn = connect_as ~where_to_connect mm_participant in
  Market_maker.seed_book config conn
;;

(* Two market makers per symbol with offset fair values: MM_High's bids cross
   MM_Low's asks every cycle, producing a steady stream of [Fill] /
   [Trade_report] events across multiple symbols for the monitor to render.

   Because [Market_maker.seed_book] always submits Day orders and there is no
   cancel yet, the un-crossable levels (MM_Low's bids and MM_High's asks)
   accumulate over time — this mode is for short demos, not long-running load
   tests. *)
let trade_back_and_forth ~where_to_connect =
  (* One pair of MMs per symbol, anchored at a representative fair value. *)
  let symbol_anchors =
    [ Symbol.of_string "AAPL", 15000
    ; Symbol.of_string "TSLA", 25000
    ; Symbol.of_string "GOOG", 28000
    ]
  in
  (* MM_Low's fair value sits [low_offset_cents] below the anchor and
     MM_High's sits [high_offset_cents] above. The offsets are asymmetric so
     MM_High's bid (at [anchor + high_offset_cents - half_spread]) crosses
     MM_Low's ask (at [anchor + low_offset_cents + half_spread]). *)
  let low_offset_cents = -10 in
  let high_offset_cents = 15 in
  let cycle_period = Time_ns.Span.of_sec 2. in
  let make ~participant ~symbol ~fair_value_cents : Market_maker.Config.t =
    { participant
    ; symbol
    ; fair_value_cents
    ; half_spread_cents = 5
    ; size_per_level = 25
    ; num_levels = 3
    }
  in
  (* Two market makers total, each shared across all symbols — so we open
     exactly one logged-in connection per participant. *)
  let mm_low = Participant.of_string "MM_Low" in
  let mm_high = Participant.of_string "MM_High" in
  let%bind low_conn = connect_as ~where_to_connect mm_low in
  let%bind high_conn = connect_as ~where_to_connect mm_high in
  let configs_for_symbol (symbol, anchor) =
    [ ( low_conn
      , make
          ~participant:mm_low
          ~symbol
          ~fair_value_cents:(anchor + low_offset_cents) )
    ; ( high_conn
      , make
          ~participant:mm_high
          ~symbol
          ~fair_value_cents:(anchor + high_offset_cents) )
    ]
  in
  let configs = List.concat_map symbol_anchors ~f:configs_for_symbol in
  let cycle () =
    Deferred.List.iter ~how:`Sequential configs ~f:(fun (conn, config) ->
      Market_maker.seed_book config conn)
  in
  let%map () = cycle () in
  Clock_ns.every cycle_period (fun () -> don't_wait_for (cycle ()))
;;

let start ~port ~market_maker_behavior =
  let%bind server =
    Exchange_server.start ~symbols:default_symbols ~port ()
  in
  let where_to_connect =
    Tcp.Where_to_connect.of_host_and_port { host = "localhost"; port }
  in
  let%bind () =
    match market_maker_behavior with
    | `Trade_back_and_forth ->
      let%map () =
        print_endline
          "=== Starting two market makers trading back-and-forth ===";
        trade_back_and_forth ~where_to_connect
      in
      print_endline ""
    | `Seed_market_maker ->
      let%map () =
        print_endline "=== Seeding book with market maker orders ===";
        seed_market_maker ~where_to_connect
      in
      print_endline ""
    | `Do_nothing -> Deferred.unit
  in
  print_endline
    [%string
      "JSIP Exchange server listening on port %{Exchange_server.port \
       server#Int}"];
  let symbols =
    List.map default_symbols ~f:Symbol.to_string |> String.concat ~sep:", "
  in
  print_endline [%string "Trading: %{symbols}"];
  Exchange_server.close_finished server
;;

let () =
  Command.async
    ~summary:"JSIP Exchange server"
    (let%map_open.Command port =
       flag "-port" (required int) ~doc:"PORT port to listen on"
     and market_maker_behavior =
       choose_one
         ~if_nothing_chosen:(Default_to `Do_nothing)
         [ flag
             "-seed-market-maker"
             (no_arg_some `Seed_market_maker)
             ~doc:
               " pre-seed the book with market maker orders (mutually \
                exclusive with -trade-back-and-forth)"
         ; flag
             "-trade-back-and-forth"
             (no_arg_some `Trade_back_and_forth)
             ~doc:
               " run two market makers in a loop, generating sustained \
                traffic for the monitor (mutually exclusive with \
                -seed-market-maker)"
         ]
     in
     fun () -> start ~port ~market_maker_behavior)
  |> Command_unix.run
;;
