# JSIP Exercises - Part 1

In this part you'll get oriented in the exchange codebase and make your first
substantive changes to it: filling in the price-comparison primitives,
fixing the matching engine so it respects price-time priority, adding new
time-in-force variants and event-driven processing, and refactoring some
LLM-generated command-parsing code into something more idiomatic. The
exercises start small and grow in scope; by the end of this part you will
have touched every layer of the system at least once.

**Learning goals for Part 1:**

- Read `.mli` files to understand a module's public API and use them to
  navigate an unfamiliar codebase.
- Write expect tests and use `dune promote` to iterate on them.
- Use Core's higher-order list functions (`filter`, `fold`, `reduce`,
  `sort`).
- Add variants to existing variant types and let the compiler's exhaustiveness
  warnings guide you to every place that needs updating.
- Recognize and refactor common LLM-generated anti-patterns: stringly-typed
  dispatch, logic spread across modules with no single owner, hardcoded
  lists that drift from their underlying type.
- Reason about the exchange semantics you're implementing — price-time
  priority, time-in-force, end-of-day, self-trade prevention — and explain
  _why_ each rule exists, not just how it's coded.

---

## Exercise 1: Implement `Price.is_more_aggressive` and `Price.is_marketable`

Implement the `is_more_aggressive` and `is_marketable` functions. The first function
determines whether one price is more aggressive than another from the perspective of a
given side. For a buyer, a higher price is more aggressive (willing to pay more). For a
seller, a lower price is more aggressive (willing to accept less). The second function
determines whether an order on a given side would trade against a given resting price.

Once you've implemented both functions, use them in `Order_book`'s internal
`best_price` helper and in `Order_book.find_match`, replacing the equivalent
ad-hoc per-side comparisons with calls to the `Price` functions. (Note that
`best_price` is a private helper inside `order_book.ml`, not exposed in the
`.mli` — it backs `best_bid_offer`.) For `best_price`, you can avoid any
matching logic and use a single `List.reduce` call.[^reduce]

[^reduce]:
    `List.reduce` combines all elements of a list into a single
    value using a function you provide. It returns `None` for an empty
    list and `Some result` otherwise. For example, to find the maximum
    element: `List.reduce [3; 1; 4; 1; 5] ~f:Int.max` returns `Some 5`.
    For `best_price`, you would reduce the list of order prices using
    `Price.is_more_aggressive` to keep the more aggressive of each pair.

This is a good pattern to keep in mind -- reusable logic relating to a
particular type (in this case `Price.t`s) ought to go in the module for that type.
Otherwise it risks being sprinkled around different parts of the system, making it hard to
improve and maintain.

**Hints:**

- Look at `price.mli` for descriptions of both functions.

**Tests to write:** Add cases to `lib/types/test/test_price.ml` covering both
sides and edge cases (equal prices).

We'll have a lecture on testing later on. For now, you can refer to
[Real World OCaml - Expect Tests](https://dev.realworldocaml.org/testing.html#expect-tests)
for some examples and guidance.

---

## Exercise 2: Fix price-time priority matching

The order book currently stores orders in unsorted lists and `find_match`
returns the first tradable order it encounters, not the best-priced one.
This means buyers can pay more than they need to. The test "price priority
is broken" demonstrates this bug.

<!-- TODO: link to test file lib/order_book/test/test_matching_engine.ml#217:233 -->

**What to do:**

1. Change `find_match` to scan the list and return the most aggressively priced resting
   order on the opposite side (lowest ask for a buy, highest bid for a sell). Among orders
   at the same price, prefer the one that was added first (price-time priority).
2. Update `snapshot_side` so the snapshot lists levels in the same
   order that matching would visit them: bids highest-price-first, asks
   lowest-price-first, with ties broken by arrival time. The snapshot is
   what clients see when they query the book, so it should reflect the
   real matching order rather than insertion order.
3. Update the expect output in the affected tests, including the "price
   priority" test in `test_matching_engine.ml` and the snapshot test in
   `test_order_book.ml`.

**Hints:**

- A good approach for `find_match`: filter for marketable resting orders,
  then fold to find the most aggressive using `Price.is_more_aggressive`.
  Don't try to sort the whole list -- a single fold is simpler and
  sufficient.
- For time-priority tie-breaking: lower `Order_id` = arrived first. This
  falls naturally out of the sequential ID generator.
- For `snapshot_side`: the current code maps orders to `Level.t`
  (`{ price; size }`) and sorts them with `Level.compare`, which only
  knows about price and size — it has no notion of arrival time. Sort
  the underlying `Order.t list` first, with a comparator built from
  `Price.is_more_aggressive` and `Order_id.compare` (lower order ID =
  arrived first), then map to `Level.t`. That keeps the snapshot
  consistent with the matching order.
- After this change, several existing tests will have different expect output
  (fill order changes, snapshot ordering). That's the point -- the old output was _wrong_.

---

## _Exercise 3: Add symbol validation_ [OPTIONAL]

`Symbol.of_string` currently accepts any non-empty string. Add validation
that the symbol contains only uppercase alphanumeric characters.

**Design decision:** Should `of_string "aapl"` raise an error, or
automatically uppercase it? Either choice is defensible — pick one and
document why in a code comment.

**Hints:**

- `String.for_all` with `Char.is_alphanum` from Core is the idiomatic way
  to validate all characters.
- Note that the client binary (`app/client/bin/main.ml`) already
  uppercases the symbol string before calling `Symbol.of_string` for
  `BOOK` and `SUBSCRIBE` commands, while `Protocol.parse_command`
  (used for `BUY`/`SELL`) passes it through unchanged. If you decide
  to auto-uppercase inside `of_string`, callers can stop uppercasing
  themselves; if you reject mixed case instead, you'll want to make
  `parse_command` uppercase consistently with the `BOOK`/`SUBSCRIBE`
  paths.

**Tests to write:** Add cases to `lib/types/test/test_symbol.ml` for valid symbols,
invalid symbols (special characters, empty), and your lowercase decision.

---

## _Exercise 4: Participant-view fills_ [OPTIONAL]

Add `to_participant_view : t -> Participant.t -> string option` to the `Fill` module.

It should format a fill from the perspective of a specific participant. Instead of the
exchange-centric "aggressor=Alice BUY resting=Bob" view, show "You bought 100 AAPL at
$150.00" or "You sold 100 AAPL at $150.00". If the fill does not involve the given
participant, return `None`.

This is what the gateway should send to individual clients rather than the
raw exchange fill.

**Hint:** The resting party's side is `Side.flip fill.aggressor_side` — it
is not stored directly in the fill record. If the aggressor was a buyer,
the resting party sold.

Add an expect test for `to_participant_view` to `test_fill.ml`.

Note that, for now, the participant view isn't actually used in the client-side display —
the gateway doesn't (yet) send fill messages to individual participants, and the server
uses the `Protocol.format_event` rendering. The unit test is enough to demonstrate the new
function; you'll plug it into the real session feed in Part 2 Exercise 1c, when the
client starts subscribing to its session feed.

---

## _Exercise 5: End-of-day processing_ [OPTIONAL]

Add a function that cancels all resting Day orders and emits
`Order_cancel` events with `End_of_day` reason.

**What to do:**

1. Add `end_of_day : t -> Exchange_event.t list` to the matching engine.
2. Iterate all books, collect all resting Day orders, remove them, and
   emit cancellation events.
3. Write a test that verifies Day orders are correctly removed and that that `end_of_day`
   returns the correct events.

**Hints:**

- `orders_on_side` returns a _snapshot_ (a copy of the data), so it is safe
  to iterate while removing orders from the book. If it returned a live
  view, mutation during iteration would be unsafe.
- IOC orders should never be resting on the book, but handle them defensively anyway
  (cancel with `End_of_day` reason, but print a warning that there's likely a bug).
- You test should include multiple symbols and partially-filled orders to make sure the
  remaining size is reported correctly.

---

## _Exercise 6: Add Good-till-Cancel orders_ [OPTIONAL]

Add `Good_till_cancel` to `Time_in_force.t`. GTC orders rest on the book
like Day orders, but are not cancelled at end of day. This requires:

1. Adding the variant and updating `rests_on_book` (should return `true`).
2. Implementing end-of-day processing that skips GTC orders.
3. Deciding how GTC orders interact with server restarts. (For now, it is
   fine if they are lost — persistence will be the subject of a later exercise.)
4. Updating the client to accept "GTC" as a time-in-force string (`protocol.ml`). This
   should be reflected in the help text printed in `main.ml` at the start of a client
   session.
5. Add new tests or extend existing ones to cover GTC behavior, particularly with respect
   to end-of-day.
6. Test that a client can manually submit a GTC order.

**Hint:** GTC is a very simplest new time-in-force variant — it behaves exactly like Day
for matching. The only difference is in end-of-day processing.

---

## _Exercise 7: Add Fill-or-Kill orders_ [OPTIONAL]

Add `Fill_or_kill` to `Time_in_force.t` and
`Fill_or_kill_not_fully_fillable` to `Cancel_reason.t`. Update
`rests_on_book` (FOK should return `false` — it never rests).

In `Matching_engine.submit`, before executing fills for a FOK order, check
whether the total available liquidity at marketable prices is >= the order
size. If not, reject the entire order (emit `Order_cancel` with the new
FOK reason, no fills). If yes, proceed with normal matching.

**Hints:**

- You can compute available liquidity by iterating resting orders on the
  opposite side and summing the remaining sizes of those with marketable
  prices. This is the check that makes FOK different from IOC.
- The pre-check must happen _before_ any state mutation. If you start
  filling and then discover you can't complete, you've already mutated
  resting orders.
- A rejected FOK emits `Order_accept` then `Order_cancel` — not
  `Order_reject`. The order was valid (it got an ID), it just couldn't be
  completely filled. `Order_reject` is for malformed orders (e.g., unknown symbol).
- After a FOK rejection, verify the book state is unchanged — no resting
  orders should have been modified.
- Don't forget to also update the protocol parser to accept "FOK" as a
  time-in-force string, update the help text, and test that it works.

**Write tests for:**

- FOK fully fillable: should fill like a normal order
- FOK not fully fillable: should be completely rejected, no fills
- FOK exactly fillable: edge case at the boundary

---

## Exercise 8: Centralize command parsing

As you've seen in last two exercises, implementation of the command-line interface is
currently split across two places:

1. `Protocol.parse_command` handles BUY/SELL by string-matching on the first word of the
   line (`"BUY" -> Ok Side.Buy | "SELL" -> ...`), including hardcoded string matching for
   time-in-force (`"IOC"`, `"DAY"`). Hard-coding these time-in-force strings instead of
   tying them directly to `Time_in_force.t` prevent the OCaml compiler from being able to
   warn us if we forgot to update this string matching when adding a new order type.
2. The client binary (`app/client/bin/main.ml`) uses
   `String.is_prefix` and `String.chop_prefix` to detect BOOK and
   SUBSCRIBE before falling through to the `Protocol` parser for
   everything else. The client's help text also hardcodes the
   time-in-force options as a string literal.

Meanwhile, adding more command types (like the ability to CANCEL an order) would require
wiring them into `main.ml`'s `if`/`else` chain, which would quickly become cumbersome
and hard to work with.

The state of this command-line handling, technically working for the current set of
features, but annoying to modify and awkwardly split up, is a common pattern in
LLM-generated code. AI tools like Claude Code will eagerly produce logic that works but is
split across modules with no single owner, and stringly-typed dispatch
(`String.is_prefix`, `String.uppercase` + match on string literals) where structured types
would be clearer. In fact, Claude Code was the author of this exact code! We left it as
part of the initial exchange code because we think it's important to become familiar with
ways that LLMs can produce suboptimal code before you start using them later in the
program.

Your job in this exercise is to centralize all command parsing into one module that uses
OCaml's type system for dispatch.

### 8a: Define the command type and verb

Create a new module `Exchange_command` in the gateway library (i.e., add
`exchange_command.ml` and `exchange_command.mli` to `lib/gateway/src`).

First, define a `Verb.t` type for the first word of a command:

```ocaml
type verb = Buy | Sell | Book | Subscribe
```

Derive case-insensitive `to_string`/`of_string` on this type so that
parsing the verb is just a call to `Verb.of_string` rather than a
chain of string comparisons. Look at how `Side.t` uses
`[@@deriving string ~case_insensitive]` for the pattern.

Then define the parsed command type. Each variant carries only the
data that its command needs:

```ocaml
type t =
  | Submit of Order.Request.t
  | Book of Symbol.t
  | Subscribe of Symbol.t
```

Note there is no `Unknown` variant — an unrecognized verb is simply an
`Error` in the result:

```ocaml
val parse : ?default_participant:Participant.t -> string -> t Or_error.t
```

The `parse` function should:

1. Split the line on spaces, take the first word.
2. Parse it as a `Verb.t`. If it fails, return `Error`.
3. Match on the verb to parse the remaining arguments:
   - `Buy | Sell`: parse symbol, size, price, time-in-force,
     participant (move this logic from `Protocol.parse_command`).
   - `Book | Subscribe`: parse a required symbol argument.

The `default_participant` optional argument replaces the purpose of
`Protocol.parse_command_with_default_participant`: when present, it
overrides the participant on parsed orders where no `as <name>` clause
was given. If neither `default_participant` nor an `as <name>` clause
is provided, fall back to "anonymous".

When moving the order-parsing logic, also fix the time-in-force
parsing: `Protocol.parse_command` hardcodes `"IOC"`, `"DAY"`, etc. as
string literals, but `Time_in_force` already has a case-insensitive
`of_string` derived from `[@@deriving string]`. Use it instead.

Similarly, these abbreviations are hard-coded in error messages and usage strings, meaning
this have to be manually updated every time the variant changes.
Fortunately, `[@@deriving enumerate]` provides a `val all : t list` of the variant tags that you can use along with
`List.map` and `String.concat` to add `val all_str : string` to `Time_in_force`. Use
it in the error message for unrecognized values, so any new time-in-force variants
will automatically appear.

Apply the same principle to the usage string — use `Time_in_force.all_str` rather than
writing `"[DAY|IOC]"`.

Don't forget to add `Exchange_command` to `jsip_gateway.ml` and
`jsip_gateway.mli`.

**Hints:**

- Move the order-argument parsing code from `Protocol.parse_command`
  into `Exchange_command` rather than delegating to it. The goal is for
  `Exchange_command` to own _all_ command parsing, not to be another
  layer on top of Protocol.
- After this, `Protocol` should contain only event formatting
  (`format_event`, `format_events`). Consider whether "Protocol" is
  still the right name for what remains.
- Watch out for the case where the first "extra" argument after the
  price is `as` rather than a time-in-force — the existing code
  handles this by falling through to the default `Day`.

### 8b: Use the command type in the client

Replace the `if String.is_prefix` chain in `app/client/bin/main.ml` and the call to
`parse_command_with_default_participant` with a single call to
`Exchange_command.parse`, followed by a `match` on the result.

Each arm of the match should do exactly what the corresponding
`if`/`else` branch does now — behavior should not change, only the
structure of the code.

Also update the help text printed on connect: replace the hardcoded
time-in-force list (e.g., `[IOC|DAY]`) with `Time_in_force.all_str`
so it stays in sync with the type definition.

**Hints:**

- The `Error` case prints the error message and loops.

### 8c: Update tests

**Migrate tests.** The command-parsing tests in `test_protocol.ml` currently call
`Protocol.parse_command` and `parse_command_with_default_participant`. Most of them should
move to a new `test_exchange_command.ml` and be rewritten to use `Exchange_command.parse`.

Add new tests for:

- BOOK with a symbol argument
- SUBSCRIBE with case-insensitive input
- Default participant override and explicit `as` clause preservation

---

## _Exercise 9: Self-trade prevention_ [OPTIONAL]

When a participant's incoming order would match against their own resting
order, the exchange should prevent the trade. This avoids misleading
activity.

Add logic to the matching engine to cancel any incoming order that would self-trade (i.e.,
match with an order from the same participant). In a real exchange, in addition to having
the order cancelled, a market participant might even be fined for sending an order that
would self-trade.

---

## Exercise 10: Improve the order book data structure

Replace the plain list with a data structure that maintains price-time
ordering. The current implementation has $O(n)$ `find_match` and `remove`,
and no efficient way to query the best price.

**Options to consider:**

- A `Map` keyed by `(Price.t, Order_id.t)` per side — O(log n) for all
  operations. Simple to implement using `Core.Map`.
- Separate price levels with a queue at each level — more like a
  real exchange order book. Uses a `Map` from price to a queue of orders.

**Constraint:** The `order_book.mli` interface should not change. This is a
pure internal improvement.

**Hints:**

- The composite key `(Price.t, Order_id.t)` gives you price-time ordering
  for free via the default `compare` — prices sort numerically, and within
  the same price, order IDs sort by arrival time.
- For bids, "best" = highest price = `Map.max_elt`. For asks, "best" =
  lowest price = `Map.min_elt`.
- You need a reverse index mapping order ID to the data structure containing the order to
  make `remove` O(log n). Without it, removing by order ID requires scanning all entries.
- `orders_on_side` for bids needs `List.rev` because the Map's natural
  order is ascending, but bids should be displayed best-first (descending). Better yet,

**Tests:** All existing tests should continue to pass.

**Stretch:** [Profile](overview.md#benchmarks) the book with a large number of orders
(thousands) and compare list vs. map performance.

---

## Stretch: Per-participant P&L tracking

If you finish the rest of Part 1 early, build a small module that tracks
each participant's running **P&L** (profit and loss) from their fills.
This comes into play later in the program when you start implementing
trading strategies — you might want to ask the system, "how is this
strategy doing?"

The model is mark-to-market against a reference price (you can use the
last trade price per symbol for now):

- A participant's **realized** P&L is the cash they have earned or
  spent on closed positions: the difference between what they paid
  for shares and what they sold them for. Buy fills decrease cash by
  `size * price`; sell fills increase cash by `size * price`.
- A participant's **unrealized** P&L is the paper gain or loss on any
  still-open position, valued at the reference price:
  `number_of_shares * (reference_price - average_entry_price)`. Each fill
  changes the number of shares and the average entry price.
- Total P&L is realized + unrealized.

**What to build:**

1. A new module `lib/pnl/src/pnl.{ml,mli}`. Internally it tracks, for
   each participant and symbol, current inventory, the running cost
   basis (so you can compute average entry price), and realized
   cash. Public functions to `apply_fill : t -> Fill.t -> t`,
   `apply_trade_report : t -> Trade_report.t -> t` (to refresh the
   reference price for unrealized P&L), and `summary : t -> Participant.t -> ...` returning a per-symbol breakdown plus the
   total.
2. A few expect tests that drive it through some hand-rolled fills
   and a final trade-print, comparing the summary against expected
   numbers.
