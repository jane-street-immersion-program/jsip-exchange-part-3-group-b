(** Scaffolding for bot tests. *)

open! Core
open! Async
open Jsip_types
open Jsip_fundamental
open Jsip_bot_runtime
open! Jsip_bots

let aapl = Symbol.of_string "AAPL"
let alice = Participant.of_string "Alice"

let oracle_config ~initial_price_cents =
  Symbol.Map.of_alist_exn
    [ ( aapl
      , { Fundamental_oracle.Config.initial_price_cents
        ; volatility_cents_per_sec = 0.0
        ; mean_reversion_strength = 0.0
        ; tick_interval = Time_ns.Span.of_sec 1.0
        } )
    ]
;;

(* Build a runtime around a bot module with a mock submit/cancel that records
   what the bot does. *)
let make_recording_bot
  (type cfg)
  (bot_module : (module Bot_runtime.Bot with type Config.t = cfg))
  (config : cfg)
  ?(initial_price_cents = 15000)
  ()
  =
  let submitted = ref [] in
  let cancelled = ref [] in
  let submit request =
    submitted := request :: !submitted;
    return (Ok ())
  in
  let cancel order_id =
    cancelled := order_id :: !cancelled;
    return (Ok ())
  in
  let oracle =
    Fundamental_oracle.create (oracle_config ~initial_price_cents) ~seed:42
  in
  let bot =
    Bot_runtime.create
      bot_module
      config
      ~participant:alice
      ~oracle
      ~rng:(Splittable_random.of_int 7)
      ~submit
      ~cancel
      ~tick_interval:(Time_ns.Span.of_sec 1.0)
  in
  bot, submitted, cancelled
;;

let print_submitted (submitted : Order.Request.t list ref) =
  let recent = List.rev !submitted in
  List.iter recent ~f:(fun req ->
    printf
      !"%{Side} %{Symbol} %d@%{Price#dollar} %{Time_in_force}\n"
      req.side
      req.symbol
      (Size.to_int req.size)
      req.price
      req.time_in_force)
;;

(* Smoke test: drive the do-nothing reference bot through one event so the
   runtest target exercises the helpers above. Replace or extend with
   bot-specific tests as concrete strategies are added to [Jsip_bots]. *)
module Inert_bot = struct
  module Config = struct
    type t = unit
  end

  let name = "inert"
  let on_start () _ctx = return ()
  let on_tick () _ctx = return ()
  let on_event () _ctx _event = return ()
end

let spammer_config ~orders_per_tick : Spammer.Config.t =
  { symbols = [ aapl ]
  ; orders_per_tick
  ; size = 10
  ; next_client_order_id = ref 0
  }
;;

(* Like [print_submitted] but also shows the client_order_id, since ID
   uniqueness across ticks is the behavior we most want to see. *)
let print_orders (submitted : Order.Request.t list ref) =
  List.rev !submitted
  |> List.iter ~f:(fun (req : Order.Request.t) ->
    printf
      !"#%{sexp:Client_order_id.t} %{Side} %{Symbol} %d@%{Price#dollar} \
        %{Time_in_force}\n"
      req.client_order_id
      req.side
      req.symbol
      (Size.to_int req.size)
      req.price
      req.time_in_force)
;;

let%expect_test "spammer fires a burst of never-fill orders each tick" =
  let config = spammer_config ~orders_per_tick:3 in
  let bot, submitted, _cancelled =
    make_recording_bot (module Spammer) config ()
  in
  let ctx = Bot_runtime.For_testing.context_of bot in
  (* Two ticks. The second must keep minting fresh IDs (3, 4, 5), not reset
     to 0 — that's the persistent-counter fix, and it's what keeps the
     exchange's duplicate-ID path from rejecting the burst. *)
  let%bind () = Spammer.on_tick config ctx in
  let%bind () = Spammer.on_tick config ctx in
  print_orders submitted;
  [%expect
    {|
    #0 BUY AAPL 10@$0.01 DAY
    #1 SELL AAPL 10@$10000.00 DAY
    #2 BUY AAPL 10@$0.01 DAY
    #3 BUY AAPL 10@$0.01 DAY
    #4 SELL AAPL 10@$10000.00 DAY
    #5 BUY AAPL 10@$0.01 DAY
    |}];
  return ()
;;

(* The pressure the spammer exerts is its burst magnitude: one tick must
   produce exactly [orders_per_tick] submissions, so the scenario's intensity
   knob maps directly to load. A spammer that fired once per tick would pass
   a "did it submit?" test but exert almost no pressure — this pins the
   count. *)
let%expect_test "burst size equals orders_per_tick across intensities" =
  let%bind () =
    Deferred.List.iter ~how:`Sequential [ 0; 1; 5; 20 ] ~f:(fun n ->
      let config = spammer_config ~orders_per_tick:n in
      let bot, submitted, _cancelled =
        make_recording_bot (module Spammer) config ()
      in
      let ctx = Bot_runtime.For_testing.context_of bot in
      let%map () = Spammer.on_tick config ctx in
      printf
        "orders_per_tick=%d -> %d submitted\n"
        n
        (List.length !submitted))
  in
  [%expect
    {|
    orders_per_tick=0 -> 0 submitted
    orders_per_tick=1 -> 1 submitted
    orders_per_tick=5 -> 5 submitted
    orders_per_tick=20 -> 20 submitted
    |}];
  return ()
;;

(* Every order must carry the bot's own identity, since the exchange scopes
   duplicate-ID detection per participant and routes fills back by it. This
   guards the [participant = Context.participant] wiring in [on_tick]. *)
let%expect_test "every order carries the bot's participant" =
  let config = spammer_config ~orders_per_tick:3 in
  let bot, submitted, _cancelled =
    make_recording_bot (module Spammer) config ()
  in
  let ctx = Bot_runtime.For_testing.context_of bot in
  let%bind () = Spammer.on_tick config ctx in
  List.rev !submitted
  |> List.iter ~f:(fun (req : Order.Request.t) ->
    printf !"%{sexp: Participant.t}\n" req.participant);
  [%expect {|
    Alice
    Alice
    Alice
    |}];
  return ()
;;

(* With multiple symbols configured, a single tick must spread its orders
   across them round-robin so the load hits every book, not just the first. *)
let%expect_test "burst round-robins across configured symbols" =
  let config : Spammer.Config.t =
    { symbols = [ aapl; Symbol.of_string "MSFT" ]
    ; orders_per_tick = 5
    ; size = 10
    ; next_client_order_id = ref 0
    }
  in
  let bot, submitted, _cancelled =
    make_recording_bot (module Spammer) config ()
  in
  let ctx = Bot_runtime.For_testing.context_of bot in
  let%bind () = Spammer.on_tick config ctx in
  List.rev !submitted
  |> List.iter ~f:(fun (req : Order.Request.t) ->
    printf !"%{Symbol}\n" req.symbol);
  [%expect {|
    AAPL
    MSFT
    AAPL
    MSFT
    AAPL
    |}];
  return ()
;;

(* Drive the filler through a few ticks and assert independently-computable
   properties of what it submits -- not that a specific request object came
   back (that would be tautological). We check the count, that everything is
   a resting [Day] order, that every order is priced clear of the fundamental
   (so it never fills), and that every [client_order_id] is fresh (so none
   get rejected as duplicates). *)
let%expect_test "book_filler: piles fresh, non-marketable Day orders" =
  let fair_value_cents = 15000 in
  let orders_per_tick = 5 in
  let ticks = 3 in
  let config =
    Book_filler.Config.create
      ~symbols:[ aapl ]
      ~orders_per_tick
      ~size:1
      ~min_offset_cents:100
      ~max_offset_cents:2000
      ()
  in
  let bot, submitted, _cancelled =
    make_recording_bot
      (module Book_filler)
      config
      ~initial_price_cents:fair_value_cents
      ()
  in
  let ctx = Bot_runtime.For_testing.context_of bot in
  let%bind () =
    Deferred.List.iter
      ~how:`Sequential
      (List.init ticks ~f:Fn.id)
      ~f:(fun _ -> Book_filler.on_tick config ctx)
  in
  let requests = List.rev !submitted in
  let fair = Price.of_int_cents fair_value_cents in
  let non_marketable (req : Order.Request.t) =
    match req.side with
    | Buy -> Price.( < ) req.price fair
    | Sell -> Price.( > ) req.price fair
  in
  let ids = List.map requests ~f:(fun req -> req.client_order_id) in
  printf "submitted: %d\n" (List.length requests);
  printf
    "all Day: %b\n"
    (List.for_all requests ~f:(fun req ->
       Time_in_force.equal req.time_in_force Day));
  printf "all non-marketable: %b\n" (List.for_all requests ~f:non_marketable);
  printf
    "all ids distinct: %b\n"
    (not (List.contains_dup ids ~compare:Client_order_id.compare));
  [%expect
    {|
    submitted: 15
    all Day: true
    all non-marketable: true
    all ids distinct: true
    |}];
  return ()
;;

(* The noise trader should quote around the fundamental on both sides. Assert
   the independently-computable envelope: a fixed count, all resting [Day]
   orders, every price within [jitter_cents] of fair, and fresh IDs. *)
let%expect_test "noise_trader: quotes fresh Day orders around the touch" =
  let fair_value_cents = 15000 in
  let jitter_cents = 40 in
  let orders_per_tick = 6 in
  let ticks = 4 in
  let config =
    Noise_trader.Config.create
      ~symbols:[ aapl ]
      ~orders_per_tick
      ~jitter_cents
      ~size:10
      ()
  in
  let bot, submitted, _cancelled =
    make_recording_bot
      (module Noise_trader)
      config
      ~initial_price_cents:fair_value_cents
      ()
  in
  let ctx = Bot_runtime.For_testing.context_of bot in
  let%bind () =
    Deferred.List.iter
      ~how:`Sequential
      (List.init ticks ~f:Fn.id)
      ~f:(fun _ -> Noise_trader.on_tick config ctx)
  in
  let requests = List.rev !submitted in
  let low = Price.of_int_cents (fair_value_cents - jitter_cents) in
  let high = Price.of_int_cents (fair_value_cents + jitter_cents) in
  let within_band (req : Order.Request.t) =
    Price.( <= ) low req.price && Price.( <= ) req.price high
  in
  let ids = List.map requests ~f:(fun req -> req.client_order_id) in
  printf "submitted: %d\n" (List.length requests);
  printf
    "all Day: %b\n"
    (List.for_all requests ~f:(fun req ->
       Time_in_force.equal req.time_in_force Day));
  printf
    "all within jitter band: %b\n"
    (List.for_all requests ~f:within_band);
  printf
    "all ids distinct: %b\n"
    (not (List.contains_dup ids ~compare:Client_order_id.compare));
  [%expect
    {|
    submitted: 24
    all Day: true
    all within jitter band: true
    all ids distinct: true
    |}];
  return ()
;;

(* The slow consumer's whole behavior is what it {e doesn't} do: it never
   submits, and its [on_event] paces (or refuses) reads. We assert it submits
   nothing across ticks, that [Never] yields an event handler that never
   completes (so the runtime's [Pipe.iter] would stall), and that a finite
   delay does complete. *)
let%expect_test "slow_consumer: submits nothing and throttles reads" =
  let sample_event : Exchange_event.t =
    Order_accept
      { order_id = Order_id.For_testing.of_int 1
      ; request =
          { client_order_id = Client_order_id.of_int 1
          ; symbol = aapl
          ; participant = alice
          ; side = Buy
          ; price = Price.of_int_cents 15000
          ; size = Size.of_int 10
          ; time_in_force = Day
          }
      }
  in
  let never_config =
    Slow_consumer.Config.create
      ~read_behavior:Slow_consumer.Read_behavior.Never
  in
  let bot, submitted, cancelled =
    make_recording_bot (module Slow_consumer) never_config ()
  in
  let ctx = Bot_runtime.For_testing.context_of bot in
  let%bind () = Slow_consumer.on_tick never_config ctx in
  let%bind () = Slow_consumer.on_tick never_config ctx in
  printf "submitted: %d\n" (List.length !submitted);
  printf "cancelled: %d\n" (List.length !cancelled);
  printf
    "Never handler determined: %b\n"
    (Deferred.is_determined
       (Slow_consumer.on_event never_config ctx sample_event));
  let delay_config =
    Slow_consumer.Config.create
      ~read_behavior:
        (Slow_consumer.Read_behavior.Delay_per_event Time_ns.Span.zero)
  in
  let%bind () = Slow_consumer.on_event delay_config ctx sample_event in
  printf "zero-delay handler completed: true\n";
  [%expect
    {|
    submitted: 0
    cancelled: 0
    Never handler determined: false
    zero-delay handler completed: true
    |}];
  return ()
;;

(* Drive the cancel storm's [on_tick] directly and assert the two properties
   that actually matter for the pathology: every submit gets a *fresh*
   [client_order_id] (so duplicate detection never blocks the storm), and
   each submitted order is cancelled. The expected IDs are computed
   independently of the bot ([1;2;3] then [4;5;6] across two ticks), so this
   is not a restatement of the implementation. *)
let%expect_test "cancel storm allocates fresh ids and cancels each order" =
  let config =
    Cancel_storm.Config.create
      ~symbols:[ aapl ]
      ~cycles_per_tick:3
      ~max_in_flight:1
      ~size:100
      ~passive_offset_cents:100
      ()
  in
  let bot, submitted, cancelled =
    make_recording_bot (module Cancel_storm) config ()
  in
  let ctx = Bot_runtime.For_testing.context_of bot in
  let print_ids () =
    let submitted_ids =
      List.rev_map !submitted ~f:(fun (req : Order.Request.t) ->
        Client_order_id.to_int req.client_order_id)
    in
    let cancelled_ids = List.rev_map !cancelled ~f:Client_order_id.to_int in
    print_s [%message (submitted_ids : int list) (cancelled_ids : int list)]
  in
  let%bind () = Cancel_storm.on_tick config ctx in
  print_ids ();
  [%expect {| ((submitted_ids (1 2 3)) (cancelled_ids (1 2 3))) |}];
  (* A second tick continues the counter — no ID is ever reused. *)
  let%bind () = Cancel_storm.on_tick config ctx in
  print_ids ();
  [%expect
    {| ((submitted_ids (1 2 3 4 5 6)) (cancelled_ids (1 2 3 4 5 6))) |}];
  return ()
;;

(* The test above pins [max_in_flight = 1], the degenerate sequential case,
   and asserts invariants (fresh ids, all cancelled) that hold at *any*
   concurrency -- so it can't tell whether the knob works. This test actually
   observes the bound: a gated [submit] freezes the storm mid-flight, so we
   can read how many cycles the runtime let run at once. It must be exactly
   [max_in_flight]. If the knob were broken (ignored, or wired to `Parallel
   or `Sequential) the peak would differ and this fails. After releasing the
   gate we also confirm the concurrent path still keeps ids fresh and cancels
   every order. *)
let%expect_test "cancel storm bounds in-flight cycles to max_in_flight" =
  let max_in_flight = 4 in
  let cycles_per_tick = 20 in
  let config =
    Cancel_storm.Config.create
      ~symbols:[ aapl ]
      ~cycles_per_tick
      ~max_in_flight
      ~size:100
      ~passive_offset_cents:100
      ()
  in
  let gate = Ivar.create () in
  let in_flight = ref 0 in
  let peak = ref 0 in
  let submitted = ref [] in
  let cancelled = ref [] in
  let submit (request : Order.Request.t) =
    submitted := request.client_order_id :: !submitted;
    incr in_flight;
    peak := Int.max !peak !in_flight;
    let%map () = Ivar.read gate in
    decr in_flight;
    Ok ()
  in
  let cancel client_order_id =
    cancelled := client_order_id :: !cancelled;
    return (Ok ())
  in
  let oracle =
    Fundamental_oracle.create
      (oracle_config ~initial_price_cents:15000)
      ~seed:42
  in
  let bot =
    Bot_runtime.create
      (module Cancel_storm)
      config
      ~participant:alice
      ~oracle
      ~rng:(Splittable_random.of_int 7)
      ~submit
      ~cancel
      ~tick_interval:(Time_ns.Span.of_sec 1.0)
  in
  let ctx = Bot_runtime.For_testing.context_of bot in
  (* Kick off the tick but do not await it: submits pile up against the gate. *)
  let tick = Cancel_storm.on_tick config ctx in
  let%bind () = Scheduler.yield_until_no_jobs_remain () in
  printf "peak while frozen: %d (cap %d)\n" !peak max_in_flight;
  Ivar.fill_exn gate ();
  let%bind () = tick in
  printf "submitted: %d\n" (List.length !submitted);
  printf "cancelled: %d\n" (List.length !cancelled);
  printf
    "all ids distinct: %b\n"
    (not (List.contains_dup !submitted ~compare:Client_order_id.compare));
  [%expect
    {|
    peak while frozen: 4 (cap 4)
    submitted: 20
    cancelled: 20
    all ids distinct: true
    |}];
  return ()
;;

let%expect_test "make_recording_bot wires up a runnable bot" =
  let bot, submitted, _cancelled =
    make_recording_bot (module Inert_bot) () ()
  in
  let%bind () =
    Bot_runtime.feed_event
      bot
      (Order_accept
         { order_id = Order_id.For_testing.of_int 1
         ; request =
             { client_order_id = Client_order_id.of_int 1
             ; symbol = aapl
             ; participant = alice
             ; side = Buy
             ; price = Price.of_int_cents 15000
             ; size = Size.of_int 10
             ; time_in_force = Day
             }
         })
  in
  print_submitted submitted;
  [%expect {| |}];
  return ()
;;
