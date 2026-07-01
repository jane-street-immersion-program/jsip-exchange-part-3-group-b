---
name: bonsai-web
description: "Bonsai web UI framework: Bonsai components, ppx_html, Vdom, Rpc_effect, js_of_ocaml, let%arr, let%sub, match%sub."

---

# Bonsai Web

Use the following stack to build web UIs in Bonsai

| Tool | Purpose |
|------|---------|
| **Bonsai** | Incremental web framework — state, effects, computation graph |
| **ppx_html** | JSX-like HTML syntax in OCaml (`{%html\| ... \|}`) |
| **js_of_ocaml** | Compiles the client OCaml to a JS bundle |
| **rpc_effect** | Effect-based interface to RPCs (`Rpc_effect.Rpc.poll` / `dispatcher`) |

## Getting Started

A Bonsai client is a `js_of_ocaml` executable. Minimal app entry point:
```ocaml
let app (local_ graph) : Vdom.Node.t Bonsai.t =
  let count, set_count = Bonsai.state' 0 graph in
  let%arr count and set_count in
  {%html|
    <button on_click=%{fun _ -> set_count (fun c -> c - 1)}>-</button>
    <span>%{count#Int}</span>
    <button on_click=%{fun _ -> set_count (fun c -> c + 1)}>+</button>
  |}

let () = Bonsai_web.Start.start app
```

The client `dune` needs `bonsai`, `bonsai.extra`, `bonsai_web`, and `virtual_dom` in
`(libraries ...)`, and `ppx_jane`, `bonsai.ppx_bonsai`, `ppx_html`, and `js_of_ocaml-ppx`
in `(preprocess (pps ...))`.

## Building the client with dune

The client executable compiles to JS with `(modes js)` and `js_of_ocaml`:

```
(executable
 (name main)
 (modes js)
 (js_of_ocaml
  (flags (:standard --effects=cps)))
 (libraries core bonsai bonsai.extra bonsai_web virtual_dom ...)
 (preprocess
  (pps ppx_jane bonsai.ppx_bonsai ppx_html js_of_ocaml-ppx)))
```

`dune build` produces `main.bc.js`. A separate server binary (e.g. using `cohttp-async` +
`async_rpc_websocket`) serves that bundle alongside a static `index.html`. See
`app/dashboard` in this project for a complete client + server + protocol example.

## Design

When doing any user interface work, **always** use the [[frontend-design]] skill

## Core Bonsai

### Two-phase model

Bonsai functions take `(local_ graph)` as a parameter. Code using `graph` runs **once** at
initialization to build the computation graph. Code inside `let%arr` blocks runs
**repeatedly** during stabilization as inputs change. `graph` is `local_`, so you cannot
store it in closures or refs.

### State

All state APIs take `graph` and return `(current_value, updater)`.

```ocaml
(* Replace entirely *)
let name, set_name = Bonsai.state "Alice" graph in
(* set_name : (string -> unit Effect.t) Bonsai.t *)

(* Update based on previous value — use for counters or anything read-modify-write *)
let count, set_count = Bonsai.state' 0 graph in
(* set_count : ((int -> int) -> unit Effect.t) Bonsai.t *)

(* State machine — define an action type and an apply function *)
type action = Add_grade of float | Reset

let stats, inject =
  Bonsai.state_machine
    ~default_model:{ total = 0.0; count = 0 }
    ~apply_action:(fun _ctx model -> function
      | Add_grade g -> { total = model.total +. g; count = model.count + 1 }
      | Reset -> { total = 0.0; count = 0 })
    graph
in
(* inject : (action -> unit Effect.t) Bonsai.t *)
```

| API | When to use |
|-----|-------------|
| `Bonsai.state` | Simple replacement, new value independent of old |
| `Bonsai.state'` | New value depends on old (counters, record field updates) |
| `Bonsai.state_machine` | Multiple action types, complex update logic |
| `Bonsai.actor` | State machine where actions return values |
| `Bonsai.toggle` / `toggle'` | Boolean state |
| `Bonsai.scope_model` | Separate state per key (per-tab, per-user, etc.) |


### `let%arr` — transform `Bonsai.t` values

Use it for all value transformations. Always use `and` instead of nesting:

```ocaml
(* GOOD *)
let%arr count and set_count in

{%html|<button on_click=%{fun _ -> set_count (fun c -> c + 1)}>#{count#Int}</button>|}

(* BAD — nested let%arr creates 'a Bonsai.t Bonsai.t, which is not allowed *)
let%arr count in
let%arr set_count in
...
```

### `let%sub` — split `Bonsai.t` records/tuples

Use one `let%sub` destructure when later graph-building code needs several fields
as separate `Bonsai.t` values:

```ocaml
(* GOOD *)
let%sub { Listed_artifact.artifact_id; metadata; _ } = artifact in
...

(* BAD *)
let artifact_id = let%arr { Listed_artifact.artifact_id; _ } = artifact in artifact_id in
let metadata = let%arr { Listed_artifact.metadata; _ } = artifact in metadata in
...
```

### `match%arr` vs `match%sub`

Prefer `match%arr` for simple branching — no state in branches:

```ocaml
match%arr student with
| Phd _ -> {%html|<div>PhD student</div>|}
| Masters _ -> {%html|<div>Masters student</div>|}
| Bachelors _ -> {%html|<div>Undergrad</div>|}
```

Use `match%sub` only when branches need their own `graph` / state. It has significant
overhead. Use `match%sub [%lazy]` to defer branch construction (mainly for URL routing).

### `Bonsai.assoc` — per-key nodes from a map

Each key can get individual state using the `graph` parameter:

```ocaml
let views =
  Bonsai.assoc (module Int) todos
    ~f:(fun _key todo (local_ graph) ->
      let done_, set_done = Bonsai.state false graph in
      let%arr todo and done_ and set_done in
      {%html|<li>#{todo}</li>|})
    graph
in
let%arr views in
Vdom.Node.Map_children.div views
```

Nested `assoc` inside `assoc` is expensive; avoid when possible.

### Effects

`Effect.t` represents side effects scheduled by the Bonsai runtime, typically from event
handlers.

```ocaml
(* Chain sequentially *)
let submit =
  let%bind.Effect () = Effect.print_s [%message "Validating..."] in
  let%bind.Effect () = save_effect in
  set_message "Done!"

(* Wrap a synchronous function *)
let%bind.Effect n = Effect.of_sync_fun (fun () -> Random.int 100) () in
set_number n
```
**Never raise exceptions in `js_of_ocaml`** — they are extremely slow. Propagate
`Or_error.t` through `Bonsai.t` and render the error case.

### Common gotcha: can't embed `Bonsai.t` in ppx_html

`ppx_html` produces `Vdom.Node.t` (a snapshot), not `Vdom.Node.t Bonsai.t` (reactive). Use
`let%arr` to extract the current value first:

```ocaml
(* WRONG — Counter.component returns Vdom.Node.t Bonsai.t *)
{%html|<div>%{Counter.component graph}</div>|}

(* RIGHT *)
let%arr counter = Counter.component graph in
{%html|<div>%{counter}</div>|}
```

### View vs component convention

**Always wrap a reusable piece of UI in a module with a `view` or `component`
function.** Do not expose bare top-level functions like `let button ...` — write
`module Button = struct let view ... end` (or `let component ...`) instead. This is
what makes `<Button.view>...</>` work in ppx_html; callers using `<Module.path>`
syntax need exactly this shape.

- **View**: takes non-`Bonsai.t` params, returns `Vdom.Node.t`. No `graph`, no
  `let%arr`. Export as `Module.view`. For ppx_html compatibility, use a single positional
  parameter for the children (either `Vdom.Node.t list` or `unit`).
- **Component**: takes `Bonsai.t` params and/or `graph`, returns `'a Bonsai.t`. Export
  as `Module.component`.
- Views can only call other views. Components can call both.

```ocaml
(* GOOD — callable as <Button.view ~on_click=%{save}>Save</> *)
module Button = struct
  let view ?(attrs = []) ~on_click children =
    {%html|<button *{attrs} on_click=%{on_click}>*{children}</button>|}
end

(* BAD — cannot be used via <...> syntax; breaks the convention. *)
let button ?(attrs = []) ~on_click children = ...
```

**For `state_machine` / `actor`, `scope_model`, lifecycle events, routing with
`Url_var`, and more examples:** Load `references/bonsai-quick-start.md`.

### Style rules

These come up often. Follow them by default.

- **Always destructure the record/tuple in `let%arr`.** This adds a cutoff so the
  block only re-runs when the destructured fields change:
  `let%arr { foo; _ } = my_thing in ...`, not `let%arr my_thing in my_thing.foo`.
- **Prefer `let%arr` over `Bonsai.map` / `let%map` / `>>|`.** They produce equivalent
  graphs but `let%arr` is the only form that gets the destructure-cutoff optimization
  and is the form readers expect.
- **No side effects in `let%arr` bodies.** A `let%arr` body can run multiple times
  per frame and even runs while the node is inactive. Use `Bonsai.Edge.on_change`
  for effects that should fire when a value changes.
- **Use `Bonsai_web.Effect.t`, not `Ui_effect.t`.** `Effect.t` is a superset and the
  one the rest of the codebase uses; mixing them causes annoying type mismatches.
- **Use let-punning in `let%arr`.** `let%arr current_file and current_directory` is
  easier to read than `let%arr file = current_file and dir = current_directory`,
  and keeps grep working.
- **Don't compute expensive things while building an `Effect.t`.** The constructor
  runs every stabilization, the effect runs once. Move work inside the effect with
  `Effect.of_sync_fun` (or similar) so it runs at click time, not build time.
- **Avoid `Bonsai.Clock.Expert.now` — it ticks every frame (~60 Hz).** For crossing a
  deadline use `Bonsai.Clock.at`, for an approximate time use
  `Bonsai.Clock.approx_now ~tick_every`, and to capture "now" inside an effect use
  `Bonsai.Clock.get_current_time`.
- **Always pass `(local_ graph)` as an explicit named `graph` parameter.**
  `match%sub [%lazy]` requires the binding to be called `graph`, and `local_`
  prevents accidentally storing it in a closure.

## ppx_html

**Always** use `{%html| ... |}` for writing Bonsai components.
**Avoid** manual `Vdom.Node.*` function calls.

ppx_html is more readable and is the standard way to write Bonsai views. Full docs: the
public `ppx_html` README.

### Interpolation

The sigil picks the type. Use `#{foo}` for strings, `%{foo#Module}` for anything with a
`Module.to_string`, `%{node}` for a single `Vdom.Node.t` or `Vdom.Attr.t`, `*{items}` for a list,
and `?{node}` for a `Vdom.Node.t option`:

```ocaml
{%html|
  <div %{container_attr} *{extra_attrs} ?{maybe_attr}>
    <h1>Hello, #{name}!</h1>
    <p>You have %{count#Int} items.</p>
    %{child_view}
    <ul>*{item_views}</ul>
    ?{maybe_footer}
  </div>
|}
```

### Components

**Always** call Bonsai components using `<Module.path>` syntax when possible. The last positional
parameter determines the tag style:

- **`unit` -> self-closing:** `<Greeting.view />`
- **`Vdom.Node.t list` -> with children:** `<Card.view> content </>`

Pass named arguments with `~arg:%{value}`. Pass HTML attributes (like `on_change`) as Attr.t
directly — this works when the component function has an optional `?(attrs = [])` parameter.
Explicit named arguments are preferred to attrs when a component provides them (e.g. a
`~on_click` argument gives stronger guarantees than `Attr.on_click`). Host elements like
`div` and `input` only support attrs.

```ocaml
{%html|
  <>
    <Button.view ~on_click:%{handler}>Save</>
    <input type="text" value=%{value} min=%{min} max=%{max} />
  </>
|}
```

Use `<>...</>` fragments when you need multiple sibling root nodes.

## Styling

This project does **not** depend on `ppx_css`, and `ppx_html`'s `style="..."` attribute
desugars to `ppx_css` — so do not write `style=` inside `{%html| |}`. Instead build a
plain string `style` attribute with `Vdom.Attr.create "style" "..."` and interpolate it
into the markup as an attribute:

```ocaml
let card_style = Vdom.Attr.create "style" "display: flex; gap: 8px; padding: 16px" in
{%html|
  <div %{card_style}>
    <span>#{text}</span>
  </div>
|}
```

Keep style strings as named tokens in one module (see `app/dashboard/client/styles.ml`
for this pattern) so colors and spacing stay consistent across the app.

## Data fetching

Call Async RPCs from Bonsai clients via `Rpc_effect`. Two main styles:

- **`Rpc_effect.Rpc.dispatcher`** — one-shot calls for user actions (save, delete).
- **`Rpc_effect.Rpc.poll`** — periodically fetch data; only one request in flight at a
  time. This is what `app/dashboard` uses to stream samples from the server.

Quick shape of a dispatcher:

```ocaml
let dispatch =
  Rpc_effect.Rpc.dispatcher
    my_rpc
    ~where_to_connect:(Bonsai.return Where_to_connect.Self)
    graph
in
(* dispatch : (Query.t -> Response.t Or_error.t Effect.t) Bonsai.t *)
```

**For full details — `Rpc.poll` options (`~output_type`, `~on_response_received`),
`Where_to_connect`, and connecting a client to a server over a websocket:**
Load `references/rpc.md`.

## Routing

Most JSIP apps are single-page and need no routing. If you do want client-side routing,
`Url_var` (from `bonsai.extra`) parses the URL into a typed route you branch on with
`match%sub`.

## Forms

**Build forms by hand: compose host inputs (`<input>`, `<select>`, `<textarea>`) with
`Bonsai.state'` and plain `let%arr`.** Hold each field in its own state, read the values
in a `let%arr`, and validate into an `Or_error.t` before submitting. This is simpler and
more transparent than a form-combinator library.

**For the full form patterns — input catalog, multi-field composition, validation with
`Or_error.t`, and submit buttons:**
Load `references/forms.md`.

## Key File Locations

The worked example for this project is the dashboard app:

| Resource | Path |
|----------|------|
| Client (Bonsai + ppx_html + Rpc_effect) | `app/dashboard/client/` |
| Client entry point | `app/dashboard/client/main.ml` |
| Style-token module | `app/dashboard/client/styles.ml` |
| Server (cohttp + websocket) | `app/dashboard/server/` |
| RPC protocol shared by client and server | `app/dashboard/protocol/` |

For API reference beyond this project, consult the public Bonsai documentation and the
`.mli` files in your opam switch (`bonsai`, `bonsai_web`).

## Reference Files

- `references/bonsai-quick-start.md` — Compressed Bonsai quick start (state, effects, ppx_html, control flow)
- `references/rpc.md` — RPCs in Bonsai: `Rpc_effect.Rpc.dispatcher` and `Rpc.poll`
- `references/forms.md` — Building forms by hand with host inputs and `Bonsai.state'`
