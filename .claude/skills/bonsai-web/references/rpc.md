# RPCs in Bonsai

This reference covers how to call Async RPCs from Bonsai web clients via `Rpc_effect`. Two
styles cover almost everything in JSIP:

1. **`Rpc_effect.Rpc.dispatcher`** — one-shot calls for user actions (submit, delete).
2. **`Rpc_effect.Rpc.poll`** — periodically fetch data; one request in flight at a time.

The worked example is `app/dashboard`: the client polls the server for recent samples, and
the shared RPC protocol lives in `app/dashboard/protocol`.

For exact labels and optional arguments, read the `Rpc_effect` `.mli` in your opam switch.

## Choosing an RPC style

| Need | Use |
|------|-----|
| One-shot action triggered by the user (submit form, click delete) | `Rpc_effect.Rpc.dispatcher` |
| Periodically fetch data that the server recomputes | `Rpc_effect.Rpc.poll` |
| Server-pushed stream | Prefer client polling. `Pipe_rpc` / `State_rpc` push from server to client, but a backgrounded browser tab stops processing events, so diffs pile up and cause freezes on refocus plus server-side memory growth. Polling inverts this: the client drives, and a backgrounded tab simply stops polling. |

## Where to connect

`Rpc_effect` functions take an optional `~where_to_connect`. For an app served by its own
server (the JSIP dashboard case) you can omit it — it defaults to connecting back to the
server that served the page. Pass it explicitly only when connecting to a different
service.

## `dispatcher` — one-shot calls

Use for user-initiated actions. Returns a Bonsai function that produces an `Effect.t` when
called:

```ocaml
let dispatch_save =
  Rpc_effect.Rpc.dispatcher my_rpc graph
in
(* dispatch_save : (Query.t -> Response.t Or_error.t Effect.t) Bonsai.t *)

let%arr dispatch_save in
fun query ->
  let%bind.Effect result = dispatch_save query in
  match result with
  | Ok response -> handle_ok response
  | Error err   -> handle_error err
```

## `poll` — periodic calls with tracked state

Use to periodically fetch data. Only one request is in flight at a time. This is exactly
what `app/dashboard/client/samples_subscription.ml` does:

```ocaml
let _ : Recent_samples.Response.t option Bonsai.t =
  Rpc_effect.Rpc.poll
    Protocol.Rpcs.recent_samples_rpc
    ~equal_query:[%equal: Recent_samples.Query.t]
    ~on_response_received
    ~every:poll_every
    ~output_type:Last_ok_response
    query
    graph
in
```

Here `query` is a `Query.t Bonsai.t` (so polling re-issues when the query changes),
`~every` is a `Time_ns.Span.t Bonsai.t`, and `~on_response_received` is an optional
callback that lets you fold each response into your own state machine (the dashboard uses
it to append new samples to a ring buffer via `inject`).

## Output types (`~output_type`)

`poll` takes `~output_type` to control the shape of its Bonsai result:

| Output type | Returns | Use when |
|-------------|---------|----------|
| `Last_ok_response` | Latest successful response (as an `option`) | You only care about the happy path. This is what the dashboard uses. |
| `Pending_or_error` | `'response Pending_or_error.t` | You want to distinguish "loading" from "error" from "ok". |
| `Response_state` | Most recent response across all queries | You want to keep showing stale data while a new query loads. |

See the `Poll_result` / output-type definitions in the `Rpc_effect` `.mli` for the full
set (including fetching-status and refresh-effect variants).

## Connection status

`Rpc_effect.Status.state` returns a `Bonsai.t` reflecting the connection state
(`Connecting` / `Connected` / `Disconnected`), which is handy for a global "offline"
banner.

## Error handling

Every dispatcher/poll result carries `Or_error.t`. **Don't raise in `js_of_ocaml`** — it
is extremely slow. Propagate the `Or_error.t` through your `Bonsai.t` and render the error
case in the view.

## Advanced: diff-based polling

`Rpc_effect` also has a `Polling_state_rpc` flavor where the server sends a full response
once and then diffs (good for large maps/tables where diffs are much smaller than full
responses). JSIP apps use plain `Rpc.poll`; reach for `Polling_state_rpc` only if a poll
response gets large enough that diffing is worth the extra protocol complexity, and check
whether it's available in your switch first.
