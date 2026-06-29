open! Core
open! Async
open Jsip_types
module Fundamental_oracle = Jsip_fundamental.Fundamental_oracle

module Context = struct
  type t =
    { participant : Participant.t
    ; oracle : Fundamental_oracle.t
    ; rng : Splittable_random.t
    ; dispatch_submit : Order.Request.t -> unit Deferred.Or_error.t
    ; dispatch_cancel : Client_order_id.t -> unit Deferred.Or_error.t
    }

  let participant t = t.participant
  let fundamental t symbol = Fundamental_oracle.price t.oracle symbol
  let random t = t.rng
  let submit t request = t.dispatch_submit request
  let cancel t order_id = t.dispatch_cancel order_id
end

module type Bot = sig
  module Config : sig
    type t
  end

  val name : string

  (** Called exactly once, before the tick loop starts and before any events
      are delivered. Use this for one-time setup that needs to happen on the
      same scheduler as [on_tick] / [on_event] — e.g., seeding an initial
      ladder of orders. *)
  val on_start : Config.t -> Context.t -> unit Deferred.t

  val on_tick : Config.t -> Context.t -> unit Deferred.t
  val on_event : Config.t -> Context.t -> Exchange_event.t -> unit Deferred.t
end

type packed_bot =
  | Packed :
      { bot : (module Bot with type Config.t = 'cfg)
      ; config : 'cfg
      }
      -> packed_bot

type t =
  { context : Context.t
  ; bot : packed_bot
  ; tick_interval : Time_ns.Span.t
  }

let create
  (type cfg)
  (bot_module : (module Bot with type Config.t = cfg))
  (config : cfg)
  ~participant
  ~oracle
  ~rng
  ~submit
  ~cancel
  ~tick_interval
  =
  let context : Context.t =
    { participant
    ; oracle
    ; rng
    ; dispatch_submit = submit
    ; dispatch_cancel = cancel
    }
  in
  { context; bot = Packed { bot = bot_module; config }; tick_interval }
;;

let participant t = t.context.participant

let feed_event t event =
  let (Packed { bot = (module B); config }) = t.bot in
  B.on_event config t.context event
;;

let start t =
  let (Packed { bot = (module B); config }) = t.bot in
  let%bind () = B.on_start config t.context in
  let rec loop () =
    let%bind () = Clock_ns.after t.tick_interval in
    let%bind () = B.on_tick config t.context in
    loop ()
  in
  loop ()
;;

module For_testing = struct
  let context_of t = t.context
end
