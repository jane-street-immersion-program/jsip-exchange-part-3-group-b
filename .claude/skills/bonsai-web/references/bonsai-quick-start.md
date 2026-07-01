# Bonsai Quick Start Reference

Compressed reference for Bonsai state, control flow, effects, and patterns.
ppx_html syntax and styling are covered in the main SKILL.md — this file focuses on everything else.

For a full worked example, see the `app/dashboard` client in this project, plus the public
Bonsai documentation.

## Control Flow

### `let%arr` — transform `Bonsai.t` values

```ocaml
let component student =
  let%arr student in
  {%html|<div>#{Student.name student}</div>|}
```

### `match%arr` — simple conditional rendering (preferred)

No state in branches. Sugar for `let%arr x in match x with ...`:

```ocaml
let component (student : Student.t Bonsai.t) =
  match%arr student with
  | Student.Phd _ -> {%html|<div>PhD student</div>|}
  | Masters _ -> {%html|<div>Masters student</div>|}
  | Bachelors _ -> {%html|<div>Undergrad</div>|}
```

### `match%sub` — branches with their own state

Use only when branches need `graph`. Each arm creates independent Bonsai state.

```ocaml
let component (name : string Bonsai.t) (local_ graph) =
  match%sub name with
  | "Bob" ->
    let is_on, toggle = Bonsai.toggle ~default_model:true graph in
    let%arr is_on and toggle in
    {%html|<button on_click=%{fun _ -> toggle}>Toggle</button>|}
  | other ->
    let%arr other in
    {%html|<div>#{other}</div>|}
```

### `match%sub [%lazy]` — deferred construction

Defers Bonsai node creation until matched. Requires `graph` in scope.
Use sparingly — mainly for URL routing where each route is a large page.

### `Bonsai.assoc` — per-key nodes from a map

Each key gets independent state. Use `Vdom.Node.Map_children.div` to render.

```ocaml
let component ~todos (local_ graph) =
  let views =
    Bonsai.assoc (module Int) todos
      ~f:(fun _key todo (local_ graph) ->
        let done_, set_done = Bonsai.state false graph in
        let%arr todo and done_ and set_done in
        {%html|<div>#{todo}<button on_click=%{fun _ -> set_done true}>Done</button></div>|})
      graph
  in
  let%arr views in
  Vdom.Node.Map_children.div views
```

**Caution:** significant overhead, especially nested `assoc` inside `assoc`.

## State

All state APIs take `graph` and return (current_value, updater).

| API | When to use | Updater type |
|-----|-------------|--------------|
| `Bonsai.state` | Simple replacement, new value independent of old | `'a -> unit Effect.t` |
| `Bonsai.state'` | New value depends on old (counters) | `('a -> 'a) -> unit Effect.t` |
| `Bonsai.toggle` | Boolean toggle | `unit Effect.t` (toggles) |
| `Bonsai.toggle'` | Boolean with toggle + direct set | `{ state; toggle; set_state }` |
| `Bonsai.state_machine` | Multiple action types, complex update logic | `'action -> unit Effect.t` |
| `Bonsai.actor` | State machine where actions return values | `'action -> 'result Effect.t` |
| `Bonsai.state_machine_with_input` | State machine needing external changing input | `'action -> unit Effect.t` |
| `Bonsai.scope_model` | Separate state per key (e.g., per-tab, per-user) | N/A (wraps inner component) |

### `Bonsai.state` and `Bonsai.state'`

```ocaml
(* state: replace entirely *)
let name, set_name = Bonsai.state "Alice" graph in

(* state': update based on previous *)
let count, set_count = Bonsai.state' 0 graph in
(* In let%arr: *) set_count (fun c -> c + 1)
```

**Prefer `Bonsai.state'` over `Bonsai.state` when updating records.** Two concurrent
effects calling `set_profile { profile with ... }` via `Bonsai.state` race: the second
write overwrites the first using a stale closure. `state'` always sees the latest value:

```ocaml
set_profile (fun profile -> { profile with email = Some new_email })
```


### `Bonsai.toggle` and `Bonsai.toggle'`

```ocaml
let is_on, toggle = Bonsai.toggle ~default_model:true graph in
(* toggle : unit Effect.t — flips the boolean *)

let { Bonsai.Toggle.state; set_state; toggle } =
  Bonsai.toggle' ~default_model:true graph
(* set_state : bool -> unit Effect.t — set directly *)
```

### `Bonsai.state_machine`

Define `action` type (variants) and `apply_action` function:

```ocaml
type action = Add_grade of float | Reset

let state, inject =
  Bonsai.state_machine
    ~default_model:{ total = 0.0; count = 0 }
    ~apply_action:(fun _ model -> function
      | Add_grade g -> { total = model.total +. g; count = model.count + 1 }
      | Reset -> { total = 0.0; count = 0 })
    graph
(* inject : action -> unit Effect.t *)
```

### `Bonsai.actor`

Like `state_machine` but `recv` returns `(new_model, return_value)`:

```ocaml
let state, inject =
  Bonsai.actor
    ~default_model:{ todos = []; next_id = 0 }
    ~recv:(fun _ model -> function
      | Add text ->
        let id = model.next_id in
        { todos = (id, text) :: model.todos; next_id = id + 1 }, id
      | Remove id ->
        { model with todos = List.filter model.todos ~f:(fun (i,_) -> i <> id) }, id)
    graph
(* inject : action -> int Effect.t — returns the ID *)
```

### `Bonsai.state_machine_with_input`

Like `state_machine` but `apply_action` receives a changing `~input` value:

```ocaml
let count, update =
  Bonsai.state_machine_with_input
    ~default_model:0
    ~apply_action:(fun _ input_status count action ->
      let step = match input_status with Active s -> s | Inactive -> 1 in
      match action with Increment -> count + step | Decrement -> count - step)
    step_size  (* Bonsai.t input *)
    graph
```

### `Bonsai.scope_model`

Maintains separate state per key value. Switching keys preserves each key's state.

```ocaml
Bonsai.scope_model (module String) ~on:active_user graph
  ~for_:(fun graph ->
    let%arr counter = Counter.component graph and form in
    {%html|<div>%{Form.view form}%{counter}</div>|})
```

## Effects

Effects (`Effect.t`) are side effects scheduled by the Bonsai runtime, typically from event handlers.

### Scheduling

```ocaml
let increment : unit Effect.t = set_count (fun c -> c + 1) in
{%html|<button on_click=%{fun _ -> increment}>+</button>|}
```

### Chaining with `let%bind.Effect`

```ocaml
let submit =
  let%bind.Effect () = Effect.print_s [%message "Validating..."] in
  let%bind.Effect () = Effect.print_s [%message "Submitting..."] in
  set_message "Done!"
```

### `Effect.of_sync_fun` — wrap synchronous functions

```ocaml
let%bind.Effect n = Effect.of_sync_fun (fun () -> Random.int 100) () in
set_number n
```

### `Effect.all_parallel_unit` — run multiple effects concurrently

```ocaml
Effect.all_parallel_unit
  [ (Effect.Prevent_default [@alert "-deprecated"])
  ; set_count (fun c -> c + 1)
  ; Effect.print_s [%message "Clicked!"]
  ]
```

## Common Gotchas

**Can't embed `Bonsai.t` in ppx_html.** `ppx_html` produces `Vdom.Node.t` (a snapshot), not `Vdom.Node.t Bonsai.t` (reactive). Use `let%arr` to extract the current value first:

```ocaml
(* WRONG: Counter.component returns Vdom.Node.t Bonsai.t *)
{%html|<%{Counter.component graph} />|}

(* RIGHT: let%arr extracts the Vdom.Node.t *)
let%arr counter = Counter.component graph in
{%html|<div>%{counter}</div>|}
```

**No nested `let%arr`.** Use `let%arr x and y in ...` not `let%arr x in let%arr y in ...`. Nesting would create `'a Bonsai.t Bonsai.t`, which is not allowed.

**`Bonsai.state` race condition with records.** When two concurrent effects update different fields of the same record using `Bonsai.state`, the second write overwrites the first (stale closure). Use `Bonsai.state'` instead — its `(old -> new)` updater always sees the latest state:

```ocaml
(* BAD: set_profile { profile with email = ... } races with username update *)
(* GOOD: *)
let profile, set_profile = Bonsai.state' { username = None; email = None } graph in
(* ... *)
set_profile (fun profile -> { profile with email = Some new_email })
```

## View vs Component Convention

**Always put a reusable piece of UI in a module with a `view` or `component` function.** Never expose a bare top-level `let button ...`; write `module Button = struct let view ... end` (or `let component ...`) instead. `<Module.path>` call syntax in ppx_html requires exactly this shape, so following it keeps every component usable from `{%html| ... |}`.

- **View**: takes non-`Bonsai.t` params, returns `Vdom.Node.t`. No `graph`, no `let%arr`. Export as `Module.view`.
- **Component**: takes `Bonsai.t` params and/or `graph`, returns `'a Bonsai.t`. Export as `Module.component`.
- Views can only call other views. Components can call both.

## Lifecycle Events

Subscribe to node lifecycle via `Bonsai.Edge.lifecycle`:
- `on_activate` — when node is added to graph
- `on_deactivate` — when node is removed from graph

Most nodes persist for app lifetime (activate fires once, deactivate never fires). Only `match%sub` and `Bonsai.assoc` conditionally create/destroy nodes.

**State persists across lifecycle.** A node's state survives removal and re-addition. To reset state on removal, use `Bonsai.with_model_resetter` or `Bonsai.scope_model`.

```ocaml
Bonsai.Edge.lifecycle
  ~on_activate:(let%arr log in log "Activated")
  ~on_deactivate:(let%arr log in log "Deactivated")
  graph;
```

## Routing

Most JSIP apps are single-page and need no routing. If you do need it, `Url_var` (from
`bonsai.extra`) gives you a `Bonsai.t` for the current URL that you can `match%sub` on,
using `match%sub [%lazy]` for heavy route pages so they're built only when matched.

## Error Handling

Wrap fallible values in `Or_error.t Bonsai.t`. **Never raise exceptions** — they are extremely slow in `js_of_ocaml`.

```ocaml
match%arr student_result with
| Ok student -> {%html|<div>#{Student.name student}</div>|}
| Error err -> {%html|<div>Error: #{Error.to_string_hum err}</div>|}
```
