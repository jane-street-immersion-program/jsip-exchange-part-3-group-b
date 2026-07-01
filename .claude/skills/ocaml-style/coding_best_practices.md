# OCaml Code Conventions

- Prefer plain variants over poly variants
- Use qualified names, do not open modules
- Do not over-qualify names when context makes the qualification redundant, such as
  when type inference disambiguates or a module is already open in scope.
```ocaml
(* GOOD *)
some_function ~param:Variant_a

(* BAD *)
some_function ~param:Module_a.Module_b.Variant_a
```

## Monads
```ocaml
(* Preferred: let-ppx *)
let%bind.Option some_result = some_function x in
...

(* Or open first: use for many similar binds *)
let open Option.Let_syntax in
let%bind some_result = some_function x in
...

(* Traditional - use sparingly *)
Option.bind (some_function x) ~f:(fun some_result -> ...)

(* Infix operators - use sparingly *)
(>>|) (* for map *)
(>>=) (* for bind *)


(* GOOD *)
let foo x y =
   let%bind a = some_function x in
   let%bind b = some_other_function y in
   return (a, b)
;;

(* BAD *)
let foo x y =
    some_function x >>= fun a ->
    some_other_function y >>= fun b ->
    return (a, b)
;;

```

## Type Definitions
- Prefer a `type t` within a named module (a 'sweeksified type')

```ocaml
(* GOOD *)
module Order_id = struct
    type t = string
end

(* BAD *)
type order_id = string
```

## Type annotations
- Temporary type annotations are a good debugging tool when compiler errors are unclear.
  Adding an annotation to a function parameter, match scrutinee, or intermediate binding can
  make missing record fields, variant constructors, and type mismatches much easier to
  diagnose.
- Once the issue is understood and the code compiles cleanly, remove annotations that are no
  longer needed.

### Examples of acceptable annotations
This is not an exhaustive list of acceptable type annotations but bey very conservative about leaving them in the code

*Inside ppx blocks* — [%sexp], [%message], etc. require explicit types.
*Record field access without prior inference* — the first use of an identifier is foo.bar and no earlier call gives the compiler the type.
*Variant matching without prior inference* — the first use is matching on variants and no earlier call gives the compiler the type.

## Pattern Matching
- Do not use catch-all patterns for enumerable variants
- Explicit payload wildcards are fine when the constructor is named; prefer typed `_`
  patterns when ignoring the payload
- Different teams have different conventions around matching on booleans. Follow the
  surrounding code when there is a clear local pattern. In the absence of one, prefer
  `match` once either arm becomes multi-line: it keeps branch order flexible and is
  easier to extend safely. For short single-expression branches, either style can be
  fine.

```ocaml
(* GOOD *)
match status with
| Active -> process_active ()
| Pending -> process_pending ()
| Completed | Cancelled -> failwith "unexpected_state"

match List.is_empty items with
| false -> List.rev items
| true ->
  default_items ()
  |> List.filter ~f:is_valid
  |> List.dedup_and_sort ~compare:Int.compare

(* BAD *)
match status with
| Active -> process_active ()
| Pending -> process_pending ()
| _ -> failwith "unexpected status"

if List.is_empty items
then
  default_items ()
  |> List.filter ~f:is_valid
  |> List.dedup_and_sort ~compare:Int.compare
else List.rev items

(* ACCEPTABLE *)
match value with
| None -> process_none ()
| Some (_ : string) -> process_some ()

if keep_weight_sum then weight_agg :: aggs else aggs
```

## Ignored values
Make the discarded type visible

```ocaml
(* GOOD *)
match maybe_name with
| Some (_ : string) -> handle_some ()
| None -> handle_none ()

match t with
| { id = (_ : int); name } -> use name

ignore (List.map xs ~f : _ list)
let (_ : int) = count_sheep () in
...

(* BAD *)
let _ = count_sheep () in
Fn.ignore (List.map xs ~f)
...
```

## Tests
- Use expect tests
- Expect tests with CRs are failing, despite what the build says
- Complex tests live in `test` subdir of the project

## Maps & Sets
* Use Core-style map & set creators:
```ocaml
(* GOOD *)
Key.Map.empty
Key.Map.of_alist_exn

(* BAD *)
Map.empty (module Key)
Map.of_alist_exn (module Key)
```

## Source code position

Some functions take a `Source_code_position.t` to report where they were called from.
Default `?(here = [%here])` and pass `~here:[%here]` explicitly at the call site when you
want the caller's location.

```ocaml
val require : ?here:Source_code_position.t -> bool -> unit

let require ?(here = [%here]) condition =
  if not condition
  then raise_s [%message "require failed" (here : Source_code_position.t)]
;;
let () = require ~here:[%here] is_valid
```

Forward `~here` (defaulting to `[%here]`) when threading a caller's location through a
helper, or when attaching it to a manually constructed error.

## Choosing APIs
- Prefer APIs that are harder to misuse and easier to keep correct as the code evolves.
  This is true both for writing code and choosing what existing library to use.
- When there is a stronger-typed helper available, prefer it over a stringly or loosely
  typed one.
- Prefer `with_`-style helpers that scope cleanup in a callback over create/release pairs,
  so the resource is always cleaned up even on exceptions. Use `Core`'s `In_channel.with_file` /
  `Out_channel.with_file` to scope cleanup and `Filename` / `Filename_unix` to create temp
  paths. (`File_path` is available, so prefer it for typed path values.)

```ocaml
(* Scope cleanup with with_file; create temp paths via Filename *)
In_channel.with_file path ~f:(fun in_channel -> ...)
```

## Engineering principles
- **DRY**: avoid duplication. If logic or a variable exists elsewhere, reuse it. If two
callsites share logic or use the same constant (that is also the same semantically, no
point in having a variable for 1 if it doesn't mean more), extract a helper and
parameterize differences.

DRY is more than just avoiding big shared logic, it's also about ensuring that a default
value is consistent with what we show in a command help text (by reusing a variable for
both)
- **KISS**: prefer simple, direct code. Add complexity only when it clarifies boundaries
and control flow.

## Good code
Unless the user explicitly asks otherwise, do not make changes you believe are
poor-quality, low-signal, or bad style just to satisfy a requirement.

If the available options all seem bad, stop and explain the tradeoffs, blockers, and the
least-bad next steps.

If the user explicitly prefers one of those options, trust them and do it to completion!
