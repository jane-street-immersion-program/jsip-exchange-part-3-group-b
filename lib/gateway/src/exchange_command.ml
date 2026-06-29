open! Core
open Jsip_types

type t =
  | Login of { name : string }
  | Submit of Order.Request.t
  | Cancel of { client_order_id : Client_order_id.t }
  | Book of Symbol.t
  | Subscribe of Symbol.t
[@@deriving sexp_of]

let to_string t = sexp_of_t t |> Sexp.to_string

module Verb = struct
  type t =
    | Login
    | Buy
    | Sell
    | Cancel
    | Book
    | Subscribe
  [@@deriving string ~case_insensitive ~capitalize:"SCREAMING_SNAKE_CASE"]
end

let parse_symbol tokens =
  match tokens with
  | [] -> Or_error.error_string "missing required symbol argument"
  | symbol :: [] ->
    (try Ok (Symbol.of_string symbol) with
     | exn ->
       let exn_str = Exn.to_string exn in
       Or_error.error_string
         [%string "invalid symbol: %{symbol}\nexception: %{exn_str}"])
  | _ :: rest ->
    let trailing = String.concat ~sep:" " rest in
    Or_error.error_string
      [%string "unexpected trailing arguments: %{trailing}"]
;;

let parse_login tokens =
  match tokens with
  | [ name ] -> Ok (Login { name })
  | _ -> Or_error.error_string "expected: LOGIN <participant_name>"
;;

let parse_client_order_id client_order_id_str =
  match Int.of_string_opt client_order_id_str with
  | Some n when n >= 0 -> Ok (Client_order_id.of_int n)
  | Some _ -> Or_error.error_string "client order id must be non-negative"
  | None ->
    Or_error.error_string
      [%string "invalid client order id: %{client_order_id_str}"]
;;

let parse_order_request side tokens =
  let open Or_error.Let_syntax in
  match tokens with
  | client_order_id_str :: symbol_str :: size_str :: price_str :: rest ->
    let%bind client_order_id = parse_client_order_id client_order_id_str in
    let%bind size =
      match Int.of_string_opt size_str with
      | Some n when n > 0 -> Ok n
      | Some _ -> Or_error.error_string "size must be positive"
      | None -> Or_error.error_string [%string "invalid size: %{size_str}"]
    in
    let%bind price =
      try Ok (Price.of_string price_str) with
      | exn ->
        let exn_str = Exn.to_string exn in
        Or_error.error_string
          [%string "invalid price: %{price_str}\nexception: %{exn_str}"]
    in
    let%bind symbol =
      try Ok (Symbol.of_string symbol_str) with
      | exn ->
        let exn_str = Exn.to_string exn in
        Or_error.error_string
          [%string "invalid symbol: %{symbol_str}\nexception: %{exn_str}"]
    in
    let%bind time_in_force =
      match rest with
      | [] -> Ok Time_in_force.Day
      | [ tif_str ] ->
        (try Ok (Time_in_force.of_string tif_str) with
         | _ ->
           let supported =
             Time_in_force.all
             |> List.map ~f:Time_in_force.to_string
             |> String.concat ~sep:"|"
           in
           Or_error.error_string
             [%string
               "unknown time-in-force: %{tif_str} (expected [%{supported}])"])
      | _ ->
        let trailing = String.concat ~sep:" " rest in
        Or_error.error_string
          [%string "unexpected trailing arguments: %{trailing}"]
    in
    Ok
      (Submit
         { client_order_id
         ; symbol
         ; side
         ; price
         ; size = Size.of_int size
         ; time_in_force
         })
  | _ ->
    Or_error.error_string
      [%string
        "expected: BUY|SELL <client_id> <symbol> <size> <price> \
         [%{Time_in_force.all_str}]"]
;;

let parse_cancel tokens =
  let open Or_error.Let_syntax in
  match tokens with
  | [ client_order_id_str ] ->
    let%map client_order_id = parse_client_order_id client_order_id_str in
    Cancel { client_order_id }
  | _ -> Or_error.error_string "expected: CANCEL <client_order_id>"
;;

let parse line : t Or_error.t =
  let open Or_error.Let_syntax in
  let line = String.strip line in
  if String.is_empty line
  then Or_error.error_string "empty command"
  else (
    let parts =
      String.split line ~on:' ' |> List.filter ~f:(Fn.non String.is_empty)
    in
    let result : t Or_error.t =
      match parts with
      | verb :: rest ->
        (match Verb.of_string verb with
         | Verb.Login -> parse_login rest
         | Book ->
           let%map symbol = parse_symbol rest in
           (Book symbol : t)
         | Subscribe ->
           let%map symbol = parse_symbol rest in
           (Subscribe symbol : t)
         | Buy -> parse_order_request Side.Buy rest
         | Sell -> parse_order_request Sell rest
         | Cancel -> parse_cancel rest
         | exception _ ->
           Or_error.error_string [%string "unrecognized command: %{verb}"])
      | _ -> Or_error.error_string "unrecognized command"
    in
    result)
;;
