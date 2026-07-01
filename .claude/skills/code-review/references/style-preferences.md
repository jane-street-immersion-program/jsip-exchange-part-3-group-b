# Style Preferences for Generalizing CRs

When generalizing CR feedback, apply these conventions across the diff. Firmwide
conventions come from the Jane Street OCaml Style Guide; team-specific ones supplement or
strengthen them.

Users might have different or additional preferences; follow the conventions of the code
you're working in if they differ from what's here.

## Pattern matching and control flow
- `match` over `if-then-else` for decomposing data — match simultaneously inspects and
  binds, avoiding the need to retread ground with `Option.value_exn` etc.
- Put short cases first in match expressions, so the matched expression stays close to
  as many patterns and bodies as possible.
- Avoid catch-all (`_`) patterns on variant types — list cases explicitly so the compiler
  catches additions.
- No `when` clauses except for simple conditions — extract complex logic into a helper or
  nested match.

## Naming
- Boolean-returning functions should have predicate names: `is_valid` not
  `check_validity`.
- `_exn` suffix for functions that can raise.
- `with_` prefix indicates resource acquire/release, not "append".
- `snake_case`, not `camelCase`. American English for identifiers.
- Only begin a variable name with `_` to indicate it's unused.
- Name your constants — don't rely on comments alone. Break constants into sub-constants;
  arithmetic is documentation.

## Types and variants
- Prefer normal variants over polymorphic variants unless you need narrowing/subtyping.
- Annotate type of ignored values: `let (_ : int) = ...`, `ignore (f x : t)`.
- Access record fields and constructors by annotating types, not module paths:
  `let (x : My_record.t) = ...` not `{ My_record.field; ... }`.
- Avoid `M.{ ... }` for constructing records (it's a sneaky local open).
- Named records over unlabeled tuples for return types with >1 field.

## Expressions and style
- `f ();` over `let () = f () in ...` (semicolons for imperative code).
- Avoid `let ... and ...` except in applicative syntax or monads where `and` has
  different semantics (Deferred, Or_error, Incremental).
- Don't bury important context at end of line — `not (pred x)` not `pred x |> not`;
  `ok_exn (...)` not `... |> ok_exn`.
- Avoid polymorphic compare — use `[%equal]`, `[%compare]`, or type-specific comparators.
- For file paths, use `File_path.Operators` (infix `^/`).

## Modules and namespaces
- Open only the modules you need, always at the top of the file.
- Avoid module abbreviation when aliasing — alias to the last path component only.
- Use the classic `module T = struct ... end include T include Foo.Make (T)` form to apply
  a functor.
- Core-style creators: `Key.Map.empty` not `Map.empty (module Key)`.
- Avoid `helpers.ml`, `common.ml`, `util.ml` grab bags.
- Use the intf pattern to define a module type just once.

## Interfaces
- Modules should almost always have a single type, called `t` ("sweeksification").
- Function argument order: optional, t, positional, labeled.
- Label arguments when their purpose isn't obvious from the type.
- Don't expose internal helpers in the mli. Use `Private`, `For_testing`, `Expert`
  submodules for their respective purposes.
- Use signature includes (`include Stringable.S with type t := t`) over hand-written
  interfaces.

## Documentation
- Every library, module, and most mli entries should have documentation.
- Comments should explain *why*, not just *what*.
- Use doc comments (`(** *)`) in mli files. Use `(*_ *)` for author-only notes.
- Avoid useless comments that just restate the type signature.

## Error handling
- Functions should return data, not embed control flow — return a bool or option, let the
  caller decide what to do.
- Don't silently ignore `Or_error` results — log on error, at least at info level.
- Watch out for `don't_wait_for` — it's a sneaky ignore of deferred completion.
- Prefer `don't_wait_for` over `upon` if you don't need to wait for completion.

## Testing
- Prefer `let%expect_test` over `let%test` or `let%test_unit`.
- Optimize tests for readability — make it easy to determine if output is correct.
- Use both assertion-style (`[%test_result]`) and printing-style (`print_s`/`[%expect]`)
  evidence when each style is appropriate: asserts for clarity, prints for debuggable failures and inspectable output.
- Prefer writing tests in external test suites (separate `test/` directory).
- Use `For_testing` modules to expose test-only functionality.

## Monadic style
- Explicit qualifiers (`let%bind.Deferred.Or_error`) over opens
  (`open Deferred.Or_error.Let_syntax`). Makes error paths visible.
- Exception: plain `Deferred` binds don't need qualification if Async is open.

## Additional/miscellaneous conventions
- Separate data extraction from effects: `filter_map` to get data, then `iter` to act.
- Use `[@@deriving of_sexp]` / `t_of_sexp` instead of manual sexp parsing when possible.
- Functions should take the minimal data they need
- Group related functions into modules (e.g. `Constants` for any constant runtime config).
- Log levels: info for operational events, error for failures.
- Use ppx_string_dedent (`[%string_dedent]`) for multiline string literals.
- Constants that depend on runtime values should be computed, not guessed.
