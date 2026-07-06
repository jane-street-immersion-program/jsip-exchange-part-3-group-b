open! Core
open! Async
open Jsip_types
module Context = Jsip_bot_runtime.Bot_runtime.Context

module Read_behavior = struct
  type t =
    | Never
    | Delay_per_event of Time_ns.Span.t
  [@@deriving sexp_of]
end

module Config = struct
  type t = { read_behavior : Read_behavior.t } [@@deriving sexp_of]

  let create ~read_behavior = { read_behavior }
end

let name = "slow-consumer"
let on_start (_config : Config.t) (_ctx : Context.t) = return ()

(* A slow consumer submits nothing. *)
let on_tick (_config : Config.t) (_ctx : Context.t) = return ()

(* The whole pathology lives here. The runtime drains this bot's feeds with
   [Pipe.iter pipe ~f:(feed_event bot)], and [Pipe.iter] will not pull the
   next element until the deferred returned by [f] -- ultimately this
   [on_event] -- is determined. So delaying (or never determining) here
   throttles how fast the bot reads its market-data pipe.

   Reading slower than events arrive backs the pipe up. The exchange writes
   to each subscriber's pipe with [Pipe.write_without_pushback_if_open] and
   sets no size budget on it (see [Dispatcher.push_market_data]), so the
   exchange-side buffer for this subscriber grows without bound while we
   dawdle -- exactly the resource this bot targets. *)
let on_event
  (config : Config.t)
  (_ctx : Context.t)
  (_event : Exchange_event.t)
  =
  match config.read_behavior with
  | Never -> Deferred.never ()
  | Delay_per_event span -> Clock_ns.after span
;;
