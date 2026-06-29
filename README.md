# JSIP Exchange

A simplified stock exchange built in OCaml. Over the course of this project
you will extend and improve every layer of the system — from the core data
structures to the network protocol.

## What is an exchange?

An exchange is a marketplace where buyers and sellers meet to trade financial
instruments (stocks, bonds, etc.). The exchange doesn't buy or sell anything
itself — it _matches_ buyers with sellers.

When a participant wants to buy 100 shares of AAPL[^1] at $150.00, they send an
**order** to the exchange. If there's already a seller willing to sell at
$150.00 or less, the exchange **fills** the order -- a trade happens. If not,
the order **rests** on the **order book**, waiting for a compatible seller to
arrive.

The order book is the central data structure. It has two sides:

- **Bids** (buy orders): sorted from highest price to lowest. The highest bid
  is the "best bid" — the most someone is currently willing to pay.
- **Asks** (sell orders): sorted from lowest price to highest. The lowest ask
  is the "best ask" — the least someone is currently willing to accept.

The difference between the best bid and the best ask is the **spread**. When
an incoming order's price crosses the spread (a buyer willing to pay at least
the best ask, or a seller willing to accept at most the best bid), a trade
occurs.

The state of a market is often shorthanded as the **best bid or offer** or **BBO**, which captures the current best prices one can buy or sell.

## Architecture

The system is organized into layers, each building on the one below:

| Layer                 | Directory                                                                                                         | Key modules                                                                                                 |
| --------------------- | ----------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------- |
| Applications          | `app/server`, `app/client`, `app/market_maker`, `app/bots`, `app/scenarios`, `app/scenario_runner`, `app/monitor` | Server and client binaries, the seed market-maker, bots, named scenarios, scenario CLI, bonsai_term monitor |
| Bot ecosystem         | `lib/bot_runtime`, `lib/fundamental`, `lib/news_injector`                                                         | Bot scaffolding, simulated fundamental prices, scripted news shocks                                         |
| Gateway               | `lib/gateway`                                                                                                     | Facilitates client-exchange communication                                                                   |
| Order Book & Matching | `lib/order_book`                                                                                                  | Keeps track of orders and executes trades                                                                   |
| Core Types            | `lib/types`                                                                                                       | `Side`, `Price`, `Size`, `Symbol`, `Order`, `Fill`, `Level`, `Bbo`, `Book`, etc.                            |
| Test Harness          | `lib/test_harness`                                                                                                | Testing infrastructure                                                                                      |

### Core Types (`lib/types/src/`)

The fundamental data types used everywhere:

| Module           | Purpose                                                                                                   |
| ---------------- | --------------------------------------------------------------------------------------------------------- |
| `Side`           | `Buy` or `Sell`                                                                                           |
| `Price`          | Fixed-point price in integer cents                                                                        |
| `Size`           | Order quantity (thin wrapper around `int` for clarity)                                                    |
| `Symbol`         | Trading instrument identifier (e.g., "AAPL")                                                              |
| `Participant`    | Anyone who can send orders, identified by a unique string name                                            |
| `Order_id`       | Unique identifier assigned by the matching engine                                                         |
| `Time_in_force`  | How long an order stays active: `Day` or `Ioc`                                                            |
| `Order`          | An order: `Request` (before submission) and live `Order` (with mutable remaining size)                    |
| `Fill`           | A trade execution: price, size, and both sides                                                            |
| `Level`          | A price level: price + aggregate size (shared by `Bbo` and `Book`)                                        |
| `Bbo`            | Best bid and offer: the best `Level` on each side                                                         |
| `Book`           | Read-only book snapshot with levels and BBO (returned by the book query RPC)                              |
| `Exchange_event` | Everything the engine produces: order acceptances, fills, cancels, rejections, BBO updates, trade reports |
| `Cancel_reason`  | Why an order was cancelled                                                                                |

The `Time_in_force` module controls how long an order stays active. `Day`
orders rest on the book until the end of the trading day — if not filled,
they are cancelled at market close. `Ioc` (Immediate or Cancel) orders
attempt to fill immediately against whatever liquidity is available; any
unfilled portion is cancelled right away and never rests on the book.

### Order Book & Matching Engine (`lib/order_book/src/`)

| Module            | Purpose                                                                                                  |
| ----------------- | -------------------------------------------------------------------------------------------------------- |
| `Order_book`      | Per-symbol book with bid and ask sides. Supports add, remove, find, and `find_match`.                    |
| `Matching_engine` | Maintains one book per symbol. `submit` assigns an order ID, runs the matching loop, and returns events. |

**The matching loop**: When a new order arrives, the engine repeatedly calls
`Order_book.find_match` to find a compatible resting order. For each match, it
fills both sides (reducing remaining size), removes fully-filled resting
orders from the book, and emits `Fill` and `Trade_report` events. After the
loop, Day orders with remaining size rest on the book; IOC remainders are
cancelled.

`Matching_engine.submit` runs the full matching loop synchronously and
returns the event list. Over RPC, the `Exchange_server` queues each
incoming request into a bounded `Pipe`, and a background task drains the
pipe, calls `Matching_engine.submit`, and hands the resulting events to
the `Dispatcher` for routing. Clients get backpressure for free (the
queue is bounded) and the matching engine never blocks on slow network
I/O.

**Known limitation**: The current `find_match` implementation is deliberately naive -- it
returns the _first_ tradable order it finds in the list, not the _best-priced_ one. See
the "Price priority" test in `lib/order_book/test/test_matching_engine.ml` for a
demonstration of this bug. As you work on this project, fixing this will be one of the exercises.

### Gateway (`lib/gateway/src/`)

The gateway sits between clients and the matching engine. It handles
protocol parsing (translating text commands into order requests),
network communication (RPC server/client), and event distribution
(routing BBO updates, trade reports, fills, and order-lifecycle events
to the right subscribers).

| Module            | Purpose                                                                                                                                                                                                                                         |
| ----------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `Protocol`        | Parses text commands (`BUY AAPL 100 150.00 as Alice`) and formats events as text                                                                                                                                                                |
| `Exchange_server` | Embeddable server: bundles the matching engine, the bounded request queue, the dispatcher, and the RPC implementations                                                                                                                          |
| `Rpc_protocol`    | Defines the Async RPCs for client-server communication                                                                                                                                                                                          |
| `Dispatcher`      | Central event router: keeps subscription registries for market data (per symbol), the audit firehose, and per-participant sessions, and routes each event to the right subscribers                                                              |
| `Session`         | A logged-in client's outbound event channel — a participant identity plus a bounded pipe of events. The session feed RPC that exposes this pipe is a week-2 exercise; for now the dispatcher prints session-bound events on the server's stdout |

### Bot ecosystem (`lib/bot_runtime/`, `lib/fundamental/`, `lib/news_injector/`)

These libraries support the "bot ecosystem": a set of automated
participants that trade against the exchange to produce interesting
market behavior for scenarios and visualizations. The exchange itself
does not depend on them — they live alongside the matching engine, not
inside it.

| Module                                   | Purpose                                                                                                                                                                               |
| ---------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `Bot_runtime` (`lib/bot_runtime`)        | Scaffolding for a single bot: tracks its view of the world (BBOs, inventory, fundamental price), runs an `on_tick` callback on a clock, and dispatches exchange events to `on_event`. |
| `Fundamental_oracle` (`lib/fundamental`) | A per-symbol Ornstein-Uhlenbeck price process. Supplies a "true price" trajectory that bots and scenarios can anchor against. Reproducible from a seed.                               |
| `News_injector` (`lib/news_injector`)    | Schedules pre-configured shocks (earnings surprises, flash crashes) against the `Fundamental_oracle` at fixed offsets from a scenario's start.                                        |

Bots talk to the exchange through the same RPC interface that any
external client would use — `Bot_runtime.create` takes `submit` and
`cancel` closures, and the scenario runner wires them to
`Rpc_protocol.submit_order_rpc` over a local connection.

### Applications (`app/`)

The `app/` directory contains runnable binaries that compose the
libraries into complete programs.

| Application           | What it does                                                                                                                                                                                                                                |
| --------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `app/server`          | Exchange server that listens for RPC connections on a TCP port. Supports `-seed-market-maker` (pre-seed the book) and `-trade-back-and-forth` (two MMs trading in a loop to generate sustained traffic).                                    |
| `app/client`          | Interactive client that connects to the server. Supports `BUY`, `SELL`, `BOOK`, and `SUBSCRIBE` commands.                                                                                                                                   |
| `app/market_maker`    | Library for a bot that seeds the book with resting orders around a fair value.                                                                                                                                                              |
| `app/bots`            | Library where trading bots live. One module per bot; currently empty — we'll be adding bots as we build out the exchange.                                                                                                                   |
| `app/scenarios`       | Library where named scenarios live. One module per scenario (`Calm_day`, `Active_day`, `Earnings_shock`, `Flash_crash`); each satisfies `Scenario.S` and is registered in `Jsip_scenarios.all`.                                             |
| `app/scenario_runner` | CLI that picks a scenario from `Jsip_scenarios`, starts a server, instantiates a `Fundamental_oracle`, schedules `News_injector` events, and starts the scenario's bots.                                                                    |
| `app/monitor`         | Bonsai_term TUI (text-based user interface — a styled terminal app, similar in spirit to `htop` or `vim`): subscribes to the exchange's audit log and renders a filterable, color-coded stream of every event the matching engine produces. |

### Test Harness (`lib/test_harness/src/`)

Shared infrastructure for all tests:

- **`Harness`**: Constants (`aapl`, `tsla`, `goog`, `alice`, `bob`,
  `charlie`, `market_maker`), order builders (`buy`, `sell`), printing
  helpers (`print_book`, `print_bbo`, `print_event`, `print_events`),
  output filtering via `Show.all` / `Show.no_market_data` /
  `Show.only`, quiet variants (`submit_quiet`, `submit_quiet_`) that
  skip the auto-print, and a `sample_events` list (one of each
  `Exchange_event.t` variant) for tests that need stable hand-built
  events.
- **`E2e_helpers`**: Helpers for async end-to-end tests that spin up a
  real server on an OS-assigned port: `with_server`, `connect_as`,
  `connection`, `rpc_submit`, `rpc_book`. The participant-targeted
  events triggered by an `rpc_submit` currently surface as `[for
<participant>]` lines on stdout, since the session feed RPC isn't
  wired up yet — once it is, `rpc_submit` will drain those events from
  the session feed and return them.

## Building and running

```sh
# Build everything
dune build

# Run all tests
dune runtest

# Format the code
dune fmt

# Run the server and client (in separate terminals):

# Run the exchange server with a market maker pre-seeding the book
dune exec app/server/bin/main.exe -- -port 12345 -seed-market-maker

# Or run two market makers trading back and forth, for sustained traffic
dune exec app/server/bin/main.exe -- -port 12345 -trade-back-and-forth

# Run an interactive order-entry client
dune exec app/client/bin/main.exe -- -port 12345 -name Alice

# Boot a named scenario (exchange + bots + simulated news) on one process.
# NOTE: the named scenarios are currently TODO stubs; filling them in is
# part of the project, so this will raise until they're implemented.
dune exec app/scenario_runner/bin/main.exe -- -scenario calm-day -port 12345 -seed 0

# Watch the exchange's audit log in a filterable TUI
dune exec app/monitor/bin/main.exe -- -host localhost -port 12345
```

### Client commands

```
BUY AAPL 100 150.00              Buy 100 shares at $150.00 (Day order)
SELL TSLA 50 200.00 IOC          Sell 50 shares IOC
BUY AAPL 100 150.00 as Bob       Specify participant name
BOOK AAPL                        Show the order book
SUBSCRIBE AAPL                   Stream market data updates
```

### What you'll see when you submit orders

The exchange does not yet have a way to push participant-targeted events
(acceptance, fills, cancellations, rejections) back to a specific client
— wiring up the session feed RPC and the login flow it depends on is a
week-2 exercise. The `Session` module and the dispatcher's routing logic
already exist; what's missing is the RPC that hands a session's pipe
back to its owner.

For now, the `Dispatcher`'s `push_to_session` stub prints those events
on the server process's stdout, prefixed with `[for <participant>]`. Run
the server in one terminal so you can see them as they happen.

Public market-data events (BBO updates and trade reports) _do_ already
have a real push channel: use the `SUBSCRIBE <symbol>` command in the
client to attach a per-symbol stream so you see the public side of
the exchange's responses to your orders.

## Testing

Every test in the project is a `let%expect_test`, but they come in a few
flavors depending on how they check correctness:

- **Output-comparison tests**: run a scenario, print output to
  stdout, and compare against expected output embedded in a `[%expect]` block
  in the source file. Good for testing complex interactions where the output
  tells a story (e.g., matching scenarios, book state). If the output changes,
  the test fails and shows you a diff. Run `dune promote` to accept new output.

- **Assert-based tests** (`[%test_result]`): check that a value
  equals an expected value directly, without printing. A `let%expect_test`
  doesn't need a `[%expect]` block — if the body only asserts and prints
  nothing, an empty (silent) run is a pass. Good for simple value-level checks
  (e.g., "this function returns 42"). On failure, `[%test_result]` shows the
  expected and actual values as _sexps_ (s-expressions — Lisp-style
  parenthesized text like `((symbol AAPL) (price 150))`, OCaml's standard way
  to print a structured value as text). In some cases we want to assert that a
  function raises or doesn't raise an exception in a particular scenario, and
  for that we use `require_does_raise` or `require_does_not_raise` from
  `Expect_test_helpers_core`.

- **Protocol-shape tests** (`lib/gateway/test/test_rpc_shapes.ml`): a special use of
  expect tests that pins each RPC's serialization digests — short hex fingerprints
  computed from the byte layout of every type the RPC sends. The serialization library
  we use is called `bin_io` (binary I/O), and `[@@deriving bin_io]` on a type is what
  asks the compiler to generate the encoding functions. Instead of fingerprinting
  program behavior, these tests fingerprint the _protocol_: a digest changes only when
  a type's byte layout changes — a new field, a new variant, or an RPC pointed at a
  different type. They're the precise statement of "what bytes go over the network."
  When you extend the protocol, update this file (add a block for each new RPC) and
  `dune promote` once you've confirmed an intended change moved a digest.

```sh
# Run tests
dune runtest

# If an expect test fails with new (correct) output, promote it
dune promote
```

### Test organization

| Test file                                         | What it tests                                                                         |
| ------------------------------------------------- | ------------------------------------------------------------------------------------- |
| `lib/types/test/test_side.ml`                     | Side flip, sign, marketability, parsing                                               |
| `lib/types/test/test_price.ml`                    | Price construction, arithmetic, formatting, comparison                                |
| `lib/types/test/test_symbol.ml`                   | Symbol construction and validation                                                    |
| `lib/types/test/test_order_id.ml`                 | Order ID generation and sequencing                                                    |
| `lib/types/test/test_time_in_force.ml`            | Time-in-force parsing and `rests_on_book`                                             |
| `lib/types/test/test_order.ml`                    | Order creation, fill mutation, validation                                             |
| `lib/types/test/test_fill.ml`                     | Fill notional value calculation                                                       |
| `lib/order_book/test/test_order_book.ml`          | Book add/remove/find, best price queries, find_match                                  |
| `lib/order_book/test/test_matching_engine.ml`     | Full matching scenarios, IOC, multi-symbol, market data events                        |
| `lib/gateway/test/test_protocol.ml`               | Command parsing, error handling, event formatting                                     |
| `lib/gateway/test/test_end_to_end.ml`             | Async end-to-end: real server, RPC clients, market data subscriptions                 |
| `lib/gateway/test/test_rpc_shapes.ml`             | RPC wire contract: each RPC's name, version, and bin_io shape digests of its types    |
| `lib/fundamental/test/test_fundamental_oracle.ml` | Oracle determinism from seed, mean reversion, news shocks                             |
| `lib/news_injector/test/test_news_injector.ml`    | Scheduled shock delivery against a `Fundamental_oracle`                               |
| `lib/bot_runtime/test/test_bot_runtime.ml`        | BBO and inventory state tracking, event dispatch                                      |
| `app/market_maker/test/test_market_maker.ml`      | Market maker book seeding, trading against the market-maker                           |
| `app/bots/test/test_bots.ml`                      | Scaffolding for bot tests (recording submit/cancel against a mock context)            |
| `app/monitor/test/test_event_log.ml`              | Event log model: filters (category, substring, combine), color mapping, BBO snapshots |
| `app/monitor/test/test_controller.ml`             | Monitor controller state machine: key handling, filter chips, substring edit mode     |

### Benchmarks

The project includes benchmarks for the order book and matching engine
(`lib/order_book/bench/bench_order_book.ml`).

```sh
# Run benchmarks (takes ~4 minutes with default quota)
dune exec lib/order_book/bench/bench_order_book.exe -- -ascii -quota 5

# Quick run (shorter quota, less stable results)
dune exec lib/order_book/bench/bench_order_book.exe -- -ascii -quota 1
```

#### What the benchmarks measure

Each benchmark name tells you what is being measured and at what scale:

| Benchmark name                         | What it measures                                                                                                                             |
| -------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------- |
| `find_match (n=X)`                     | Finding the best resting order when a marketable order arrives. This is the hot path — it runs on every incoming order.                      |
| `find_match_miss (n=X)`                | `find_match` when no resting order is marketable. Measures worst-case scan time.                                                             |
| `best_bid_offer (n=X)`                 | Querying the BBO (best bid and offer prices and sizes).                                                                                      |
| `add+remove (n=X)`                     | Adding then immediately removing an order. Measures book mutation overhead.                                                                  |
| `submit_ioc_cross (n=X)`               | Full end-to-end: submit an IOC order that crosses the best ask. Includes matching, fill generation, BBO update, and event list construction. |
| `submit_ioc_miss (n=X)`                | Submit an IOC order that matches nothing. Measures the overhead of the submission path without any fills.                                    |
| `submit_sweep_X_levels`                | An aggressive order that fills against every resting order in the book. Worst-case matching.                                                 |
| `find_match_alloc (n=X, Y words/call)` | Same as `find_match`, but the name reports how many minor-heap words are allocated per call. Lower is better; 0 is ideal.                    |

The `(n=X)` suffix is the number of resting orders in the book. The
same benchmark runs at n=10, 50, 100, and 500 so you can observe how
your implementation scales.

#### How to read the output

```
┌───────────────────────────────────────────┬──────────┬──────────┬──────────┬──────────┬──────────────┬────────────┬────────────┐
│ Name                                      │  mGC/Run │ mjGC/Run │ Prom/Run │ mjWd/Run │     Time/Run │    mWd/Run │ Percentage │
├───────────────────────────────────────────┼──────────┼──────────┼──────────┼──────────┼──────────────┼────────────┼────────────┤
│ find_match (n=10)                         │  0.01e-3 │          │          │          │      23.93ns │     15.00w │            │
│ find_match (n=50)                         │  0.01e-3 │          │          │          │      23.39ns │     15.00w │            │
│ find_match (n=100)                        │  0.01e-3 │          │          │          │      22.13ns │     15.00w │            │
│ find_match (n=500)                        │  0.01e-3 │          │          │          │      22.96ns │     15.00w │            │
│ find_match_miss (n=10)                    │  0.01e-3 │          │          │          │     134.62ns │     13.00w │      0.05% │
│ find_match_miss (n=50)                    │  0.01e-3 │          │          │          │     395.48ns │     13.00w │      0.15% │
│ find_match_miss (n=100)                   │  0.01e-3 │          │          │          │     773.19ns │     13.00w │      0.30% │
│ find_match_miss (n=500)                   │  0.01e-3 │          │          │          │   4_510.21ns │     13.00w │      1.74% │
│ best_bid_offer (n=10)                     │  0.01e-3 │          │          │          │     180.96ns │     13.00w │      0.07% │
│ best_bid_offer (n=50)                     │  0.01e-3 │          │          │          │     837.88ns │     13.00w │      0.32% │
│ best_bid_offer (n=100)                    │  0.01e-3 │          │          │          │   1_573.77ns │     13.00w │      0.61% │
│ best_bid_offer (n=500)                    │  0.01e-3 │          │          │          │   7_674.52ns │     13.00w │      2.96% │
│ add+remove (n=100)                        │  0.49e-3 │          │    0.25w │    0.25w │   1_279.04ns │    513.00w │      0.49% │
│ submit_ioc_cross (n=10)                   │  0.20e-3 │          │          │          │   1_305.20ns │    210.00w │      0.50% │
│ submit_ioc_cross (n=50)                   │  0.39e-3 │          │          │          │   4_357.86ns │    410.00w │      1.68% │
│ submit_ioc_cross (n=100)                  │  0.63e-3 │          │    0.30w │    0.30w │   8_726.96ns │    660.00w │      3.36% │
│ submit_ioc_cross (n=500)                  │  2.55e-3 │  0.03e-3 │    6.16w │    6.16w │  37_524.33ns │  2_660.00w │     14.47% │
│ submit_ioc_miss (n=10)                    │  0.07e-3 │          │          │          │     502.83ns │     76.00w │      0.19% │
│ submit_ioc_miss (n=50)                    │  0.07e-3 │          │          │          │   2_174.09ns │     76.00w │      0.84% │
│ submit_ioc_miss (n=100)                   │  0.07e-3 │          │          │          │   4_541.80ns │     76.00w │      1.75% │
│ submit_ioc_miss (n=500)                   │  0.07e-3 │          │          │          │  20_886.92ns │     76.00w │      8.05% │
│ submit_sweep_10_levels                    │  1.40e-3 │          │    0.21w │    0.21w │   4_802.63ns │  1_464.00w │      1.85% │
│ submit_sweep_50_levels                    │ 11.39e-3 │  0.04e-3 │    7.64w │    7.64w │  68_262.45ns │ 11_924.00w │     26.31% │
│ submit_sweep_100_levels                   │ 34.70e-3 │  0.22e-3 │   47.31w │   47.31w │ 259_412.14ns │ 36_249.00w │    100.00% │
│ find_match_alloc (n=100, 12.0 words/call) │  0.01e-3 │          │          │          │      20.79ns │     15.00w │            │
└───────────────────────────────────────────┴──────────┴──────────┴──────────┴──────────┴──────────────┴────────────┴────────────┘
```

Most of these columns are about OCaml's **garbage collection** (GC). A
quick primer: OCaml manages memory automatically. New values are
allocated cheaply on the **minor heap**; periodically a **minor GC**
runs and either reclaims them (if no longer used) or **promotes** the
survivors to the **major heap**. The major heap holds longer-lived
values and is reclaimed by a more expensive **major GC**. Allocation is
fast in OCaml, but every allocated word eventually creates work for the
garbage collector, so allocation-heavy code can become a bottleneck
even when individual operations look quick. For a more thorough
explanation, see the [Real World OCaml chapter on the garbage
collector](https://dev.realworldocaml.org/garbage-collector.html).

The columns:

- **mGC/Run**: fraction of a minor GC triggered per call. Values like
  `34.70e-3` mean one minor GC every ~29 calls. Higher values mean more
  GC pressure. Most benchmarks here sit around `0.01e-3` (one minor GC
  every ~100,000 calls).
- **mjGC/Run**: fraction of a major GC triggered per call. Major GCs
  are much more expensive than minor ones, so even small values here
  matter. Only the heaviest benchmarks (e.g. `submit_sweep_100_levels`,
  `submit_ioc_cross` at n=500) trigger them.
- **Prom/Run**: words promoted from the minor heap to the major heap
  per call. Indicates allocations that survived a minor GC and are
  now more expensive to collect. Usually tracks closely with `mjWd/Run`.
- **mjWd/Run**: major-heap words allocated per call. Most rows are
  blank (no major-heap allocation); only the sweep-style benchmarks
  and large `submit_ioc_cross` runs show non-zero values.
- **Time/Run**: average wall-clock time per single call. This is the
  number you most care about. Measured in nanoseconds (ns). Lower is
  better.
- **mWd/Run**: minor-heap words allocated per call. Every allocation
  creates work for the garbage collector. In the example above,
  `submit_sweep_100_levels` allocates ~36,249 words per call, while
  `find_match` allocates only 15 words.
- **Percentage**: time relative to the slowest benchmark in the run.
  Useful for comparing benchmarks against each other at a glance.

#### What to look for

**Scaling behavior**: Compare the same benchmark at different `n` values.
If `find_match_miss` takes 100ns at n=10 and 4,500ns at n=500, it is
scaling linearly (O(n)) — it scans the entire list when no match is
found. After optimizing with a sorted data structure, it should be
O(log n) or O(1).

**Allocation pressure**: The `mWd/Run` column reveals hidden costs. Even
if an operation is fast, allocating many words per call will eventually
cause GC pauses that add latency jitter. The `find_match_alloc`
benchmark reports the exact words-per-call in its name for easy
comparison.

**Before/after comparison**: Save benchmark output to a file before
making changes, then run again after:

```sh
dune exec lib/order_book/bench/bench_order_book.exe -- -ascii -quota 5 > before.txt
# ... make your optimization ...
dune exec lib/order_book/bench/bench_order_book.exe -- -ascii -quota 5 > after.txt
diff before.txt after.txt
```

#### Tips for stable results

- Use `-quota 5` or higher (5 seconds per benchmark). Lower quotas
  produce noisier results.
- Close other programs while benchmarking. Background CPU load adds
  variance.
- Run benchmarks multiple times and check that results are consistent
  before drawing conclusions.
- Focus on relative changes (2x faster, 10x fewer allocations) rather
  than absolute nanosecond counts, which vary by machine.

### Writing tests

Use the test harness for concise, readable tests:

```ocaml
open Jsip_test_harness

let%expect_test "my scenario" =
  let t = Harness.create () in
  (* Bob places a sell *)
  Harness.submit_ t (Harness.sell ~price_cents:15000 ~participant:Harness.bob ());
  (* Alice buys — should cross *)
  Harness.submit_ t (Harness.buy ~price_cents:15000 ());
  (* Check the book state *)
  Harness.print_book t Harness.aapl;
  [%expect {|
    ACCEPTED id=1 AAPL SELL 100@$150.00 DAY
    BBO AAPL bid=- ask=$150.00 x100
    ACCEPTED id=2 AAPL BUY 100@$150.00 DAY
    FILL fill_id=1 AAPL $150.00 x100 aggressor=2(Alice) BUY resting=1(Bob)
    TRADE AAPL $150.00 x100
    BBO AAPL bid=- ask=-
    === AAPL ===
      BIDS: (empty)
      ASKS: (empty)
      BBO: - / -
  |}]
;;
```

`Harness.submit_` prints all events, including market data (BBO updates
and trade reports). To suppress these in tests that focus on matching
logic, use `Harness.submit_quiet_`.

## How to find your way around

Every module has a `.mli` (interface) file that documents its public API. Start there. Use
the VSCode search sidebar to find functions and types referenced by the exercises, and
follow `.mli` docstrings to locate where the work belongs.

## Glossary

**Aggressor**: The incoming order that causes a match. Contrast with
_resting_ order.

**Ask**: A sell order, or the price at which someone is willing to sell. The
ask side of the book is sorted lowest-to-highest. Also called an "offer."

**BBO (Best Bid and Offer)**: The highest bid price and the lowest ask price
currently on the book. The BBO is the tightest price at which you can
immediately trade.

**Bid**: A buy order, or the price at which someone is willing to buy. The
bid side of the book is sorted highest-to-lowest.

**Bot**: An automated participant that submits orders to the exchange without
human input. In this project, bots are built on `Bot_runtime`, which gives
them a periodic `on_tick` callback and a view of BBOs and inventory.

**Book depth**: The full set of price levels on each side of the order book,
with the aggregate size available at each level. A "depth of book" display
shows this information.

**Cancel**: Remove a resting order from the book before it is filled. The
unfilled portion is no longer available for matching.

**Cross**: When an incoming order's price is aggressive enough to match
against a resting order on the opposite side, the orders "cross" and a trade
occurs.

**Day order**: An order that rests on the book until the end of the trading
day. If not filled by market close, it is automatically cancelled.

**Fair value**: An estimate of the true price of an instrument. Market makers
use their fair value estimate to decide where to place bids and asks.

**Fill**: A trade execution — when a buy and sell order match, both sides are
"filled" (partially or fully). A partial fill reduces the order's remaining
size; a full fill completes it.

**Fundamental price**: A scenario-level notion of an instrument's "true"
price, separate from whatever the order book happens to show. The exchange
itself has no idea about fundamentals — prices are wherever orders cross.
Bots and scenarios read the simulated fundamental from `Fundamental_oracle`
to anchor their strategies and to script step-changes via the news
injector.

**Fill or Kill (FOK)**: A time-in-force that requires the order to be
completely filled immediately, or entirely rejected. Unlike IOC, no partial
fill is allowed.

**Good till Cancel (GTC)**: A time-in-force that keeps the order resting on
the book until it is either filled or explicitly cancelled, potentially
across multiple trading sessions.

**Half-spread**: Half the distance between the bid and ask prices. A market
maker quoting a half-spread of $0.10 around a fair value of $150.00 would
bid $149.90 and offer $150.10.

**Immediate or Cancel (IOC)**: A time-in-force that fills as much of the
order as possible immediately, then cancels the unfilled remainder. The order
never rests on the book.

**Inventory**: The net position (shares held) by a market maker or
participant. A market maker who has bought more than they have sold is "long"
(positive inventory); the reverse is "short" (negative inventory).

**Liquidity**: The availability of resting orders on the book. A "liquid"
market has many resting orders at tight prices, making it easy to trade. A
market maker "provides liquidity" by posting resting orders.

**Market data**: Information about trading activity broadcast to
participants. Includes trade reports (what traded) and BBO updates (current
best prices). Market data is anonymous — it does not reveal who is trading.

**Market maker / Market making**: A market maker is a participant who
provides liquidity by continuously quoting both a bid and an ask. Market
making is the strategy of doing this — profiting from the spread while
taking risk if the market moves against the maker's inventory.

**Matching engine**: The core component of the exchange that receives orders,
maintains the order book, determines which orders can trade against each
other, and produces fills.

**Notional**: The total dollar value of a trade, calculated as price x size.
A fill of 100 shares at $150.25 has a notional value of $15,025.00.

**Order book**: The data structure holding all resting (unfilled) orders for
a given symbol, organized into bids and asks.

**P&L (Profit and Loss)**: The net gain or loss from trading activity.
Calculated from the difference between the prices at which a participant
bought and sold.

**Position**: The number of shares a participant currently holds in a given
symbol. Buying increases the position; selling decreases it. A position of
+100 means you are "long" 100 shares.

**Price level**: A specific price at which one or more orders rest on the
book. Multiple orders can rest at the same price level.

**Price-time priority**: The matching rule used by most exchanges. Orders are
matched first by price (most aggressive first), then by time (earliest
first among orders at the same price).

**Remaining size**: The unfilled portion of an order. An order to buy 100
shares that has been partially filled for 30 shares has a remaining size of 70.

**Resting order**: An order that is sitting on the book, waiting to be
matched. Contrast with _aggressor_.

**Scenario**: A named, reproducible configuration of the exchange — symbols,
fundamental price processes, scheduled news events, and bots — that the
scenario runner boots in a single process. Scenarios are how this project
exercises the exchange end-to-end without needing a human at a client.

**Self-trade**: When the same participant's buy and sell orders would match
against each other. Most exchanges prevent self-trades because they create
misleading trading activity.

**Spread**: The difference between the best bid and best ask prices. A
narrower spread means tighter pricing and typically more liquidity.

**Sweep**: When an aggressive order is large enough to fill against multiple
resting orders at successively worse price levels, it "sweeps" through those
levels.

**Tick**: The minimum price increment. For our exchange, the tick size is
$0.01 (one cent). Prices must be a whole number of ticks.

**Time-in-force (TIF)**: A property of an order that determines how long it
remains active. Common values: Day (until market close), IOC (fill
immediately or cancel), FOK (fill completely or reject), GTC (until
explicitly cancelled).

**Trade print** / **Trade report**: A public record of a completed trade,
showing the symbol, price, and size. Does not reveal participant identities.

## Key concepts

### Price-time priority

Most exchanges match orders using **price-time priority**: among all resting
orders on the opposite side that an incoming order could trade against, the one
with the most aggressive price goes first. If multiple resting orders share the
same price, the one that arrived earliest goes first.

Example: if the ask side has:

- Order A: $10.00 x100 (arrived first)
- Order B: $10.00 x50 (arrived second)
- Order C: $10.05 x200

A buy at $10.05 would fill against A first (best price + earliest), then B
(same price, next earliest), then C.

### Aggressor vs. resting

The **aggressor** is the incoming order that causes a match. The **resting**
order was already on the book. The fill always executes at the _resting_
order's price — this is better for the aggressor (a buyer pays less than their
limit; a seller receives more).

### Market data

After each order submission, the engine may emit:

- **`Trade_report`**: a public, anonymous record that a trade occurred (price
  and size only — no participant names).
- **`Best_bid_offer_update`**: the new best bid and best ask after the book
  changed. Only emitted when the BBO actually changes.

These are the events that market data subscribers receive. They see trades and
price levels, but not who is trading.

### Async RPCs

The server and client communicate using Jane Street's Async RPC library.
Two kinds of RPCs:

- **Regular RPCs** (`Rpc.Rpc`):
  - `submit_order_rpc` is one-way. The server enqueues the request on
    the matching engine's input pipe and returns `unit Or_error.t` as
    soon as it's accepted onto the queue. The matching engine's actual
    response (`Order_accept`, `Fill`, `Order_reject`, …) is meant to
    arrive asynchronously on the participant's session feed — for now,
    printed on the server's stdout.
  - `book_query_rpc` returns a `Book.t` snapshot for a given symbol.
- **Pipe RPCs** (`Rpc.Pipe_rpc`):
  - `market_data_rpc` streams `Best_bid_offer_update` and `Trade_report`
    events for one or more symbols.
  - `audit_log_rpc` streams the full unfiltered event firehose. The
    monitor uses this; ordinary clients shouldn't.

[^1]:
    AAPL is the **stock symbol** (or **ticker symbol**) for Apple, Inc. See the
    [Investopedia](https://www.investopedia.com/terms/s/stocksymbol.asp) entry for more
    information.
