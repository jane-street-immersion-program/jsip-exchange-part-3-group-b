# JSIP Exercises - Part 3

Part 3 is different from the previous two parts in a couple ways:

- **From solo work to group work.** You're going to start out this
  part working in a group of three or four, using a _shared_ GitHub
  repo where you'll each contribute some shared code. You'll review each other's
  code and copy the merged result into your own exchange code.

- **From feature work to production engineering.** The bots you build
  in this part are deliberately mean — they're designed to expose the
  ways your exchange falls over under load. The second half of
  part 3 is spent making the exchange survive them, while keeping the
  exchange useful to _non_-pathological clients.

Part 3 also marks your introduction to Claude Code. Throughout this doc, "you can use AI"
is implicit; the explicit notes call out where AI tends to fail or where reviewer
attention is especially important.

**Learning goals for Part 3:**

- Coordinate a multi-developer codebase via shared GitHub conventions
  (branch protection, pull-request review, RPC compatibility).
- Reason about the _resource_ dimension of a system — memory, latency,
  pipe occupancy — not just the _correctness_ dimension you've focused
  on so far.
- Build adversarial bots that surface specific resource pathologies,
  then design defenses against them.
- Trade off robustness against the user experience of legitimate
  clients. Every limit you impose makes your exchange less attractive
  to someone; defending that trade-off is part of the work.
- Use Claude Code productively while staying the architect of the
  code that lands in your branch — and read your group-mates' AI-assisted
  code with the same skepticism you'd read your own.

---

## Section 0: Group setup

### 0a: Your group and shared repo

On slack you will have been assigned to a group of three or four, and given a link to
a shared GitHub repository for that group seeded with the
exchange code and implementations of exercises 1.1, 1.2, 1.8, 1.10, 2.1, and a little bit of 2.3.

Each of you keeps your own personal repo (your _solo repo_) — that's
where your individual Part 1 / Part 2 work continues to live. The
group repo is _additive_: it holds the bots and scenarios you all
agree to share. You'll keep developing the exchange itself in your
solo repo, and pull bots and scenarios over from the group repo as
they get merged.

To start:

1. Each group member should clone the group repo locally, in a different directory than your solo repo.
2. Confirm `dune build` and `dune runtest` both pass on a fresh
   clone of the group repo. If something is broken, fix it as a group
   before doing anything else.

### 0b: Reconcile your RPC protocols

You've each been working on the exchange independently.
That means your `Order.Request.t`, your `Exchange_event.t`,
your `Time_in_force.t`, and the RPCs that connect them have probably
diverged. Two exchanges that disagree on these types can't run each
other's bots: a client built against an `Order.Request.t` with a
`client_order_id` field won't be able to read the bytes that come
back from an exchange where that field is missing or named
differently.

When the exchange sends a message to a client, the
OCaml value doesn't travel as such — instead the sender turns it
into a sequence of bytes, ships those bytes over the network, and
the receiver turns the bytes back into a value on the other side.
That process of "OCaml value → bytes → OCaml value" is called
_serialization_. To do this, we use a Jane Street library called `bin_io`
(short for "binary I/O"; you may also see it referred to as
"binprot", for "binary protocol"). The `[@@deriving bin_io]`
on most of our types is a PPX that generates the
code that does the serialization. Two sides of an RPC can only
talk to each other if both sides agree on exactly how each type
is laid out as bytes — same field order, same set of variants in
the same order, same nested types all the way down.

`lib/gateway/test/test_rpc_shapes.ml` already exists to check that
agreement. Each `let%expect_test` in that file calls
`Rpc.Rpc.shapes` or `Rpc.Pipe_rpc.shapes` for one RPC and prints
the result — a _digest_ of the `bin_io` layout of every type that
crosses the connection (the query, the response, and, for pipe
RPCs, the error type).

A digest is a short fixed-length hexadecimal string computed from
the structure of a type's `bin_io` layout: the order of record
fields, the order of variant constructors, the layout of every
nested type those fields and constructors refer to, and so on,
all the way down. The digest changes whenever any of that
changes — adding or renaming a field in `Order.Request.t`, adding a variant to
`Time_in_force.t`, even reordering existing variants. So two exchanges
that produce identical digests for an RPC can be reasonably
expected to run each other's client code for that RPC; two
exchanges that produce different digests cannot.

The starter test file already covers `submit-order`, `book-query`,
`market-data`, and `audit-log`. You almost certainly added more
RPCs during Part 2 — at minimum `login_rpc`, `session_feed_rpc`,
and `cancel_order_rpc`. Add a `let%expect_test` block for any of
your RPCs that isn't already covered (copy the shape of an existing
block, then run `dune runtest --auto-promote` to populate the
digests). Do this _before_ the comparison step below.

Then, to reconcile:

1. Each member runs `dune runtest lib/gateway/test/` in their solo
   repo to confirm the expect outputs in the file are up to date.
   If `runtest` fails, promote the new digests with
   `dune runtest --auto-promote` so the file reflects the current
   types.
2. Open `lib/gateway/test/test_rpc_shapes.ml` in your editor and
   paste each member's set of `[%expect { ... }]` blocks into a
   shared doc, side by side.
   Include the digests from the group repo, which will also need to match.
3. Compare them RPC by RPC. If every digest matches across all
   members, you're done.
4. If a digest differs, the RPC whose digest differs is on incompatible types. Track down
   the underlying divergence — the most common offenders: differently-named fields, extra
   fields on `Order.Request.t`, extra variants on `Exchange_event.t` or `Time_in_force.t`,
   different `Client_order_id` representations, different RPC `~version` values.
5. As a group, pick one canonical shape. Whichever member already
   has it: nothing to do. Whichever members don't: port the
   relevant types to match, run the test, and confirm the digests
   now match. If you pick something that differs from the group repo, you'll need to update it to match. You'll need to do so via a pull request, see the instructions in 0c below.

**AI note:** Claude is great at this kind of conversion grunt-work
("rename `Time_in_force.Good_till_cancel` to `Time_in_force.Gtc`
across the codebase, and update every dependent file"). It's _bad_
at deciding which variant is canonical. Make that decision
yourselves as a group; then let Claude do the mechanical port.

### 0c: Working with the group repo

You've been working on your solo repo so far by committing
directly to the `main` branch. The group repo doesn't let you do that —
which is the whole point of having a group repo, and is also the
way every real-world software project you'll work on operates.
This section walks through the GitHub workflow you'll use for this shared repo.

**Branches.** A branch is a named pointer to a sequence of
commits. The default branch is usually `main` and represents the
"official" state of the project. To make a change without
disturbing `main`, you create a new branch from it, do your work
there, and ask for the change to be merged back later.

```sh
# Make sure you're up to date with main before branching:
git checkout main
git pull

# Create a new branch and switch to it. Use your-name/short-description.
git checkout -b alice/book-filler

# Do your work, commit normally:
git add app/bots/src/book_filler.ml
git commit -m "Add book-filler bot"

# Push the branch to the group repo:
git push -u origin alice/book-filler
```

The first `git push -u` sets up the branch's remote tracking so
later `git push` invocations on the same branch don't need
arguments.

If you accidentally commit to the `main` branch, you can move that commit to a different
branch by doing

```sh
git switch -c my-local-branch   # branch now points at the same commits
git switch main
git reset --hard origin/main    # rewind main back to the remote's state
git switch my-local-branch
```

**Pull requests (PRs).** A pull request is a proposal to merge
one branch into another. On GitHub, you open it by visiting the
group repo in a browser; after `git push -u`, `git` prints out a link to open a pull request.
Ctrl-click it to open it. The GitHub web page for your repo will also show a "you
just pushed a branch — open a PR?" banner. Using either link, fill in:

- A title (e.g. "Add book-filler bot + book-fill scenario").
- A description (the design note from 1b, plus an honest-AI-use
  note — see 1c).
- A reviewer (one of your group-mates). Use the gear icon in the "Reviewers" section to
  the right of the title.

Once you've opened the PR, GitHub runs the configured _CI_
(_continuous integration_) checks on the branch automatically.
For your group repo, that means `dune build` and `dune runtest`
— GitHub spins up a fresh machine, checks out the branch, and
reports back whether each command succeeded. If a check fails,
fix the issue and `git push` again — the same PR picks up the
new commits.

**Branch protection** is a per-branch rule set we've enabled on
`main` in your group repo. For `main`, it requires:

- At least one approving review from a group member who is _not_
  the PR author.
- All CI checks (`dune build`, `dune runtest`) passing.
- No _force-pushes_ — i.e. no `git push --force`, which would
  let you overwrite the branch's history on the server (handy
  for legitimate use cases like reorganizing commits before
  merge, but also a quiet way to erase a reviewer's comments by
  pushing over the commits they were attached to). Force-pushes
  are off here as a safety measure.

You can't merge a PR until those conditions are met. The
restrictions exist to make sure no one merges code that nobody
else has looked at, and to keep `main` in a state where every
group member can pull it and have a working build.

**Reviewing a PR.** When a group-mate tags you, GitHub emails
you a link. On the PR page:

1. Click the "Files changed" tab. Read every file, not just the
   summary. Hover over a specific line to leave an inline
   comment.
2. For anything that needs a real run, _pull the branch
   locally_:

   ```sh
   git fetch
   git checkout alice/book-filler
   dune build
   dune runtest
   # …then exercise the scenario, etc.
   ```

3. When you're done, hit "Review changes" at the top right:
   - "Comment" if you just have notes; the PR stays open.
   - "Request changes" if there's something the author has to
     fix before you'll approve.
   - "Approve" once you're satisfied. After at least one
     approval (plus CI passing), the author can click "Merge".

**Merging.** The PR author hits "Merge pull request" on GitHub.
Default to "Squash and merge", which collapses the branch's
commits into a single commit on `main` — easier to revert if
something goes wrong. After merging, delete the branch (GitHub
offers a button for this); next time you start work, pull `main`
fresh and branch again.

If you get stuck on any of the above, GitHub's docs are the
authoritative reference:

- [About branches](https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/proposing-changes-to-your-work-with-pull-requests/about-branches)
- [Creating a pull request](https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/proposing-changes-to-your-work-with-pull-requests/creating-a-pull-request)
- [Reviewing proposed changes in a pull request](https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/reviewing-changes-in-pull-requests/reviewing-proposed-changes-in-a-pull-request)
- [About protected branches](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches)

Use this workflow for the rest of Section 0 as you reconcile RPCs,
and throughout Section 1 for each bot/scenario PR.

---

## Section 1: The pathological bots

Real exchanges have to assume some fraction of their connected clients will misbehave.
Most misbehavior isn't malicious — it's a buggy strategy stuck in a tight loop, a market
maker whose fair-value model drifted and is now spraying orders, a test that was
accidentally pointed at the production endpoint, a slow process that subscribed to market
data and then got stuck. A few are: a competitor probing for weakness, a participant
deliberately trying to slow down its rivals' fills with junk traffic. The exchange has to
keep running for _everyone else_ while one of these clients is connected — both because
its other paying customers expect uninterrupted service, and because the regulator and the
press would very much like an explanation if it doesn't.

You're going to spend Section 1 building bots whose entire
job is to misbehave in specific, repeatable ways. Each one targets
a different exchange resource: the order book, the request queue,
a subscriber pipe, the cancel path. You will divide up the work of implementing these among your group, and submit the implementations to the _group_
repo so that every group member can run every group-mate's
bot against their own exchange. Each bot is a separate
file under `app/bots/src/`, each scenario a separate file under
`app/scenarios/src/`, and each is delivered via a single pull
request that another group member reviews and merges.

In Section 2 you'll build a dashboard to _see_ what these bots do
to an exchange's memory use and latency. In Section 3 you'll defend
your exchange against them — which is where most of the real
engineering happens. The bots in this section are the input to
that work; treat them as adversaries you're constructing on
purpose so you can fight them later.

### 1a: Bot/scenario assignments

As a group, distribute the four required bots — one per group member.
If you have four members, everyone owns one. If you have three,
someone owns two; agree on a fair distribution given the bots'
relative size (probably book-filler + slow-consumer for the same
person, since both are relatively small).

The four required bots:

1. **`Book_filler`** — rapidly piles resting Day orders on the book
   without intending to fill. Targets memory in the order book and
   the latency of `find_match` / book snapshots.
2. **`Spammer`** — submits a large burst of orders on every tick.
   Targets the request queue, the dispatcher's per-event work, and
   the bandwidth of subscriber pipes.
3. **`Slow_consumer`** — logs in, subscribes to market data and/or
   the audit log, then reads its pipe very slowly (or not at all).
   Targets the exchange-side buffer that holds events for this
   subscriber.
4. **`Cancel_storm`** — submits an order, immediately cancels it,
   repeats forever. Targets the cancel path, the
   submit/accept/cancel event flow, and the duplicate-ID bookkeeping
   from Part 2.

Each bot ships with a _scenario_ under `app/scenarios/src/` that
launches the bot alongside a reasonable supporting cast (typically:
the bot, a market maker so the bot has something to interact with,
and maybe a noise trader so the book has organic activity). The
scenario is what your group-mates will run when they want to see
_this_ pathology in action.

Required scenarios (one per bot, named obviously):

- `Book_fill` — drives the book filler.
- `Order_spam` — drives the spammer.
- `Slow_consumers` — drives the slow consumer.
- `Cancel_storm` — drives the cancel storm.

Each scenario must be self-contained: a fresh exchange spun up with
just that scenario should exhibit the pathology within ~30 seconds
of running.

Nothing about a scenario forces it to contain a single copy of its pathological bot.
Sometimes a single instance of the bot is enough; other times the pathology only really
emerges with a crowd (one slow consumer can stall its own pipe regardless of how many
other slow consumers exist, but the effect might only become obvious with many slow
consumers). If you think your bot is more interesting in numbers — say so in the design
note, and have the scenario launch several (or many!) copies with different participant
names and RNG seeds. The bots' `Config.t` should be parameterized enough that the scenario
can tune each instance independently.

**Devise your own pathological bots.** The four above are the required starting set, but
we encourage you to challenge yourself and your groupmates by contributing other
misbehaving bots. Each bot you write is a thought experiment about how a real client could
go wrong — and a real exchange has to imagine many more than four ways. If you come up
with another pathology that exposes a different exchange weakness, build it and add it to
the group repo. A few prompts to get started:

- A bot that submits many tiny orders just below the BBO,
  permanently sitting one tick away from being marketable.
- A bot that toggles `Subscribe` and `Unsubscribe` (if your
  protocol supports it) repeatedly.
- A bot that opens a connection, logs in, and then disconnects in
  the middle of a session-feed read.
- A bot that issues `Book` queries on a hot loop.
- A bot that submits very large orders that fill across many
  resting orders at once, producing many fills per submit.

**Measurement bots (a separate genre).** Distinct from
pathological bots are _measurement_ bots — bots whose job is to
play the role of an _innocent_ client whose user experience
matters, so you can see the collateral damage a pathological bot
inflicts on the rest of the market. These belong in scenarios next
to the pathologies; they're how you'll observe whether a defense
in Section 3 actually preserved the legitimate use case. Some
ideas:

- **`Latency_amplifier`** — submits a single order at random
  intervals and measures the time from submit-call to response,
  printing percentiles. Run this alongside the spammer to see
  whether innocent clients are affected.
- **`Resource_canary`** — calls `book_query_rpc` on a fixed
  schedule and reports its round-trip time. The user whose UX
  you're protecting.

If you build any of these, put them in `app/bots/src/` like
everything else, but mention in the bot's `.mli` doc comment that
it's an observer, not a misbehaver.

### 1b: Implementing a pathological bot

Each bot satisfies `Jsip_bot_runtime.Bot_runtime.Bot` — same
interface as the bots you built in Part 2.
The pattern is well-trodden by now; the new part is the bot's
_behavior_, deliberately tuned to break the exchange rather than to
trade.

For each bot, before writing any code, write a short description
in the bot's `.mli` that:

- Explains, in a sentence or two, the behavior the bot produces
  — what events it generates, on what schedule.
- Documents every field of its `Config.t`, with units, defaults,
  and what each knob is for.

The behavior description gives the reviewer the ground truth to
check the implementation against. The config documentation lets
your group-mates tune the bot when they wire it into other
scenarios.

**Where the parameterization lives.** All tunable behavior should
go through the bot's `Config.t`, which the scenario constructs and
hands the runtime. Don't hard-code numbers in the bot's `.ml`;
that makes the same bot useful in many scenarios at different
intensities. (Concretely: a `Config.t` with an `orders_per_tick`
field is much more useful than a hard-coded `50`.) Aim for a
config that's expressive enough that a single bot module can
produce both a gentle scenario and an aggressive one just by
changing the constants.

What to put in the config is up to you, but the bot's `Config.t`
should at minimum let the scenario pick:

- The symbols the bot operates on.
- The intensity of the misbehavior (orders/tick, sleep duration,
  submit/cancel cycle period — whichever rate-like quantity makes
  sense for the bot).

Anything more specific (price ranges, order sizes, subscription
choices, etc.) belongs in the config too, but the exact set is a
design decision per bot — make it the way that's most useful for
the scenarios you intend to run.

**AI note:** Claude can scaffold any of these bots fluently — the
interface is well-established and the behavior is mechanical. The
shapes it'll get wrong (silently): whether it preserved
reproducibility (every random choice must use `Context.random`,
not a fresh `Random.self_init` or `Random.State.make_self_init`),
whether the bot actually exerts pressure on the resource you
care about (a "spammer" that fires through `Context.submit` once
per tick rather than in a tight burst is not actually spamming),
and the freshness of its `client_order_id` allocation (the cancel
storm needs a _new_ client order ID each cycle, otherwise
duplicate detection blocks every submit after the first). Read
the diff critically — _especially_ the test, which Claude tends
to write in a way that asserts only the bot's own logic, not
whether the bot actually produces the pressure it was designed
for.

### 1c: One PR per bot/scenario

Each bot/scenario goes in via a single PR using the workflow from
0c. Per PR:

1. Branch off `main` (`git checkout -b your-name/<bot>`).
2. Add the bot module under `app/bots/src/<bot>.ml`.
3. Add the scenario module under `app/scenarios/src/<scenario>.ml`
   and register it in `app/scenarios/src/jsip_scenarios.ml`'s
   `all` list.
4. Add tests:
   - At minimum, a recording test of the bot (use the
     `make_recording_bot` helper from
     `app/bots/test/test_bots.ml`) that drives a few ticks and
     asserts the expected pattern of submitted requests.
   - For the cancel storm, also assert the cancel calls.
   - For the slow consumer, the recording-bot helper doesn't
     quite fit (the slow consumer reads, it doesn't submit); a
     smaller unit test that exercises its
     `Pipe.read_now_at_most` cadence is fine.
5. Push the branch, open the PR, and tag a group-mate as
   reviewer. Branch protection prevents self-merge; they have to
   approve before you can merge.

The reviewer's job is _not_ "rubber-stamp this." They should:

- **Pull the branch and run the scenario for at least one
  minute.** Watch what happens to three things:
  - The terminal monitor (`app/monitor/bin/main.exe` — the
    text-based dashboard that subscribes to the
    audit log and renders a filterable color-coded event
    stream).
  - The exchange process's memory. `htop` (preinstalled on
    your machines; press `F4` and filter by `main.exe` or your
    server's binary name) shows a live view of every process's
    _RSS_ — "resident set size", the amount of RAM the process
    is currently using. Watching the RSS column tells you
    whether memory grows, stabilizes, or holds steady while the
    bot runs.
  - Other clients' experience: try sending a single order from
    a separate `app/client/bin/main.exe` instance while the
    pathological scenario runs. Does it still respond quickly,
    or has the exchange become unresponsive?
- **Read the bot code, not just the scenario.** Look for:
  - _Edits outside `app/bots/` and `app/scenarios/`._ The PR
    should only touch these two directories (plus possibly the
    bots/scenarios tests). Anything else — a change to
    `lib/`, to `dune-project`, to an unrelated app — is
    suspicious and was almost certainly not asked for.
  - _Idiom drift_ — code that doesn't match the rest of the
    project. Common shapes: `Stdlib.List` instead of
    `Core.List`, raw exceptions instead of `Or_error.t`,
    `Result` instead of `Or_error`, unfamiliar
    `Pipe`/`Deferred` patterns, helpers introduced where the
    existing modules already have an equivalent. Compare
    against the existing bots in `app/bots/src/` and
    `app/market_maker/src/` — that's the local idiom.
  - _Tautological tests_ — tests that look like they're
    asserting something meaningful but actually only restate
    what the implementation does. Example: a test that
    constructs an `Order.Request.t`, hands it to the bot, and
    asserts the bot's `submitted` list now contains _that
    same request object_ — that's tautological; it would pass
    even if the bot did nothing useful. A real test asserts
    something _independently computable_: a specific number of
    submitted orders, a specific size distribution, a
    pre-stated price range.
- Comment on at least one thing you'd push back on. If
  everything looks perfect, comment on the _test_: did it
  actually prove the pathology happens? If you can't find
  anything to push back on _and_ the test is real, say so and
  approve.
- Pay extra attention to AI-assisted PRs. If the author flags
  that Claude wrote substantial parts (and they should!), spend
  more time on the diff — the failure modes Claude introduces
  are the ones a careless reviewer would miss.

**Honest reporting.** When you open a PR for a bot you wrote with
Claude's help, say so in the PR description. Briefly note: what you
prompted, what Claude wrote vs. what you wrote, where you pushed
back on its first draft, what you're least sure about. The
expectation is _not_ that you avoid AI — it's that you stay aware
of which parts you have less direct understanding of, and you give
the reviewer a useful starting point.

### 1d: Copy the bots and scenarios into your repo

As your group merges bots and scenarios into the `main` branch of your group repo, run

```sh
git checkout main
git pull
```

to bring them into your local clone of the group repo, and then use `cp` in the terminal
to copy them into the corresponding directory in your own `jsip-exchange` solo repo.
Double-check that your solo repo still successfully `dune build`s.

## Section 2: Build a monitoring dashboard

Now that you (collectively, as a group) have a shared set of bots that put the exchange
under pressure, you each need a way to _see_ the pressure. This section is your first
_vibe-coding_-heavy task where we'll focus on giving Claude high-level goals and care a
lot more about the final product than we do about the details of the implementation.

The dashboard is built using **Bonsai** — the same UI library that
backs `app/monitor`. Bonsai is the library Claude knows worst, so
the verification habits from the warm-up lab matter most here.
Building a real Bonsai UI is the explicit pedagogical goal of this
section; "I'll just print to stdout" defeats the purpose.

Each person will build their own dashboard in their _solo_ repo. The
bots and scenarios you pull from the group repo are the input; the
dashboard itself isn't a group artifact, because it depends on
exchange-side instrumentation that each of you may have done
differently.

### 2a: Scope

The dashboard should be a separate binary (e.g., under
`app/dashboard/`), written using `bonsai_web` — the browser
variant of Bonsai. The terminal-only monitor you saw in Part 2
uses `bonsai_term`, which shares the same state-management
patterns but renders to a terminal grid; learning `bonsai_web`
here gives you a variant with a lot more visual flexibility,
and that lets you iterate on layout in a browser. The
dashboard should connect to a running exchange and display some
informative diagnostic panes.

Before getting to what those are, a quick crash course on the runtime terms
that show up below. (These are deep topics in their own right;
the sketches here are just enough to read the rest of this
section. Once you've got the gist, the it might be helpful to ask
Claude follow-up questions and check the parts you're least
sure about against [Real World OCaml's chapter on the
OCaml Garbage Collector](https://dev.realworldocaml.org/garbage-collector.html).)

- **Heap (in the memory sense).** A region of memory the
  language runtime manages, where OCaml values that don't fit
  in a single CPU register live — every list, record, tuple,
  variant, string, etc. (Distinct from the data structure
  also called a "heap"; the contexts are unrelated.) Each
  OCaml process has one heap that grows and shrinks over its
  lifetime.
- **Word.** The natural unit of memory a computer system works with.
  On a 64-bit machine, one word is 8 bytes. An OCaml record
  with two `int` fields, say, occupies around three words (one
  header word plus one word per field). When we say "the
  exchange's heap holds 50,000 live words," that's roughly 400
  KB of OCaml-managed memory in use.
- **Garbage collection (GC).** The runtime's automatic memory
  reclamation. As your code allocates values, it fills up the
  heap; periodically the GC walks the heap, identifies values
  that are no longer reachable from the process' current context, and
  reclaims them so the memory can be reused. The catch: while
  the GC runs, your code is paused — so allocation-heavy code
  causes frequent pauses, which show up as latency spikes.
- **Collection / GC cycle.** One run of the garbage collector.
  Counted separately by heap (see below).
- **Minor heap / major heap.** OCaml splits the heap in two.
  New values go on the _minor heap_ (small, GC'd often,
  cheaply); a value that survives long enough gets _promoted_
  to the _major heap_ (larger, GC'd less often, more
  expensive). The split is a performance optimization: most
  values are very short-lived, so the cheap collector handles
  the common case.

With those in hand:

**Required panes:**

1. **Process memory.** Live OCaml-heap usage of the exchange
   process, sampled at least once per second using `Gc.stat ()`.
   `Gc.stat` is OCaml's runtime statistics function: it returns
   a record snapshotting the garbage collector's current state
   — how many words are live on each heap, how many GC cycles
   have run, how many words have been promoted from the minor
   to the major heap, and so on. (See the [Gc module
   docs](https://v2.ocaml.org/api/Gc.html#TYPEstat) for the full
   field list, and ask Claude to explain any field you don't
   recognize.) At minimum show `live_words` (total words
   currently reachable — the OCaml-side memory the exchange is
   using right now). Display as a rolling window (last ~60
   seconds), not just a single number — a flat line vs. linear
   growth vs. exponential growth tells you very different
   stories about the pathological bot you're running.
2. **Submit-order latency.** The time from "client calls
   `submit_order_rpc`" to "matching engine has handled it." You'll
   need to instrument the exchange to measure this (see 2b). Show
   as a histogram or as live p50/p90/p99 percentiles over a
   rolling window. (The p-notation just means percentile of the
   distribution: p50 is the median, p90 is the latency the worst
   1-in-10 requests, p99 is the latency the worst 1-in-100
   requests. The latter two are what tell you whether the
   _slowest_ responses got slower, which is usually what matters
   under load.)
3. **Cancel-order latency.** Same shape as submit latency, but for
   `cancel_order_rpc`.

**Encouraged extras (pick at least one):**

- Pipe occupancy: for each subscriber pipe (per-symbol market data,
  audit log, per-session), the current queue length. This will
  tell you immediately when a slow consumer is filling something
  up.
- Per-participant order rate (orders/sec) and
  active-resting-order count.
- The current order book depth for one symbol (live BBO + total
  resting size per side).
- Matching-engine busyness: how often the request queue is
  empty when the matching engine looks for work, vs. how often
  it has a backlog waiting. An approximation that's easy to
  measure: the elapsed time between successive iterations of
  the loop that drains the request pipe (`start_matching_loop`
  in `exchange_server.ml`). When the engine is keeping up, that
  gap is essentially zero; when it can't, the gap grows because
  each iteration is doing more work.

### 2b: Build it with Claude

This is the section where you'll lean on Claude the most. There
are two pieces of work, and we recommend doing them in this order,
so each piece is small enough to review properly:

1. **Exchange-side instrumentation.** Add a new RPC that streams
   per-second snapshots of everything the dashboard needs.
2. **Dashboard binary.** A `bonsai_web` app that subscribes to
   that RPC and renders the panes from 2a.

The advice below applies to both pieces — read it first.

#### General advice that applies to both pieces

- **Plan before prompting.** Plan mode (`Shift+Tab` until you're
  in it) is your friend on multi-file work — and especially on
  UI work. Get Claude to lay out the file structure, the state
  shape, and the API of each module _before_ it writes any code.
  Read the plan critically: where does it land each piece, what
  does each function take and return, what tests does it
  envision? Push back on anything that doesn't match what you'd
  have written yourself.
- **Read the existing monitor.** `app/monitor/` is ~500 LOC of
  working `bonsai_term` code with the architecture you should
  imitate: a _pure state machine_ in `controller.ml` (testable
  without Bonsai), and a _Bonsai layer_ in `term_app.ml` (wires
  the state into a computation, injects events). Steal this split
  for the dashboard — it's the only way you'll be able to test
  anything. The rendering primitives are different in
  `bonsai_web` (HTML/CSS rather than terminal cells), but the
  state-machine split transfers unchanged. Bonsai is also the
  library where Claude's training is shakiest, so the existing
  monitor is your best reference when its answers look fishy.
- **Run the app and look at it.** This is the verification step
  that has no analog in `dune runtest`. The dashboard _renders_;
  the test suite can't tell you it renders the right thing. Plan
  to run the dashboard against `Book_fill` and `Slow_consumers`
  during development and check that the memory pane visibly
  moves.
- **Honest reporting in your debrief.** Note which parts were
  Claude-driven, which parts you wrote by hand, and which Bonsai
  patterns you ended up cross-referencing against the bonsai
  library docs (or the existing monitor) because Claude got them
  wrong.

#### Piece 1: Exchange-side instrumentation

Have Claude add a new pipe RPC (alongside `submit_order_rpc`,
`market_data_rpc`, etc.) that streams a record of all the
metrics from 2a, once per second. The important constraints to
hand Claude are:

- It's a _new_ RPC. Don't piggyback by adding variants to
  `Exchange_event.t` and broadcasting them on the audit log: the
  audit log exists to record exchange events (acceptances,
  fills, cancels, etc.), and conflating it with infrastructure
  metrics is exactly the kind of layering mistake you'd flag in
  a code review of someone else's PR. If Claude proposes this
  shortcut anyway — and it might — push back.
- It exposes exactly the data the dashboard panes need from 2a
  (memory, submit/cancel latency, plus whatever your
  encouraged-extras pane needs). The shape of the record, the
  latency representation, and exactly where the per-RPC
  measurement happens are design choices Claude can make — let
  it. Review the choices.
- Add a `let%expect_test` block for the new RPC's shape in
  `lib/gateway/test/test_rpc_shapes.ml`, same as for every other
  RPC.

#### Piece 2: The dashboard

Once the stats RPC is in place, build the dashboard. Place it
under `app/dashboard/`, structured like `app/monitor/` (pure
controller + Bonsai layer). The dashboard's only job is to
dispatch the stats RPC, fold the per-second snapshots into a
rolling-window state, and render the panes. Claude will produce
most of the code; your job is the planning, the verification,
and pushing back on Bonsai patterns that look invented.

### 2c: Calibrate

Before moving to Section 3, run each pathological scenario _with
your dashboard open_ and write down (in your solo repo's notes —
this will be useful raw material for your debrief and for picking
Section 3 exercises):

- What does the memory pane do when each bot runs? Is it bounded
  growth, linear growth, exponential?
- What do the submit and cancel latency percentiles do?
- Do any of the "extras" your dashboard tracks reveal additional problems?

These observations are the input to Section 3 — you're going to
fix the specific problems you measured, not generic ones.

---

## Section 3: Make the exchange survive

You now have:

- Four (or more) pathological bots that exert specific kinds of
  pressure, merged into the group repo.
- A dashboard that visualizes the pressure on your own exchange.
- Your own observations (from 2c) of how your exchange degrades
  under each pathology.

Section 3 is a menu of robustness exercises. **This section is
individual work, in your solo repo.** Each of you has your own
exchange and your own dashboard, and you'll defend your own. Pick
exercises based on what your dashboard told you was actually
broken; pick from each subsection (3a, 3b, 3c, 3d) at least once.
Some exercises build on each other; dependencies are called out.

**Working with Claude on Section 3.** You're free to use Claude
on these exercises — the verification habits from the warm-up
lab matter most here, since there's no group-review safety net
on solo-repo work. A few specific notes:

- These exercises are largely independent within each subsection
  — you don't need to finish 3a.1 before starting 3b.2. If you
  have multiple Claude sessions or terminals open, you can have
  one session working on (say) a rate-limit implementation while
  you're hand-reviewing the diff of a separate session's pipe-
  bounding work. _Don't_ commit something from a parallel
  session without reading the diff yourself; the parallelism is
  for throughput, not for skipping the review step.
- Be your own reviewer. Open the diff in VSCode before you
  commit, the same way a group-mate would on a PR. Walk the same
  three buckets from Section 1c: edits outside the file you
  asked about, idiom drift, tautological tests. If you find
  yourself unable to explain a line of the diff, that's the
  signal to slow down and ask Claude (or a TA or your group-mates) what
  it does.
- Tests are especially important here because there's no second human
  reviewer to catch a vacuous one. For each fix, ask: what would
  fail before this change and pass after? Did Claude write
  exactly that test? If not, write it yourself.
- Run the dashboard while you test. The fix should change the
  shape of at least one pane — the slow-consumer fix should
  bound that subscriber's pipe occupancy; the resting-order cap
  should bound the per-participant counter; etc. If the
  dashboard _doesn't_ visibly change, that's either a bug or a
  signal that the dashboard isn't measuring the right thing.
- Honest reporting in your debrief — same rule as everywhere
  else in this part. If Claude wrote most of an exercise, note
  which parts you wrote vs. which you accepted, and what you
  pushed back on.

**Cross-cutting principle: every restriction is a trade-off.**
Every limit you impose makes your exchange less attractive to
_some_ legitimate use case. A real participant might quote a
large ladder of resting orders (book-filler-shaped traffic); a
rate limit on cancels punishes high-frequency market makers; a
slow-consumer disconnect alienates clients on slow links. For
each exercise, you must:

1. State the limit you're imposing (with units).
2. State which legitimate workflow it would interfere with.
3. State how a competing exchange could undercut you by _not_
   imposing this limit, and why you've decided the trade-off is
   still worth it.

Write these three statements in your solo repo's notes or commit
message for the exercise. They're as important as the code, and
they'll feed into your Section 4 debrief.

### 3a: Bounded pipes (where unbounded buffering hurts most)

This is the family of fixes that addresses the slow consumer
and, to a lesser extent, the spammer. To frame what these fixes
do, two terms worth being clear on:

- A **buffer** is a chunk of memory the exchange keeps in between
  producing an event and the client actually reading it.
  Async's `Pipe` is the buffer in our case. Buffers are
  unavoidable — the producer and consumer don't run in lockstep
  — but a buffer that can grow without limit has the potential to
  crash the exchange by running the machine out of memory.
- **Backpressure** is the general technique where, when a
  consumer can't keep up, the producer is forced to slow down
  rather than continuing to produce into a growing buffer.
  Async's regular `Pipe.write` gives you backpressure for free:
  it returns a `Deferred.t` that doesn't become determined until
  the consumer has caught up, so a `let%bind` on it makes the
  producer wait. `Pipe.write_without_pushback*` _opts out_ of
  this — it returns immediately, the producer keeps going, and
  the buffer is now your problem to bound by some other means.

Currently every pipe the exchange writes to opts out of
backpressure, so a slow reader can let the buffer grow
indefinitely. Every per-symbol market-data subscriber, and every
session feed, are all vulnerable.

Concretely (read these files before you start):

- `lib/gateway/src/dispatcher.ml:56` — `push_market_data` calls
  `Pipe.write_without_pushback_if_open`.
- `lib/gateway/src/session.ml:18` — `Session.push` is the same.

The pipes themselves are created with `Pipe.create ()` in
`Dispatcher.subscribe_market_data` and `Session.create`. That
gives each pipe Async's default size budget of zero — meaning a
single buffered value is enough to trigger pushback on a regular
`Pipe.write`. But the code on the writer side calls
`Pipe.write_without_pushback_if_open`, which bypasses the budget
entirely. So in practice the pipes accept events as fast as the
matching engine produces them, and a stalled reader lets the
internal buffer grow without bound.

#### 3a.1: Bound each pipe and pick a policy when full

For the pipes mentioned above, choose what should
happen when the writer outpaces the reader. The reasonable choices:

- **Block the writer.** Use `Pipe.write` instead of the
  no-pushback variant. But the writer here is the matching
  engine, and it's writing the same event to many subscribers
  at once (a _fan-out_: one producer feeds many consumers).
  Blocking on a single subscriber's pipe means _every_ client's
  RPC slows down because _one_ client can't keep up. Almost
  never the right call for a fan-out like ours.
- **Drop the newest event.** When the pipe is full, throw the new
  event away. Cheap; means the slow client misses the most recent
  events.
- **Drop the oldest event.** When the pipe is full, pop the front
  of the pipe to make room. Means the slow client gets the latest
  events but misses some history. Often the better choice for
  market data, where stale BBOs are useless.
- **Disconnect the slow client.** Close the pipe, log a warning,
  remove the subscriber. Honest about the failure mode; the slow
  client has to reconnect.

Pick a policy _per pipe family_ (market data, session). They
don't have to match. Document the choice in the dispatcher's
`.mli`. Make the per-pipe size budget configurable rather than a
magic constant — `Dispatcher.create` is the natural place to take
it as an argument (and `Exchange_server.start` is the natural
place to plumb it through from a server-level config).

**Testing.** One reasonable approach: construct a
`Dispatcher.t`, subscribe a market-data (or session) pipe whose
reader you never read from, then call `Dispatcher.dispatch` with
a sequence of events larger than the budget you configured.
Observe the pipe's contents (`Pipe.read_now_at_most` /
`Pipe.length_now`) and assert that what's there matches your
policy:

- For _drop-newest_: the pipe contains the first N events you
  dispatched and none of the later ones.
- For _drop-oldest_: the pipe contains the _last_ N events.
- For _disconnect_: the pipe is closed (`Pipe.is_closed
reader`), and the subscriber is no longer in the dispatcher's
  internal registry.

That's one way; another reasonable shape is a `let%expect_test`
that prints a one-line state summary after each event and uses
`dune runtest --auto-promote` to lock in the expected sequence.
Pick whichever lets you read the test most easily. Whatever you
pick, don't reimplement your policy inside the test — assert against
hand-constructed expected values.

#### 3a.2: Slow-consumer disconnect threshold

Even if you picked "drop oldest" for 3a.1, you probably want a
_second_ line of defense: if a consumer has been at-or-near pipe
capacity for more than N seconds, disconnect them. The first defense
keeps memory bounded; the second keeps the dispatcher from spending
CPU cycles forever on a client that's clearly broken.

Builds on 3a.1. Add a periodic check inside the dispatcher (or in
`Exchange_server`'s background task) that walks subscriber bags and
closes any pipe that's been full for too long.

### 3b: Order-side rate and capacity limits

This is the family of fixes that addresses the spammer, the book
filler, and the cancel storm. Each protects a different exchange
resource.

#### 3b.1: Per-participant resting-order capacity

The book filler's whole purpose is to pile resting orders. Add a
limit: a participant may hold at most N resting orders per symbol
(or across all symbols, your choice; both are defensible). When a
participant's next Day order would put them over the limit, reject
it with a new `Cancel_reason.Resting_order_cap`.

The hard part is data: you need an efficient per-participant
running count. Where does it live, and how is it kept in sync with
fills, cancels, and end-of-day? Discuss with your group before
implementing.

**Tests:** verify the limit is enforced, verify a fill that brings
the participant back under the limit allows a new order, verify
end-of-day cancellation correctly decrements.

#### 3b.2: Per-participant submit rate limit

The spammer submits hundreds of orders per tick. Add a rate
limit on `submit_order_rpc` capping each participant at N
orders per second, where N is whatever number your dashboard
suggests a well-behaved client will never come close to.
Over-budget submits are rejected with
`Order_reject { reason = "rate limit exceeded" }`.

Two standard algorithms work here; pick whichever you find
easier to reason about:

- **Sliding window.** Keep track of
  the timestamps of the last N submits for each participant.
  When a new submit arrives, drop entries older than one
  second from the head of the list. If the list is then
  smaller than N, accept and append; otherwise reject. This is
  literally "in the last second, how many have they sent?"
- **Token bucket.** Each participant has a counter, the "token
  bucket", that the exchange increments at a steady rate of N
  tokens per second (capped at some maximum). Every submit
  costs one token; submitting when the bucket is empty
  produces a rejection. This is cheaper than the sliding
  window (a single integer per participant instead of a list)
  and allows occasional bursts up to the bucket's max size.

Either is fine. Document which you picked, and why.

Implementation note: you have a per-participant `Session.t` already,
which is the natural place to hang the rate-limit state. The
matching engine should not have to know about rate-limit state;
keep this at the gateway level.

**Tests:** verify that an in-budget burst is accepted; verify
that the (N+1)st submit in the same window is rejected; verify
that after enough time has passed (whatever your implementation
considers a refill / window-slide) submits are accepted again;
verify that two participants have independent limits, so one
flooding doesn't lock out the other.

**Trade-off note:** a per-participant cap doesn't help if the
spammer logs in as ten different participants. Combining this with
3b.4 (login rate limit) is the natural follow-up.

#### 3b.3: Per-participant cancel rate limit

Same as 3b.2 but for `cancel_order_rpc`. The cancel storm is the
obvious motivator. Note that the cancel storm submits _and_ cancels,
so it'll also trip 3b.2 — but 3b.3 lets you set a tighter cancel
limit specifically.

The interesting design question: should the rate limit be per
_action_ (submit / cancel separately) or per _total operations_?
Real exchanges typically combine them as "messages per second" with
weights. Document the decision you make.

#### 3b.4: Per-connection login + session limit

The login storm exploits the fact that a misbehaving client can
open arbitrarily many TCP connections, log in as different (or even
the same) participant, and keep them all alive. Cap:

- The number of `login_rpc` calls per source IP per second.
- The total number of concurrent active sessions per source IP.

The peer's IP comes from `Rpc.Connection.peer_addr` or via the
`(Socket.Address.Inet.t, …)` parameter to `Rpc.Connection.serve`'s
`initial_connection_state` callback.

#### 3b.5: Per-symbol total book-depth cap

Even with per-participant caps from 3b.1, a coordinated set of
participants can still flood a single symbol. Add a global cap on
the total number of resting orders per symbol (or, more usefully,
total resting _shares_ per side per symbol — that's what affects
matching latency).

Real exchanges do enforce something like this — usually as a
soft limit on book depth past which incoming orders that would
otherwise rest are instead rejected. The intuition is: a book
that's already very deep at every price level isn't getting more
useful to the matching engine, but each additional resting order
costs CPU and memory. Once you've hit the depth cap, an
incoming marketable order still matches normally (it doesn't
need to rest), and an incoming non-marketable order is rejected
with `Order_reject { reason = "book depth cap exceeded" }` —
the participant gets a clear signal to either price more
aggressively or wait for the book to thin out.

### 3c: Cheaper hot paths

A _hot path_ is a piece of code that runs on every request,
where every microsecond shows up in the exchange's throughput
or latency — the matching loop, the dispatcher's per-event
fan-out, the gateway's RPC handlers. The fixes in 3a/3b
_limit_ pressure. The fixes in this section make the exchange
_tolerate_ pressure better by making the hot paths cheaper.

#### 3c.1: Cheap-path rejection

A flood of `Order_reject`-bound orders (unknown symbol, invalid
size) currently still goes through the request
queue and the dispatcher. You can detect malformed orders at the
gateway level _before_ they enter the queue and reject them inline,
skipping the engine, the dispatcher, and the audit log entirely.

The trade-off: the audit log no longer records these rejections,
which is a legitimate signal during incident investigation. One
compromise: still dispatch a count/summary to the audit log
periodically, but don't dispatch each one.

#### 3c.2: Bounded request queue's behavior under saturation

`Exchange_server.start` already caps the request queue at 1024
entries with `Pipe.set_size_budget`. What happens to a
participant when the queue is full? Currently the RPC handler
calls `Pipe.write_if_open`, which returns a `Deferred.t` that
the handler awaits — i.e., the RPC call is slow-but-not-failed.
That's backpressure (see Section 3a's intro for the term),
which is honest, but it also means a single fast participant
can occupy the queue and slow everyone else down.

Improvements to consider: per-participant queue slots; a max-wait
timeout after which the submit RPC returns an error instead of
queueing; an admission policy that refuses requests when the queue
is more than X% full.

### 3d: Observability and audit (so you can prove the fix worked)

#### 3d.1: Reject-reason counters

Add a per-`Cancel_reason.t` and per-`Order_reject reason` counter,
exposed via the stats RPC. The dashboard can then show "how many
orders got rejected for rate-limit-exceeded vs.
duplicate-client-id vs. ..." over time. This is the kind of signal
an exchange operator uses to spot a new pattern of abuse.

#### 3d.2: Per-participant resource usage

The dashboard already shows process-level memory and aggregate
latency. Add a per-participant breakdown of:

- Active resting orders (count + total shares).
- Orders submitted in the last minute.
- Cancels in the last minute.
- Pipe occupancy (for that participant's session).

This lets the on-call operator quickly identify _which_ participant
is causing trouble — the difference between "we're under attack"
and "we're being attacked by 'Spammer42'."

---

## Section 4: Debrief

End-of-part-3, write up what happened. Two artifacts:

**Group debrief** — one document in the group repo
(`doc/part3-debrief.md`), written collaboratively. Cover:

1. **What each pathological bot actually does to an exchange.**
   What pressure does it apply, and on what timescale does the
   effect become visible? Include sampled metrics from at least
   one group-member's dashboard (memory curve, latency
   percentiles) — not just prose descriptions.
2. **What surprised you about each other's bots.** Which
   pathology turned out to be worse than expected? Which one was
   tamer? Where did running the merged set reveal an interaction
   between two bots that neither produced alone?
3. **A note on group work.** Where did the PR review process
   catch real issues? Where did it fall flat? What would you
   change about the workflow if you did this again?

**Individual debrief** — a short note in your _solo_ repo
(`doc/part3-debrief.md`), written by each of you about your own
exchange. Cover:

1. **What your dashboard showed during each scenario.** Memory,
   latency, anything else you instrumented. Note the panes that
   moved and the panes that didn't.
2. **Which Section 3 exercises you picked, and why.** Tie each
   pick to the dashboard observation it was responding to.
3. **What changed in the dashboard after your fixes.** Side-by-
   side numbers if you have them.
4. **What you'd fix next.** Pathologies you observed but didn't
   address, and why you'd prioritize them.
5. **A note on AI use.** What worked well? Where did Claude
   consistently miss things you had to catch? Did the
   verification habits from the warm-up lab survive the larger
   projects?

These are the artifacts the instructors will read to figure out
how the this part went — much more useful than a list of PR links or
commit hashes.

---

## Stretch: let clients modify orders

A natural extension to the exchange you've now hardened: give
clients a way to **modify** a resting order — change its price or
size in place — instead of cancelling it and submitting a fresh
one. This is sometimes called _cancel/replace_ or _amend_, and
essentially every real exchange offers it.

This is a solo-repo exercise, and it's deliberately placed here
rather than in Part 2 for a reason. A modify operation touches the
core wire protocol — most likely a new RPC, and possibly new
`Exchange_event.t` variants — and in Part 2 you had no protocol to
diverge from. Now you do: your group spent Section 0b agreeing on a
canonical `Exchange_event.t` and RPC set so you could all run each
other's bots. Adding modify in your own repo will move those
digests again, so treat it as a fork you're exploring on your own
exchange, not something you push to the group repo. The
upside is that you now have the whole ecosystem — market maker,
noise trader, the pathological bots — sitting in your tree, so
you're free to teach any of them to use modify and watch what
changes.

**Why a modify is more than a convenience.** On the surface,
modifying an order looks identical to cancelling it and submitting
a replacement. The interesting part — and the thing worth getting
right — is **price-time priority**. Resting orders match best-price
first, and among orders at the same price, earliest-arriving first
(the ordering your Part 1 `find_match` work established). A
participant's _place in that queue_ is valuable. Real exchanges
exploit this: a modify that only _shrinks_ an order keeps its place
in line, while a modify that reprices or grows it goes to the back —
which is exactly what a cancel-and-resubmit would have done anyway.
So a native modify is strictly better than cancel/replace for the
shrink case (you keep priority) and no worse for the rest (you also
get atomicity — there's no window where your order is missing from
the book and someone can slip ahead). Capturing that asymmetry
correctly is the heart of the exercise; the plumbing is routine by
now.

**Design questions to settle for yourself** (there's no single
right answer — decide, and be ready to defend it):

- How does a modify identify the order, and how do client-facing vs.
  internal order IDs behave across a reprice?
- A reprice can make an order immediately marketable. What runs it
  through matching, and what events come out?
- What does a modify down to a size at or below what's _already
  filled_ mean? What about a modify of an order that's already gone
  (filled or cancelled)?
- How do these outcomes surface to the client — reusing existing
  events, or new ones — and what does that cost you in wire
  compatibility?

**Use the feature.** Once it works, rework one of your bots to
use it. The dynamic market maker is the obvious candidate: instead
of cancelling its whole ladder and re-posting on every fill, have
it modify quotes in place where it can, keeping queue position
through size adjustments.

As always, cover the new behavior down with tests — especially the
cases that distinguish a modify from a plain cancel/replace (a
shrink that keeps priority vs. a reprice that loses it) — and keep
`test_rpc_shapes.ml` current for any protocol change.

---
