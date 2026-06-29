open! Core
open! Async
open Jsip_types

type t =
  { participant : Participant.t
  ; reader : Exchange_event.t Pipe.Reader.t
  ; writer : Exchange_event.t Pipe.Writer.t
  }

let create participant =
  let reader, writer = Pipe.create () in
  { participant; reader; writer }
;;

let participant t = t.participant
let reader t = t.reader
let push t event = Pipe.write_without_pushback_if_open t.writer event
let close t = Pipe.close t.writer
let is_closed t = Pipe.is_closed t.writer
