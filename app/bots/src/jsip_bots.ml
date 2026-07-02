open! Core

(* Registry of the group's pathological bots. Each bot lives in its own file
   under this directory and is re-exported here so the scenarios can name it
   as e.g. [Jsip_bots.Spammer]. Add a [module Foo = Foo] line as each bot
   lands. *)

module Spammer = Spammer
