## Naming
- Use snake_case, not camelCase
- Functions that can raise should end with `_exn`
- Boolean functions should be named as predicates (e.g., `is_valid`, `can_process`)
- Functions that acquire/release resources should start with `with_`, be higher-order
  (take a callback), and use `~f` or an anonymous argument for the callback.

## Acquiring Resources With `with_`
- When defining helpers that acquire and release resources, prefer `with_`-style
  functions over separate create/cleanup pairs.
- When consuming existing APIs, prefer the `with_` helper over paired create/cleanup
  functions when both exist.
```ocaml
(* Good - cleanup is scoped to the callback, even on exceptions *)
In_channel.with_file path ~f:(fun in_channel ->
  ...
)

(* Bad - manual open/close that leaks the channel if the body raises *)
let in_channel = In_channel.create path in
let result =
  ...
in
In_channel.close in_channel;
result
```

## Documentation
- Non-trivial modules should usually have a module-level comment in the `.mli` when it
  adds useful context
```ocaml
(* Good - in .mli file for a module whose role is not obvious *)
(** [User] represents a user account in the system.
    It handles authentication and profile management. *)

type t

(* Also fine - tiny obvious modules do not need boilerplate comments *)
open Core

val command : Command.t
```
- Avoid comments that add no useful information to the type and function name
```ocaml
(* Good - no comment needed, the signature is self-explanatory *)
val length : t -> int

(* Bad - comment adds nothing *)
(** [length t] returns the length of [t]. *)
val length : t -> int

(* Good - comment adds useful information *)
(** Returns the length in bytes, not characters. *)
val length : t -> int
```
- Use proper odoc formatting for doc comments, not markdown
```ocaml
(* Good - odoc syntax *)
(** [find t ~key] returns [Some value] if [key] exists, [None] otherwise.
    @raise Invalid_argument if [key] is empty. *)

(* Bad - markdown syntax *)
(** `find t ~key` returns `Some value` if `key` exists, `None` otherwise.
    **Raises**: Invalid_argument if `key` is empty. *)
```

## Error Handling
- Prefer explicit error types (Option, Or_error) over exceptions in interfaces
```ocaml
(* Good *)
val find : t -> key:string -> value option
val parse : string -> t Or_error.t

(* Bad *)
val find_exn : t -> key:string -> value
val parse : string -> t  (* raises on invalid input *)
```
- Include helpful context with errors using [%message]
```ocaml
(* Good *)
Or_error.error_s [%message "Failed to parse config" (filename : string) (line : int)]

(* Bad *)
Or_error.error_string "parse error"
```
- Validate human-constructed inputs
- Avoid redundant validation; don't re-check invariants that are already guaranteed by types or prior validation
```ocaml
(* Good - trust the type system *)
let process (id : User_id.t) = ...

(* Bad - redundant check when User_id.t already guarantees validity *)
let process (id : User_id.t) =
  if not (User_id.is_valid id) then failwith "invalid id";
  ...
```
- Avoid over-defensive programming; trust that callers and callees uphold their contracts
```ocaml
(* Good - trust the contract *)
let get_first list = List.hd_exn list  (* caller guarantees non-empty *)

(* Bad - over-defensive *)
let get_first list =
  match list with
  | [] -> failwith "impossible: list should never be empty"
  | x :: _ -> x
```

## Code Style
- Use [%string] over sprintf for string construction, especially for printing and logging
```ocaml
(* Good *)
[%string "User %{name} has %{count#Int} items"]

(* Bad *)
sprintf "User %s has %d items" name count
```
- Prefer match over complex Option helper functions for readability
```ocaml
(* Good *)
match find_user id with
| Some user -> process user
| None -> default_value

(* Bad - harder to read *)
Option.value_map (find_user id) ~default:default_value ~f:process
```
- Different teams have different conventions around matching on booleans. Follow the
  surrounding code when there is a clear local pattern. In the absence of one, prefer
  `match` once either arm becomes multi-line: it lets you put the short case first and
  is easier to extend safely. For short single-expression branches, either style can be
  fine.
```ocaml
(* Good *)
match List.is_empty items with
| false -> List.rev items
| true ->
  default_items ()
  |> List.filter ~f:is_valid
  |> List.dedup_and_sort ~compare:Int.compare

(* Also fine when short and local style prefers it *)
if keep_weight_sum then weight_agg :: aggs else aggs

(* Bad *)
if List.is_empty items
then
  default_items ()
  |> List.filter ~f:is_valid
  |> List.dedup_and_sort ~compare:Int.compare
else List.rev items
```
- Use `Staged.t` as guardrails for partial application
```ocaml
(* Good - makes it clear the function is meant to be partially applied *)
val create_matcher : pattern:string -> (string -> bool) Staged.t

(* Usage *)
let matches = unstage (create_matcher ~pattern:"foo") in
List.filter strings ~f:matches
```
- Prefer `don't_wait_for` to `upon` in async code
```ocaml
(* Good *)
don't_wait_for (
  let%bind () = do_something () in
  do_something_else ()
)

(* Bad *)
upon (do_something ()) (fun () ->
  upon (do_something_else ()) (fun () -> ()))
```
- Prefer Async modules (`Reader`, `Writer`, Async `Unix`, etc.) over blocking `In_channel` / `Out_channel` in Async code
- Edits are targeted and small, large changes are not made unless necessary

## Interfaces
- When a module has a primary type `t`, keep the exposed definitions focused on that type.
```ocaml
(* Good - all functions relate to User.t *)
module User : sig
  type t
  val create : name:string -> t
  val name : t -> string
end

(* Bad - unrelated helper function in module *)
module User : sig
  type t
  val create : name:string -> t
  val string_to_int : string -> int  (* doesn't involve t *)
end
```
- Order arguments: optional, t, positional, labeled
```ocaml
(* Good *)
val find : ?default:v -> t -> key -> compare:(v -> v -> int) -> v

(* Bad *)
val find : t -> ?default:v -> compare:(v -> v -> int) -> key -> v
```
- Prefer abstract types unless the type has no invariants
```ocaml
(* Good - abstract type hides implementation and enforces invariants *)
module Positive_int : sig
  type t
  val create : int -> t option
  val to_int : t -> int
end

(* Bad - exposed type allows invalid values *)
module Positive_int : sig
  type t = int
  val create : int -> t option
end
```
- Use signature includes (e.g., `include Comparable.S`) over hand-written interfaces
```ocaml
(* Good *)
module User_id : sig
  type t
  include Comparable.S with type t := t
  include Hashable.S with type t := t
end

(* Bad - hand-written *)
module User_id : sig
  type t
  val compare : t -> t -> int
  val ( < ) : t -> t -> bool
  val ( > ) : t -> t -> bool
  (* ... many more ... *)
end
```

## Managing Namespaces
- Name the inner module `T` and apply the functor to it.
```ocaml
module User_id = struct
  module T = struct
    type t = int [@@deriving sexp, compare]
  end
  include T
  include Comparable.Make (T)
end
```
- Avoid introducing new infix operators
```ocaml
(* Good *)
let result = List.concat_map items ~f:process

(* Bad - custom operator *)
let ( <*> ) = List.concat_map
let result = items <*> process
```
- Avoid ad hoc module wrappers
- Prefer a consistent style with imports, with regards to per-file vs per-library imports

## Avoiding Error-Prone Idioms
- Avoid polymorphic compare; use ppx_compare instead
```ocaml
(* Good *)
type t = { x : int; y : int } [@@deriving compare]
let equal a b = [%compare.equal: t] a b

(* Bad *)
let equal a b = a = b
let compare a b = Stdlib.compare a b
```
- Heed return values; don't ignore important results
```ocaml
(* Good *)
let (_ : [ `Ok | `Duplicate ]) = Hashtbl.add tbl ~key ~data in
...

(* Bad - ignoring whether add succeeded *)
Hashtbl.add tbl ~key ~data;
...
```
- Be careful with `when` clauses; only use for simple conditions
```ocaml
(* Good - simple condition *)
match x with
| Some n when n > 0 -> positive n
| Some n -> non_positive n
| None -> handle_none ()

(* Bad - complex condition in when clause *)
match x with
| Some n when n > 0 && is_valid n && check_database n -> ...
| ...
```

## Monads
- Avoid changing the currently open `Let_syntax` module within one scope
```ocaml
(* Good - consistent Let_syntax *)
let%bind.Deferred x = fetch () in
let%bind.Deferred y = process x in
return y

(* Bad - mixing Let_syntax modules *)
let%bind.Deferred x = fetch () in
let%bind.Option y = find x in  (* switches to Option *)
...
```
- Don't use a monad if you do not actually need monadic behavior
```ocaml
(* Good - no monad needed *)
let result = process (get_value ()) in
result

(* Bad - unnecessary Deferred *)
let%bind x = return (get_value ()) in
let%bind y = return (process x) in
return y
```
- Separate expressions that evaluate to unit from `return`
```ocaml
(* Good *)
let%bind () = Log.info "Starting" in
let%bind result = do_work () in
let%bind () = Log.info "Done" in
return result

(* Bad *)
let%bind result = do_work () in
Log.info "Done";  (* unit expression mixed with return *)
return result
```

## Stability
- Derive `stable_witness` on stable types
```ocaml
(* Good *)
module Stable = struct
  module V1 = struct
    type t = { x : int } [@@deriving bin_io, sexp, stable_witness]
  end
end
```
- All stable types should have a stable bin digest test
```ocaml
(* Good - in test file *)
let%expect_test "stable bin digest" =
  print_endline [%bin_digest: Stable.V1.t];
  [%expect {| d41d8cd98f00b204e9800998ecf8427e |}]
```
- Put `Stable` modules at the top of the file, before `open! Core`
```ocaml
(* Good *)
module Stable = struct
  module V1 = struct
    type t = int [@@deriving bin_io, sexp, stable_witness]
  end
end

open! Core

(* Bad *)
open! Core

module Stable = struct
  ...
end
```
- Define your type in unstable scope by repeating the definition
```ocaml
(* Good *)
module Stable = struct
  module V1 = struct
    type t = { x : int; y : string } [@@deriving bin_io, sexp, stable_witness]
  end
end

open! Core

type t = { x : int; y : string } [@@deriving sexp_of]  (* repeated *)

(* Bad - referencing Stable type directly *)
type t = Stable.V1.t [@@deriving sexp_of]
