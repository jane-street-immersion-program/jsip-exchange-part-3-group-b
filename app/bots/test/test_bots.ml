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
      ; participant = alice
      ; request =
          { client_order_id = Client_order_id.of_int 1
          ; symbol = aapl
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

let%expect_test "make_recording_bot wires up a runnable bot" =
  let bot, submitted, _cancelled =
    make_recording_bot (module Inert_bot) () ()
  in
  let%bind () =
    Bot_runtime.feed_event
      bot
      (Order_accept
         { order_id = Order_id.For_testing.of_int 1
         ; participant = alice
         ; request =
             { client_order_id = Client_order_id.of_int 1
             ; symbol = aapl
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
