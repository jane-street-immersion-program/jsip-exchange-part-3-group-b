open! Core
open! Async
open Jsip_types
module Bot_runtime = Jsip_bot_runtime.Bot_runtime

(** A pathological bot that submits a large burst of orders on every tick.

    Unlike a real trading strategy, the spammer has no view on price and no
    interest in trading. Its entire job is to generate load. On each tick it
    fires [orders_per_tick] submissions in parallel, each a resting [Day]
    order priced far outside the market so it never fills — the spammer is a
    pure load generator, not a counterparty. The resources this stresses:

    - the request queue and the gateway dispatcher's per-event work (every
      order is one RPC the server must decode, route, and match);
    - the order book's memory, since every order rests and never leaves;
    - the bandwidth of every subscriber pipe (each accepted order fans out as
      an event to all market-data / audit-log subscribers).

    Because its orders never fill, the spammer needs no counterparty; the
    {!Order_spam} scenario runs it solo. *)

module Config = struct
  type t =
    { symbols : Symbol.t list
    (** Symbols to spam; each tick's burst round-robins across them. Must be
        non-empty — [on_start] rejects an empty list. *)
    ; orders_per_tick : int
    (** How many orders to fire in a single [on_tick]. This is the main
        intensity knob the scenario tunes per instance. *)
    ; size : int (** Shares per order. *)
    ; next_client_order_id : int ref
    (** Mutable counter (not a tuning knob): [on_tick] reads and increments
        it to mint a unique [client_order_id] per order, so submissions never
        collide across ticks. Each spammer instance gets its own. *)
    }
  [@@deriving sexp_of]
end

let name = "spammer"

(* Prices deliberately far outside any real market so these orders never
   cross resting liquidity: a bid this low and an ask this high always rest
   instead of filling, keeping the spammer a pure load generator. Tune if
   your scenario's fundamental sits near these values. *)
let never_marketable_bid_cents = 1
let never_marketable_ask_cents = 1_000_000

(* The only startup work is a precondition check: [on_tick] round-robins over
   [config.symbols], so an empty list would divide by zero mid-burst. Fail
   loudly here, when the scenario first boots the bot, rather than there. *)
let on_start (config : Config.t) (_context : Bot_runtime.Context.t) =
  if List.is_empty config.symbols
  then
    raise_s
      [%message
        "Spammer.on_start: [symbols] must be non-empty" (name : string)];
  Deferred.unit
;;

(* The spammer is fire-and-forget *)
let on_event
  (_config : Config.t)
  (_context : Bot_runtime.Context.t)
  (_event : Exchange_event.t)
  =
  Deferred.unit
;;

(* On each tick, fire [config.orders_per_tick] resting orders in parallel to
   pile pressure on the request queue and the books. Each order gets a unique
   id from the persistent counter and a never-marketable price, so it rests
   forever instead of filling. *)
let on_tick (config : Config.t) (context : Bot_runtime.Context.t) =
  (* [on_start] guarantees [symbols] is non-empty. An array gives O(1)
     indexing for the per-order round-robin below. *)
  let symbols = Array.of_list config.symbols in
  let num_symbols = Array.length symbols in
  Deferred.List.iter
    ~how:`Parallel
    (List.init config.orders_per_tick ~f:Fn.id)
    ~f:(fun i ->
      (* Mint a unique id from the persistent counter, not from [i] (which
         resets every tick and would collide). *)
      let client_order_id =
        let id = !(config.next_client_order_id) in
        incr config.next_client_order_id;
        Client_order_id.of_int id
      in
      (* Round-robin across the symbols so the load hits every book, not just
         the first. *)
      let symbol = symbols.(i mod num_symbols) in
      let side = if i mod 2 = 0 then Side.Buy else Side.Sell in
      let price =
        match side with
        | Side.Buy -> Price.of_int_cents never_marketable_bid_cents
        | Side.Sell -> Price.of_int_cents never_marketable_ask_cents
      in
      let request : Order.Request.t =
        { client_order_id
        ; symbol
        ; participant = Bot_runtime.Context.participant context
        ; side
        ; price
        ; size = Size.of_int config.size
        ; time_in_force = Time_in_force.Day
        }
      in
      match%map Bot_runtime.Context.submit context request with
      | Ok () -> ()
      | Error error ->
        [%log.error "spammer: submit failed" (error : Error.t)])
;;
