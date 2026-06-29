open! Core
open Jsip_types
open Expect_test_helpers_core

let%expect_test "of_string: empty string raises" =
  require_does_raise (fun () -> Symbol.of_string "");
  [%expect {| "Symbol.of_string: symbol must be non-empty" |}]
;;
