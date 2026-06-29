# JSIP Exercises - Part 2

In this part you'll finish off the matching engine's last big gap — order
cancellation — and then spend the bulk of your time building out the
exchange's "ecosystem": automated trading bots and the named scenarios
that compose them. By the end of the part you should have a running
scenario producing a continuous stream of orders, fills, and
market-data updates that you can watch live in the monitor, plus at
least one bot of your own design contributing to the action.

A bit of vocabulary you'll see throughout this part:

- **Best bid** is the highest buy price currently resting in the book;
  **best ask** (or **best offer**) is the lowest sell price.
- **BBO** (best bid and offer) is the pair `(best bid, best ask)`.
  It's what most market-data feeds publish on every change.
- A **resting** order is one that's sitting in the book waiting to be
  matched. An order is **marketable** if its price lets it trade
  against something already resting on the opposite side (see Part
  1).
- A **quote** is a price (and size) that a participant — usually a
  market maker — is offering to buy or sell at. Posting a buy quote
  means submitting a resting buy order; "re-quoting" means cancelling
  your existing quote and posting a fresh one.
- A **ladder** is a set of orders posted by the same participant at
  several different prices on the same side. A market maker that
  posts five bids at $9.99, $9.98, $9.97, $9.96, and $9.95 has a
  five-level ladder on the bid side.
- A **trade event** is what the matching engine emits whenever a
  trade happens (the `Trade_report` variant of `Exchange_event.t`).
  It's the public announcement that a trade occurred at some
  price/size, with no information about who was involved.

**Learning goals for Part 2:**

- Add a feature that spans every layer of a real system — types,
  matching engine, RPC protocol[^rpc], text-command parsing, and
  tests — picking up the kind of cross-cutting change that's
  typical in a monorepo (a single source repository holding many
  loosely-connected libraries and applications, as opposed to a
  repo per library).
- Implement automated trading strategies whose behavior depends on
  state that persists across many events, and reason about how a
  strategy's choices interact with the rest of the ecosystem.
- Design a generic interface (the bot framework) and migrate an
  existing concrete implementation onto it, weighing what should be
  shared in the framework versus left to each implementation.
- Use a live observability tool (the monitor) to debug and tune a
  distributed system you've built.

[^rpc]:
    _RPC_ (Remote Procedure Call) is a style of network
    communication where one process calls a function that runs in
    another process — possibly on another machine — and gets back
    a return value, as if the function were local. The
    implementation under the hood is messages over a socket, but
    the surface looks like an OCaml function call. Jane Street's
    `Async.Rpc` library is the one we use here; you'll see
    `Rpc.Rpc.t` for one-shot request/response RPCs and
    `Rpc.Pipe_rpc.t` for streaming ones (where the server sends
    many messages over time).

---

## Exercise 1: Login, sessions, client order IDs, and cancellation

This is a multi-layer exercise that touches types, the matching engine,
the gateway, and tests. It introduces four related features:

- **Login**, which establishes participant identity at connection time
  instead of per message.
- A **session** abstraction: a per-connection outbound channel that the
  exchange uses to push events to the right participant.
- **Client-assigned order IDs** so a client can track and cancel its
  own orders without depending on the exchange's response.
- **Order cancellation**, with its accompanying RPC and text-protocol
  support.

Each piece is small on its own; together they line up the exchange to
look much more like the asynchronous push-based systems used in the
real world.

### Background: why login?

The current system uses "anonymous" as the default participant and
supports an `as <name>` clause in the text protocol for identification.
That doesn't work well once the exchange needs to keep state per
participant (which it does, as soon as cancellation enters the picture):
cancellation requires knowing _which participant_ is cancelling.

On a real exchange, identity is established at connection time, not per
message. The client authenticates once when connecting, and the server
associates all subsequent messages with that identity. This is both
simpler (no per-message identity field) and more secure (clients can't
impersonate each other).

### Background: why a session abstraction?

Once the exchange knows a connection's participant identity, it can also push events back
to that participant asynchronously. This matters because some events have no synchronous
response to ride on. Consider the resting order case: a participant submits a Day order at
$9.99, the order rests in the book, and minutes later someone else's incoming order trades
against it. The fill is initiated by someone else's submission, so the resting
participant's `submit_order_rpc` call has long since returned `Ok ()`. In our current
exchange architecture, there is nowhere to send the fill for the resting order.

So at login time the server creates a `Session.t` for the connection: a wrapper around an
outbound _pipe_ of `Exchange_event.t`s. Conceptually, a pipe is a simple construct with a
reader end and a writer end, in this context an `Exchange_event.t Pipe.Reader.t` and an
`Exchange_event.t Pipe.Writer.t`. Note that like other polymorphic OCaml types we've seen,
like `int list` or `string list`, pipes are parameterized by the type of data they read
and write.

The writer end can put values into the pipe, and the reader end can take them out. In the
context of an RPC, the reader and writer ends are usually held by different processes,
with elements being sent over the network between them

When the matching engine emits an event involving some participant — `Order_accept`,
`Fill`, `Order_cancel`, `Order_reject` — the system looks up the session and writes the
event to its outbound pipe (we'll use the `Dispatcher` module for this). We'll add a
`session_feed_rpc` clients can use to subscribe to that pipe and processes events as they
arrive.

The matching-engine machinery for this is already in place — see
[The starting state](#the-starting-state) below. What you'll be adding
is the login handshake, the session registry, and the wiring to
replace the dispatcher's printing of events with writing them to a pipe.

### Background: why client order IDs?

The current system assigns order IDs on the server after the order is
accepted. A client that submits an order doesn't know its ID until
the response arrives — and if the response is delayed or lost, the
client has no way to refer to the order. On a real exchange, clients
assign their own order IDs so they can track and cancel orders
without depending on the exchange's response.

The exchange's internal order ID (assigned by `Order_id.Generator`)
still exists and is still important — it establishes a global
ordering used for price-time priority. But it is purely internal.
All client-facing operations (submission, cancellation, events) use
the client-assigned ID.

### The starting state

The project already ships with a few pieces of this machinery in
place — read them before you start so you know what you're working
with:

- `lib/gateway/src/session.{ml,mli}` — a small `Session.t` module
  wrapping a `Participant.t` and an outbound `Exchange_event.t`
  pipe. It exposes `create`, `participant`, `reader`, `push`, and
  `close`. Nothing in the project yet constructs one.
- `lib/gateway/src/dispatcher.{ml,mli}` — the single point of event communication. It owns
  market-data subscriptions, and routes events to each based on the event's type. For
  events that should reach a single participant (`Order_accept`, `Order_cancel`,
  `Order_reject`, and `Fill` as either party) it calls a configurable `on_session_event`
  callback. Currently the dispatcher prints those events to the server's stdout — that's
  the placeholder you'll replace.
- `lib/gateway/src/exchange_server.ml` — runs the matching engine
  on a dedicated Async task that drains the request queue.
  _Async_ is the Jane Street library we use for concurrent I/O:
  it lets a single OCaml process juggle many in-flight operations
  (RPC handlers, timers, pipe reads) cooperatively, rather than
  spawning a thread per operation. A _task_ is one such cooperative
  unit of work; the scheduler runs it whenever its inputs are
  ready and pauses it while it's waiting on I/O. The
  `submit_order_rpc` handler enqueues the request and returns
  `Ok ()`; a separate `Pipe.iter` loop reads requests off the
  queue, runs each through `Matching_engine.submit`, and hands the
  resulting events to `Dispatcher.dispatch`. Everything is one OS
  process — "dedicated task" here just means a long-lived Async
  scheduler job, not a separate thread or process. The point of
  the split is that submit can return immediately without waiting
  for the matching engine, and so that requests are processed
  strictly in arrival order regardless of which clients sent them.

Nothing in the project currently authenticates a connection or
identifies the participant behind an order, so submitted requests
carry their participant in `Order.Request.t.participant` and the
gateway trusts whatever value the client sent. You'll fix that
along the way.

### 1a: Session registry on the dispatcher

Extend the `Dispatcher` with a `Session.t Participant.Table.t`
plus two operations:

- `clean_up_session : t -> Session.t -> unit Deferred.t`.
- `set_up_session : t -> Participant.t -> unit Deferred.t`. This
  should call `clean_up_session` if a session already exists
  before creating a new one.

(A `Deferred.t` is Async's name for a value that hasn't been
computed yet — equivalent to a "future" or "promise" in other
languages. `'a Deferred.t` is the type of "an `'a`, eventually."
Both of these functions return a deferred because they call (or potentially call)
`Session.close`, which closes a pipe and waits for the close to
complete; that wait is an async operation, so the _result_ of
the cleanup is "complete, eventually." When you write
`let%bind () = clean_up_session ...`, you're saying "wait for
that operation to finish, then continue.")

Replace the dispatcher's placeholder `push_to_session` so that
instead of printing, it looks up the participant's session and
calls `Session.push` (if a session exists).

### 1b: Login RPC and connection state

Add a `login_rpc` in `lib/gateway/src/rpc_protocol.{ml,mli}` that
takes a participant name (string) and returns a
`Participant.t Or_error.t`. The handler:

1. Validates the name (rejects empty / whitespace-only names).
2. Creates a `Session.t`.
3. Registers it on the dispatcher; on conflict, returns an error.
4. Stores the session in the connection state so subsequent RPCs
   on the same connection can find it.

Worth noting that this isn't real authentication. A client can
log in as any name that isn't currently taken — there's nothing
stopping someone from claiming to be "Alice" if Alice isn't already
connected. A production exchange would tie identity to a TLS
certificate, a Kerberos ticket, or an out-of-band issued API key.
We're skipping that complexity for now; if you finish early, the
[stretch exercise at the end of the doc](#stretch-real-authentication)
suggests how to add real authentication.

Async RPCs run handlers in the context of a per-connection state
value, which the server creates at connect time and threads into
every RPC handler on that connection. `Exchange_server.start`
currently passes `(fun _addr _conn -> ())` to
`Rpc.Connection.serve`'s `~initial_connection_state` argument,
meaning each connection's state is just `unit`. To remember the
logged-in participant per connection, we need that state to hold
something mutable — specifically the connection's `Session.t`.
Once you change the state type, every RPC handler can read
it (the framework passes it as the first argument).

Change `Exchange_server.start`'s `initial_connection_state` from
`(fun _addr _conn -> ())` to return a mutable record holding the
session:

```ocaml
module Connection_state = struct
  type t = { mutable session : Session.t option }

  let participant t = Option.map t.session ~f:Session.participant
end
```

Also wire up connection-close cleanup: when the RPC connection
closes, unregister from the dispatcher and close the session pipe.
`Rpc.Connection.close_finished` is a convenient hook for this;
spawn the cleanup task from `initial_connection_state` where you
have the `Rpc.Connection.t` in scope.

Update `submit_order_rpc`'s handler to:

1. Read the connection's session; return a "not logged in" error
   if absent.
2. Override the request's participant with the session's identity
   (so a logged-in client can't submit on behalf of someone else).
3. Enqueue the request as before.

Update the scenario runner, the server binary's seed and
trade-back-and-forth modes, and any other callers so they log in
before they submit.

Add a block for `login_rpc` to `lib/gateway/test/test_rpc_shapes.ml`.

### 1c: Session feed RPC

Add a `session_feed_rpc : (unit, Exchange_event.t, Error.t) Rpc.Pipe_rpc.t`.
The handler reads the connection state, fails with
`"not logged in"` if no session exists, and otherwise returns the
session's `Pipe.Reader.t`. The client subscribes once after login
and drains the pipe forever.

This is the channel that delivers `Order_accept`,
`Order_cancel`, `Order_reject`, and the participant's `Fill`
events. The participant reacts to events as they arrive on this
pipe.

Update the interactive client (`app/client/bin/main.ml`) so that
once it has logged in, it dispatches `session_feed_rpc` and prints
the events it receives. This is the right moment to plug in
`Fill.to_participant_view` from Part 1 Exercise 4: each fill on
the session feed is by definition addressed to this client's
participant, so the per-participant rendering ("You bought 100
AAPL at $150.00") is the natural format to print.

Also update `lib/test_harness/src/e2e_helpers.ml` so that end-to-end
tests can rely on participant-targeted events surfacing in expect
output rather than disappearing into the server's stdout. Currently
`connect_as` ignores its `_participant` argument; rewire it so that
after opening the TCP connection it dispatches the new `login_rpc`
with that participant, dispatches `session_feed_rpc` over the same
connection, and kicks off a background task that prints every event
it receives with a participant tag prefix:

```ocaml
let%bind (_ : Participant.t) = login client.conn participant in
let%bind session_feed, _metadata =
  Rpc.Pipe_rpc.dispatch_exn Rpc_protocol.session_feed_rpc client.conn ()
in
don't_wait_for
  (Pipe.iter_without_pushback session_feed ~f:(fun event ->
     let e = Protocol.format_event event in
     print_endline [%string "[%{participant#Participant}] %{e}"]));
```

That way an expect test that binds on `rpc_submit` will see the same per-participant
events a real interactive client would receive on its feed, prefixed by the participant so
multi-client tests stay legible. Update the `connect_as` doc comment in the `.mli` to
describe the new behavior and drop the "forward-compatibility" caveat.

Add a block for `session_feed_rpc` to `lib/gateway/test/test_rpc_shapes.ml`.

### 1d: Client order ID in the request

Add a new `Client_order_id` module and a `client_order_id : Client_order_id.t`
field to `Order.Request.t`. This is the ID chosen by the client.

Make `Client_order_id` a thin `int` wrapper, in the same style as `Order_id` and `Size`:

```ocaml
type t = int [@@deriving sexp, bin_io, compare, equal, hash]
```

Update the text protocol:

```
BUY <client_id> <symbol> <size> <price> [DAY|IOC]
```

For example, `BUY 42 AAPL 100 150.00` submits an order with
client order ID 42. The participant is known from the login.

Events must carry the client order ID so a participant can correlate them with its own
submissions.

- `Order_accept` already carries the `request`, so read the id as
  `request.client_order_id` — don't add a second field for it.
- `Order_cancel` gains a `client_order_id : Client_order_id.t` field.
- `Fill.t` gains both `aggressor_client_order_id` and
  `resting_client_order_id` (a fill has two sides, and either one may
  be this bot's order), each a `Client_order_id.t`.

These changes modify types that are converted to binary data as part of RPCs, so the
`submit-order` digest in `lib/gateway/test/test_rpc_shapes.ml` will change — re-run,
review, and `dune promote`.

### 1e: Duplicate detection

The exchange must reject orders with duplicate client order IDs
from the same participant. Add a lookup structure and check it on
every submission. Emit a `Order_reject` (which the dispatcher will
push to the participant's session feed) if the client order ID is
already in use.

What happens to the ID slot when an order is fully filled or
cancelled? Keeping it occupied prevents accidental reuse; freeing
it allows ID recycling. For debugging and auditing reasons,
preventing reuse is probably preferable.

### 1f: Matching engine cancel

Add a cancel operation. Clients cancel orders by
`(participant, client_order_id)` — the same pair they used to
submit. The engine looks up the internal order via the table from
1e.

The cancel operation should:

1. Find the order by participant and client order ID.
2. Remove the order from the book and emit an `Order_cancel`
   event with `Participant_requested` reason.
3. Emit a BBO update if the cancelled order was at the best price.
4. Handle the case where the order is not found, which includes already-filled orders,
   since those are also removed from the book, by emitting a `Cancel_reject` event. You
   will need to add this variant to `Exchange_event.t`:

   ```ocaml
   | Cancel_reject of
       { participant : Participant.t
       ; client_order_id : Client_order_id.t
       ; reason : string
       }
   ```

**Hint:** Cancellation doesn't need a separate `is_cancelled` flag
on `Order.t`. Just as a fully-filled order is removed from the
book when its remaining size reaches zero, a cancelled order is
removed by the cancel operation. From the book's perspective,
both are simply "gone." The distinction between filled and
cancelled lives in the _events_ (`Fill` vs. `Order_cancel`),
not in the order record.

### 1g: Cancel RPC and CANCEL command

Add a `cancel_order_rpc : (Client_order_id.t, unit Or_error.t) Rpc.Rpc.t`. Same one-way
enqueue-and-return shape as `submit_order_rpc`: the matching-engine response (an
`Order_cancel` event, or a `Order_reject` for "not found") arrives on the session feed.
For the text protocol, add `CANCEL <client_order_id>`.

Add a block for `cancel_order_rpc` to `lib/gateway/test/test_rpc_shapes.ml`.

### Tests

Write tests for:

- Submit with a client order ID, then cancel by that ID. Verify
  the resting participant sees the `Order_cancel` event on its
  session feed.
- Submit with a duplicate client order ID (should produce a
  `Order_reject` event on the session feed).
- Cancel an already-filled order (should produce a "not found"
  rejection — filled orders are removed from the book, same as
  cancelled ones).
- Cancel a non-existent order (should fail).
- BBO update after cancel.
- A participant's resting order, hit by someone else's incoming
  aggressor, results in a `Fill` event on the resting
  participant's session feed (this is the case that motivated
  the whole session abstraction — verify it works).
- Login required before submit or cancel (an unauthenticated
  client gets `Error "not logged in"` from the RPC).
- Two connections trying to log in with the same participant
  name: the second one fails.

**Keep the wire-shape tests current.** This exercise changes the protocol in
several ways — a new `client_order_id` field on `Order.Request.t`, the new
`login_rpc` / `session_feed_rpc` / `cancel_order_rpc` RPCs, and the new
`Cancel_reject` event (which rides on the market-data, audit-log, and
session-feed pipes) — so digests in `lib/gateway/test/test_rpc_shapes.ml` will
change and you'll add new blocks. After each protocol change, run `dune runtest`,
confirm that every digest that moved corresponds to a change you actually made,
then `dune promote`. To add a new RPC's block, copy an existing one and swap in
the RPC. Note the difference between regular and pipe RPCs.

**Hints:**

- The exchange's internal order ID (from `Order_id.Generator`) is
  still used as part of the order book's Map key for price-time
  ordering, but it never appears in client-facing events or APIs.
- With login, the text protocol's `as <name>` clause is no longer
  needed for order submission; remove it.

---

## Exercise 2: Make the market maker dynamic

In this exercise you'll dig into the market maker that already ships
in `app/market_maker/`, extend it to react to its own fills, and use
the cancel feature you built in Exercise 1 to do so.

### Background: static vs. dynamic market makers

A **market maker** is a participant that continuously offers to both
buy and sell a symbol. Their bid sits just below their estimate of
the symbol's true price (their **fair value**), and their ask sits
just above. The gap between them is the **spread**, and a market
maker makes money when the same shares trade through them in both
directions: buying low at the bid, selling high at the ask. They
provide a service to the rest of the market by always being there to
trade with — the rest of the market in turn provides the
back-and-forth buying and selling that fills both sides of the market
maker's quotes.

The market maker that ships with the exchange (`app/market_maker`) is
_static_. On startup, its `seed_book` function places a fixed ladder
of bids below the fair value and a fixed ladder of asks above, then
walks away. It does not look at the result of those submissions and
does not react to anything that happens afterward, so it never
notices when one side of its ladder is trading away faster than the
other.

A few more terms before we go further:

- **Long** means holding a positive number of shares — you've bought
  more than you've sold of a given symbol.
- **Short** is the opposite: you've sold more than you've bought, so
  your share count is negative.
- **Inventory** (or **position**) is that net share count. Filled
  buy orders add to it; filled sell orders subtract from it.
  Inventory of zero means everything has cancelled out and the
  market maker has no exposure to the symbol's price.

Holding a large position in either direction is risky: if the price
moves against the market maker before they can get back to zero
inventory, the loss can easily outweigh anything they earned from the
spread. So when a static market maker happens to be trading against
the rest of the market in a one-sided way — say, everyone else keeps
buying from it — the market maker just keeps selling and selling,
getting more and more short, while the broader price drifts upward.
Exactly the wrong combination.

A _dynamic_ market maker improves this by reacting to its fills. As
inventory grows in one direction, the market maker shifts the prices
it quotes in the opposite direction — making it less attractive for
others to keep trading the same way, and more attractive to trade
back. This shifting of quoted prices in response to inventory is
called **skewing** the quotes.

### What you're working with

Take a careful read of `app/market_maker/src/market_maker.ml` and its
`.mli` before you start. The current API is a single function:

```ocaml
val seed_book : Config.t -> Rpc.Connection.t -> unit Deferred.t
```

It submits each level of the ladder over an open RPC connection and
returns. There's no state, no event loop, no reaction to fills.

To make the market maker dynamic, you need:

1. A way for the market maker to know when it has been filled (so it
   can react). The session feed you built in Exercise 1 already
   delivers exactly that: every `Fill` event involving this
   participant (including fills against resting orders that were
   triggered by someone else's submission) lands on the session
   feed. Subscribe to it via `session_feed_rpc` and update inventory
   from the fills you observe. (There's also an `audit_log_rpc`,
   but that's intended for the exchange operator's monitoring
   tools — see `lib/gateway/src/rpc_protocol.mli`. A bot should use
   its session feed.)
2. A way for the market maker to remember which orders it currently
   has resting on the book so it can cancel them when it re-quotes.
   The client order IDs you introduced in Exercise 1 give you those
   identifiers directly — choose them when you submit and store them
   in a per-symbol structure.
3. The cancel RPC you built in Exercise 1.

The natural shape is a new function next to `seed_book`:

```ocaml
val run : Config.t -> Rpc.Connection.t -> unit Deferred.t
```

that returns a never-determined `Deferred.t` (i.e., `Deferred.never`). Internally it seeds
the initial ladder, subscribes to the session feed, and reacts to fills by cancelling
resting orders and re-posting.

### 2a: Track inventory and outstanding orders

Wire up a long-running market maker that subscribes to its session
feed and updates two pieces of internal state in response to events:

- An inventory counter per symbol. Every `Fill` event involving this
  market maker's participant adjusts it. If the market maker was the
  aggressor and bought, inventory goes up by the fill size; if it was
  the resting party on that same fill it instead sold the shares, so
  inventory goes down. Remember that a fill can involve the market
  maker as either party.
- The set of currently-resting client order IDs. Record the id from each
  `Order_accept` event that arrives on the session feed (read it as
  `request.client_order_id`; remember you chose it yourself before
  submitting). Remove the id on `Order_cancel`, or when a `Fill` consumes
  the full remaining size of the order — match the fill to your order using
  whichever of `aggressor_client_order_id` / `resting_client_order_id`
  corresponds to your side (the side whose `*_participant` is yours).

**Tests:**

Add a unit test that pushes a small sequence of events into
the market maker's event handler and asserts that the resulting
inventory and outstanding-orders state match what you expect. This is
much more reliable than eyeballing log output.

### 2b: Cancel and re-quote on every fill

Once the bookkeeping is correct, react to each `Fill`: cancel every
outstanding order on the side of the fill (or both sides, for
simplicity), and re-post a fresh ladder.

Use the cancel RPC from Exercise 1. Don't worry if some cancels fail
with "order not found" — the matching engine may have already filled
or removed the order. Silently ignore those errors.

**Tests:**

Add a unit test that drives `run` with a mock connection that records
each `submit_order_rpc` and `cancel_order_rpc` request, then injects a
`Fill` event against one of the bot's resting orders. Verify that the
recorded sequence is: an initial ladder of submits at startup, then
the cancels of those order IDs, then a fresh ladder of submits with
the same prices (since you haven't introduced the skew yet).

**Hints:**

- For 2b you don't need the skew yet — re-quote at the same prices as
  the original ladder. That isolates the cancel/re-quote machinery
  from the logic of the skew.

### 2c: Skew the quote ladder by inventory

Now use the inventory counter to shift the re-quoted ladder. The
simplest workable formula is:

```
skewed_fair = fair_value - (inventory * skew_cents_per_share)
```

When the market maker is long (positive inventory), `skewed_fair`
drops, which pulls both the bid and the ask down. Buyers in the
market are less likely to trade against the market maker's now-cheaper
bid, and sellers are more likely to trade against the market maker's
now-cheaper ask, so the next fills tend to bring inventory back
toward zero.

Add a new field to `Config.t`:

```ocaml
{ ...
; inventory_skew_cents_per_share : int
; ...
}
```

Tune it while watching a scenario run — too small and the market
maker accumulates inventory unchecked; too large and the market
maker's quotes drift away from any plausible trading range and it
stops getting filled at all.

**Tests:**

- Drive `run` with a mock connection that records submits and
  cancels, inject a `Fill` event, and verify the recorded submissions
  on the next iteration reflect the new skew.
- Inject alternating buy and sell fills and verify the market maker's
  quotes oscillate symmetrically around the configured fair value.

**Stretch:** Extend the market maker to quote multiple symbols and
skew based on _correlated_ exposure, not just per-symbol inventory. Add a
pairwise correlation matrix to the config (coefficients in
`[-1.0, 1.0]`) and compute "effective inventory" for symbol `X` as
`pos_X + sum_over_Y(corr_XY * pos_Y)`. A fill in any correlated
symbol can change effective inventory for several others, so a single
fill may need to trigger multiple re-quotes. Choosing the correlation
matrix sensibly (and updating it from observed prices) is its own
research problem — a flat config is a fine starting point.

---

## Exercise 3: Port the market maker to the bot framework

You now have a market maker that actually does something interesting,
but it's the only automated participant on the exchange. To produce a
realistic stream of activity — fills, cancels, BBO updates, trade
events — you'll want a handful of different bots running side by
side: the market maker that's already there, something randomizing
the incoming buying and selling, something that trades trends, and
so on.
Each one is its own program, but they all need the same machinery: an
RPC connection, a way to subscribe to events, a periodic callback to
do work as time passes, and a way to assemble several of them into named
scenarios.

That shared machinery lives in `Jsip_bot_runtime.Bot_runtime` and
`Jsip_scenario_runner`. Two concepts from those modules are worth
introducing up front:

- A **tick** is a fixed-interval callback. The bot framework calls
  each bot's `on_tick` function on a `Clock_ns.every`-style loop
  driven by the bot's configured `tick_interval`. Most bots use ticks
  to do periodic work that isn't event-driven (refreshing quotes,
  rolling stochastic dice for whether to submit anything this
  interval, etc.). Below, when we say "tick loop" we mean exactly
  this loop.

- The **fundamental** for a symbol is a hidden simulated "true
  value" that the **fundamental oracle**
  (`Jsip_fundamental.Fundamental_oracle`) maintains. The oracle
  changes the fundamental over time — gradually drifting, occasionally
  jolted by news events — and bots that need a price reference for
  their own decisions read it via `Context.fundamental`. The
  fundamental is _not_ the BBO; it's a synthetic ground-truth price
  that the rest of the simulation orbits around.

  This is a simplified stand-in for something real:
  participants in an actual market usually have their own beliefs about what
  a stock is "really worth" at any given moment, formed from
  whatever information they have (the company's financials, news,
  comparable companies, their own model). Those beliefs are
  private, they disagree with each other, and they change as new
  information arrives. A real exchange has no notion of a
  participant's fair value — but a simulated one can give every
  bot a single shared "true" value to anchor against. Our bots
  read it directly, which gives us a clean way to drive interesting market dynamics
  without modelling every participant's individual belief formation.

With those out of the way, take a careful read of:

- `lib/bot_runtime/src/bot_runtime.mli` — the `Bot` module type that
  every bot implements (`Config`, `on_start`, `on_tick`, `on_event`),
  plus the `Context` it operates against (oracle access, RNG, submit /
  cancel closures).
- `app/scenario_runner/src/scenario_config.ml` and `bot_spec.ml` —
  how a named scenario bundles together its symbols, its oracle
  config, any news events, and a list of bot specs.
- `app/scenario_runner/src/runner.ml` — the glue that opens one RPC
  connection per bot, logs each one in, subscribes the bot to its
  session feed and the relevant market-data streams, and starts its
  tick loop.

In this exercise you'll move your dynamic market maker onto the
`Bot_runtime.Bot` interface, which makes it composable with the other
bots you'll write in this part. Future scenarios will instantiate your
market maker alongside noise traders, momentum traders, news
injectors, and whatever else you build.

Before you start, you'll need to make two infrastructure changes that
let the bot runtime support the work you did in Exercise 1: the
runtime currently passes around exchange-assigned `Order_id.t`s, but
all client-facing identification now happens through
`Client_order_id.t`.

- **Update the `Context` and the `Bot` interface in
  `lib/bot_runtime/src/bot_runtime.{ml,mli}` to flow client order IDs
  end-to-end.** The runtime no longer needs to inject an order ID
  into the request — the bot picks one itself — so `Context.submit`
  just takes an `Order.Request.t` (which now carries the
  `client_order_id` field you added in Exercise 1d) and forwards it
  to `submit_order_rpc`. Change `Context.cancel` from
  `Order_id.t -> ...` to `Client_order_id.t -> ...`, and wire it to
  `cancel_order_rpc`. Bots can then store the client order IDs they
  chose at submission time and pass them straight back to cancel.

- **Update `start_bot` in `app/scenario_runner/src/runner.ml` to log
  in and subscribe to the session feed.** Today it opens an RPC
  connection and (optionally) subscribes to market data; extend it
  so that for every bot it (a) dispatches `login_rpc` with the
  bot's participant before anything else, (b) dispatches
  `session_feed_rpc` and pipes the resulting events into
  `Bot_runtime.feed_event` alongside the market-data feed (use
  `Pipe.interleave_pipe` or two `Pipe.iter`s inside `don't_wait_for`s), and (c)
  replaces the cancel stub with a real
  `Rpc.Rpc.dispatch_exn Rpc_protocol.cancel_order_rpc` call. The
  bot module's `on_event` will then receive its own `Order_accept`,
  `Fill`, `Order_cancel`, and `Order_reject` events the same way it
  receives BBO and trade reports.

**What to build:**

1. In `app/market_maker/src/`, add a module — call it
   `Market_maker_bot` — that satisfies
   `Jsip_bot_runtime.Bot_runtime.Bot`. The runtime already supplies
   the participant identity, an RNG, the fundamental oracle, and
   submit/cancel functions, so drop those from your `Config.t` and
   read them from `Context` instead.
2. Map your existing logic onto the three callbacks:
   - The work currently done by your `run` loop's "seed the initial
     ladder" step goes in `on_start`, which the runtime invokes
     exactly once before the tick loop or any events fire.
   - `on_tick` runs your periodic refresh logic (if any) — e.g., recomputing
     the skewed fair value off the oracle on a slow clock so the
     ladder drifts with the fundamental even when nothing has filled.
     Bots that only re-quote in response to fills can leave this empty.
   - The fill-handling logic (inventory update, cancel outstanding
     orders, re-post a skewed ladder) goes in `on_event`. The bot
     runtime forwards everything from the session feed and the
     symbol's market-data feed to `on_event`: market data events,
     order-lifecycle events for this bot's submissions, and `Fill`
     events involving this bot — exactly the events your `run`
     loop was already consuming, just delivered through the bot
     framework instead of a hand-rolled subscription.
3. Delete the old `Market_maker.seed_book` and your dynamic `run` —
   the bot module replaces both, and the dummy
   `-seed-market-maker` flag in `app/server/bin/main.ml` no longer
   has anything useful to do once the dynamic maker exists. Update
   the server binary accordingly.

**Hints:**

- For per-symbol state (inventory, outstanding orders, "have I
  posted yet?"), use a `Symbol.Table.t`.
- The client order IDs you introduced in Exercise 1 give you a
  predictable namespace for the orders you submit, so picking IDs is
  straightforward — just keep a counter per symbol on the bot side.

**Tests:** Add a unit test that wires up your bot via
`Bot_runtime.For_testing.context_of` with mock `submit` / `cancel`
closures (the existing `app/bots/test/test_bots.ml` already shows the
recording-closure pattern). Verify that ticking the bot once produces
the expected ladder of `Order.Request.t`s, and that injecting a `Fill`
event causes the bot to cancel and re-quote with a skewed ladder.

---

## Exercise 4: Build a noise trader

Real markets see a huge amount of buying and selling that isn't
trying to predict the direction of the price at all. Retail traders
rebalancing a 401(k), an index fund following a published benchmark,
a corporation liquidating shares from an acquisition — none of those
participants have a view on whether the stock is about to go up or
down; they simply have shares to buy or sell for reasons unrelated to
short-term price moves. From the matching engine's point of view that
activity is indistinguishable from random buying and selling. It's so
ubiquitous that academics have a name for it: **noise**, in contrast
to the **informed** orders from participants who do have a price
view.

A **noise trader** in our simulation stands in for all of that
real-world non-informed activity. It doesn't try to make money. It
picks a side, a size, a price, and a time-in-force more or less at
random and submits an order. Together with the market maker, it gives
the matching engine something to actually do — fills happen, the BBO
updates, trade events go out, and the other bots you'll build in this
part have something to observe and react to.

Because the noise trader is a stand-in for many different
participants, it doesn't make sense to give it a single behavior
pattern. Real participants submit a wide variety of orders: small
marketable IOC orders
(impatient traders willing to pay the spread for an immediate fill),
larger resting day orders (someone laying out a target buy or sell
price and waiting), and so on. Mirror that variety: have the bot
randomize the time-in-force along with everything else.

**What to build:**

In `app/bots/src/noise_trader.ml`, implement a
`Jsip_bot_runtime.Bot_runtime.Bot` with a config that controls:

- The list of symbols to trade.
- A mean size. Each individual order's size is drawn randomly from a
  small range around this mean (so the bot doesn't always submit the
  same number of shares).
- A `tick_chance` in `[0.0, 1.0]` — probability per tick that the bot
  sends any order at all. Lets you run `on_tick` on a fast clock and
  still produce sparse activity.
- An `aggressiveness_pct` — probability that a given order is
  marketable (crosses the spread and trades immediately) vs. priced
  away from the best price on its side (so it would rest in the
  book).
- An `ioc_pct` — probability that an order is submitted as `Ioc`
  versus `Day`. Resting `Day` orders pile up on the book, which is
  desirable for later exercises.

The `on_tick` callback should:

1. Draw a uniform random number in `[0.0, 1.0]` and return without
   doing anything if it exceeds `tick_chance`.
2. Pick a symbol uniformly from the config list.
3. Pick a side uniformly (buy or sell).
4. Pick a size randomly around the configured mean.
5. Pick a price: with `aggressiveness_pct` probability, quote at the
   opposite best price plus a few cents past it (so the order is
   marketable); otherwise quote a few cents away from this side's
   best price (so it would rest). If the book is empty, fall back to
   the fundamental from the oracle.
6. With `ioc_pct` probability submit as `Ioc`; otherwise submit as
   `Day`.

The bot will need to know the current best bid and best ask to pick
its prices, but `Bot_runtime` deliberately does not track BBOs for
you — every strategy uses market data differently, so the runtime
leaves that bookkeeping to each bot. Use `on_event` to maintain a
small per-symbol BBO cache, updating it from `Best_bid_offer_update`
events.

**Hints:**

- `Context.random` gives you a `Splittable_random.t`. Use it for
  every random choice so the scenario remains reproducible from its
  seed.
- A `Symbol.Table.t` works well for the BBO cache.

**Tests:** Use `make_recording_bot` in `app/bots/test/test_bots.ml` to
drive the noise trader through several ticks, then `print_submitted`
the recorded requests. Pin down the seed so the test is deterministic,
and verify that the mix of buy/sell, the size distribution, and the
share of marketable orders look right.

---

## Exercise 5: Wire up the calm-day scenario

`Calm_day.configure` (in `app/scenarios/src/calm_day.ml`) is currently
a stub that raises. In this exercise you'll fill it in: one market
maker plus one noise trader, trading a single symbol, with a calm
fundamental price process.

Each scenario lives in its own module under `app/scenarios/src/`,
satisfies `Scenario.S` (see `scenario.mli` in that directory), and
is registered in `jsip_scenarios.ml`'s `all` list — so a new
scenario is just a new `.ml` file plus one line in that registry.
The runner's `-scenario` flag automatically picks up every scenario
in `all`.

**What to build:**

1. Open `app/scenarios/src/calm_day.ml` and replace the
   `failwith "TODO: ..."` in `configure` with a real
   `Scenario_config.t`:

   - Pick a symbol (e.g. AAPL).
   - Build a `Fundamental_oracle.Config.t` (which is a
     `Symbol.Map.t` of `symbol_config` records) with one entry for
     your symbol — give it modest volatility (~3 cents/sec) and a
     small mean-reversion strength (~0.05). See `test_bots.ml` for
     a worked example of constructing one.
   - Leave `news = []`.
   - Build a `Bot_spec.t list` containing one market-maker bot and one
     noise trader.

2. Look at `Bot_spec.t` in `app/scenario_runner/src/bot_spec.ml` —
   each spec wraps a `(module Bot)` together with the bot's
   `Config.t`, participant, RNG seed, and tick interval.

3. Build with `dune build` and run end-to-end:

   ```sh
   dune exec app/scenario_runner/bin/main.exe -- -scenario calm-day
   ```

   then in a second terminal:

   ```sh
   dune exec app/monitor/bin/main.exe
   ```

   You should see a continuous stream of `BBO`, `ACCEPTED`, `FILL`,
   and `TRADE` events scroll past in the monitor.

**Hints:**

- Use the bonsai_term monitor's filter toggles and substring filter to
  drill into specific event categories or specific symbols.
- If you see no fills at all, you have have a bug, or your market-maker spread is too
  wide for the noise trader's aggressiveness. Try tightening
  `half_spread_cents` or raising `aggressiveness_pct`.
- If the book never fills up, it's possible your noise trader's `tick_chance` is too
  low or the market maker's `num_levels` is too small.

---

## Exercise 6: Build a momentum trader

When a stock starts moving in one direction in real markets,
it often keeps moving in that direction for a while — at least on
short time scales. The intuition is that whoever was eager enough to
push the price up by, say, ten cents in the last minute is usually
not the only person with that view, and others reacting to the same
information (an earnings rumour, a news headline, a rival's price
move) tend to pile in over the next few minutes. "Trend-following" or
"momentum" strategies are an entire family of real trading systems
that try to identify and ride those moves, ranging from a single
analyst eyeballing a chart to large quantitative funds that scan
thousands of stocks for fresh-looking trends.

A **momentum trader** in our exchange is a stripped-down version of
that idea: it watches the recent sequence of trades on the public
market-data feed and, when prices have been moving consistently in
one direction, it places its own order in the same direction. This
is your first taste of a state-tracking bot — the strategy lives
across many events, not just in a snapshot of the current world.

**What to build:**

In `app/bots/src/momentum_trader.ml`, implement a bot whose
`on_event` keeps a sliding window of the most recent `Trade_report`
events (the public trade-event broadcast that every subscriber sees).
On `on_tick`, look at the window:

- `signal = most_recent_trade_price - earliest_trade_price_in_window`.
  If the window has fewer trades than its capacity, do nothing yet.
- If `|signal| < threshold_cents`, do nothing.
- Otherwise submit an `Ioc` in the same direction as the signal (buy
  when prices have risen, sell when they've fallen), sized
  proportionally to the magnitude of the signal.

The hard part is the bookkeeping: a fixed-length ring of the last N
trade prices, kept fresh as trades arrive.

**Config:** the bot should be configurable along (at least) these
dimensions:

- The symbol it watches and trades.
- The capacity of its sliding window — how many recent trades to
  hold on to. A bigger window smooths the signal but is slower to
  react to genuine changes.
- A signal threshold in cents — the minimum recent price move
  before the bot will submit an order. Tunes how confident the bot
  has to be before it trades.
- An upper bound on the size of any single order, so a very strong
  signal doesn't translate into an unreasonably large submission.

**Hints:**

- Use `Trade_report`, not `Fill` — the runtime only delivers `Fill`
  events that involve this bot's own participant, but `Trade_report`
  is broadcast to every subscriber.
- The bot's reactivity comes from `on_event` mutating the ring;
  `on_tick` reads it and decides whether to trade.

**Tests:** feed a sequence of fake `Trade_report` events (using the recording
bot scaffold) and verify that the bot's `on_tick` submits orders in
the expected direction once the signal exceeds the threshold, and
that the signal decays once the ring rolls over.

---

## Exercise 7: Build the earnings-shock scenario

In real markets, prices don't only move in continuous, gradual drifts
— they sometimes jump abruptly when new information arrives. The
classic example is an earnings report: a public company is required
to publish a quarterly summary of its financial results, and that
report often contains numbers that surprise the market. If the
reported profit is much higher than what analysts expected, the stock
will trade meaningfully higher (often more than ten percent) almost
immediately after the next opportunity to trade — sometimes in a
single trade, sometimes over a rapid burst of many trades as buyers
and sellers find the new price. Other news has the same effect: a
regulator approves (or rejects) a drug, a CEO resigns, a merger is
announced, a government statistic surprises traders.

These jumps are particularly hard on market makers. A market maker
who posted quotes a moment before the news lands now has a bid
sitting above the new fair value (or an ask sitting below it), so
the rest of the market trades through them and the market maker
takes a loss before they can react. Most market-making firms invest
heavily in detecting news fast and pulling their quotes before
getting hit. Momentum traders, on the other hand, often love these
moves — once the jump has started, following it is the whole point.

`Earnings_shock` (in `app/scenarios/src/earnings_shock.ml`) simulates
this: a single positive shock to the fundamental price, with a market
maker (which will get caught flat-footed), a noise trader (background
activity), and a momentum trader (which should chase the jump) all
running side-by-side.

**What to build:**

In `app/scenarios/src/earnings_shock.ml`, fill in `configure`:

1. One symbol, one oracle entry with moderate volatility.
2. A `News_injector.Event.t` list with one entry: at, say, 15 seconds
   in, apply a `+500` cent jump to the symbol with a description like
   `"AAPL earnings report — stock spikes"`.
3. Bots:
   - A market maker (will get run over by the news event — that's the
     point).
   - A noise trader.
   - A momentum trader.
   - Optionally, a mean reverter from the list below (which should
     bet the jump overshoots).

**What to watch for:**

- The fundamental jumps cleanly at the scheduled offset
  (`News_injector` logs the description to stdout).
- The market maker's quotes lag because they're driven by the
  fundamental — there should be a brief window where the market
  maker's bids sit above the new post-jump fundamental and get
  traded against quickly, generating a flurry of fills.
- The momentum trader should fire shortly after, chasing the move.

**Hints:**

- `Time_ns.Span.of_sec` builds the offset.
- The `News_injector` log line goes to stdout. The scenario runner
  doesn't print exchange events itself (it leaves that to the
  monitor), so the news log shouldn't be drowned out — but you'll
  want the monitor running in a second terminal to watch the
  matching-engine reaction in real time.
- If your market maker doesn't react to the new fundamental price,
  check that its `on_event` (or its tick logic) recomputes the
  ladder using `Context.fundamental` (not a cached value).

---

## Choose your own adventure: more bots

The four linear exercises above give you a working ecosystem with two
to three bots. The rest of Part 2 is open-ended: pick from the list
below (or come up with your own) and add at least one more bot to the
project. Each is a self-contained `Bot` module under `app/bots/src/`.

- **Mean reverter.** Watches the mid-price relative to the fundamental.
  When the mid drifts far above the fundamental, sell; far below, buy.
  IOC orders only, sized for opportunism. Tunable parameters:
  `threshold_cents`, `size`. The mean reverter expects price to revert
  — earnings-shock-style scenarios will punish a naive implementation.

- **Whale.** Occasionally submits very large IOC orders that sweep
  through multiple levels of resting liquidity, then goes quiet. Per-tick
  probability gates the activity, so most ticks do nothing. Tunable:
  `mean_size`, `per_tick_chance`, `sell_pct`. Pair with a flash-crash
  scenario (see below).

- **Pairs trader.** Holds two correlated symbols and trades the spread:
  if symbol A is rich relative to its correlation with B, sell A / buy
  B; if cheap, the opposite. Needs config for the correlation
  coefficient. This is the bot whose existence the multi-asset stretch
  goal of Exercise 2c hints at.

- **Time-of-day quoter.** A market maker that widens its spread (or
  goes flat) during a configurable "off-hours" window. Useful for
  exploring how a scenario looks when liquidity drops.

- **Retail-mimicking bot.** Trades only at round prices (whole-dollar
  increments), small sizes, slow tick rate. Adds plausible texture to
  scenarios.

- **Adversarial bot.** Designed to exploit a specific weakness in another bot. The most
  interesting target is the market maker. Have the bot watch for the market maker's ladder
  of resting orders, then submit a burst of IOC orders that trade against several levels
  at once — all on the same side. This first step is intentionally expensive: the
  adversary is crossing the spread and taking on inventory. The bet is that the market
  maker's inventory skew is predictable and overreacts. After the sweep leaves the maker
  with a one-sided position, the maker skews its quotes to buy back or sell down
  inventory. The adversary then tries to sell the shares it just bought against those
  skewed quotes at a better price than the first step, completing a round trip whose
  profit comes from the maker's mechanical response rather than from a move in the
  fundamental. This is an example of _adverse selection_, an important consideration for
  any real-world trading strategy: do the people you're trading with have additional
  information or insight that makes the trade more favorable for them (in this case,
  knowing ahead of time how the market maker will respond).

For each bot you add: implement the `Bot` module, write a recording
test that pins down its behavior under a fixed seed, and add it to at
least one scenario.

---

## Choose your own adventure: more scenarios

- **Active day.** Fill in `Active_day.configure` (in
  `app/scenarios/src/active_day.ml`) with multiple symbols, multiple
  market makers (one per symbol), and a higher-throughput noise
  trader.

- **Flash crash.** Fill in `Flash_crash.configure` (in
  `app/scenarios/src/flash_crash.ml`): a tight sequence of large
  negative news shocks delivered over a few seconds, plus a whale
  heavily biased toward selling. Several real-world events have
  looked like this. A common trigger is a single large participant —
  a fund liquidating a position, or a broker that has to sell
  because a leveraged client's collateral fell below a required
  threshold — dumping a big position quickly. Other participants who
  hold the same stock see the price falling and start selling too in
  order to limit their own losses; market makers widen their quotes
  or stop trading altogether to avoid catching the falling knife.
  The result is a cascade: a few seconds of accelerating selling,
  very thin liquidity, and prices far below where they were minutes
  earlier. Suggested news event descriptions: `"large fund
liquidation"`, `"stop-loss cascade"`, `"dealers pull quotes"`.
  Watch the cascade unfold in the monitor.

- **Quiet then chaotic.** Start with a calm-day shape, then schedule a
  cluster of news events around the 30-second mark. Useful for
  watching bots' response latency.

- **Capacity stressor.** Crank `tick_chance` and `mean_size` until the
  matching engine is the bottleneck. (You'll come back to thinking about how the exchange can stay fast and stable in conditions like these in later parts.)

Each scenario lives as its own module under `app/scenarios/src/`
implementing `Scenario.S` (a [name], a [description], and a
[configure : unit -> Scenario_config.t]). To add a brand-new
scenario: drop a new `.ml` file into the directory, then add one
line to `jsip_scenarios.ml`'s `all` list — it'll show up
automatically in `scenario-runner -scenario`'s help text.

---

## Stretch: separate the system components into independent processes

Right now the exchange, every bot, and the news injector all run in
a single OS process. The bots open RPC connections to the exchange,
but those connections are loopback only — there's no real network
between them. Pull each bot out into its own process (a separate
binary that takes the bot's `Config.t` on the command line, opens an
RPC connection to a separately-started exchange server, and runs the
same `Bot_runtime` loop). A production trading system looks much
more like this: the matching engine is one process, the gateway is
another, each trading firm runs its own bot processes, and they all
talk via real network protocols. Once the bots are independent, you
can extend the split further — pull the gateway out of the matching
engine, for instance, so the matching engine talks to the gateway
over an internal RPC and the gateway is the only thing exposed to
external clients.

---

<a id="stretch-real-authentication"></a>

## Stretch: real authentication

The login from Exercise 1a only takes a participant name on trust:
any client can call `login_rpc "Alice"` and the server will accept
it as long as nobody else is currently logged in as Alice. That's
fine for a teaching simulation but obviously wouldn't fly on a
real exchange, where the consequences of impersonating another
participant include "spending their money".

Pick a plausible authentication scheme and wire it in. Some
options, in roughly increasing order of fidelity:

- **Pre-shared secrets**: the exchange has a hard-coded map from
  participant name to a secret string; the login RPC takes
  `(name, secret)` and rejects mismatches. The map could live in
  a config file the server reads at startup.
- **Per-connection challenge-response**: on connect, the server
  sends a random nonce; the client signs it with a private key
  whose corresponding public key the server knows for that
  participant. Use any signing library you like (Ed25519 via
  `tls-async` or `mirage-crypto`, for instance).
- **TLS client certificates**: terminate the RPC over TLS and pull
  the participant identity out of the cert. Most production
  exchanges use something in this family. Async RPC supports TLS
  connections — see `Async_extra.Tls_async` or
  `Rpc.Connection.client` with a TLS-wrapped reader/writer.

Whatever you pick, the principle is the same: identity is
established by something the client _has_ (a key, a certificate)
rather than something they can simply claim. Don't store secrets
in plaintext — at minimum hash them at rest, ideally use one of
the schemes above that doesn't put the secret on the wire at all.
