# AI Tools Intro

Today you'll start using **Claude Code**, a terminal-based AI coding
agent, on the `jsip-exchange` codebase. You've already spent the program so
far building OCaml fluency and learning this codebase unaided, and this
morning you got your first taste of Bonsai. Now we add an AI assistant to
your toolkit.

The program goal is to **use AI tools to help you learn and be more
productive _without turning over all your thinking to an LLM_.** Keep that in
mind today. Claude Code is good — it reads and edits files, runs shell
commands, and iterates against `dune build` and `dune runtest` on its own
until they pass. That means by the time it hands control back to you, the
obvious failures (type errors, broken tests) are already gone. **A green
build is the start of your job, not the end of it.** The skill you're
building today is what happens _after_ green: reading the diff, questioning
the tests, checking idiom, and noticing what _didn't_ change.

The introduction to AI tools has six steps:

1. **Intro talk**
2. **Set up and configure Claude Code**.
3. **Install the provided `CLAUDE.md` and skills**.
4. **Exercise: write the P&L module, with and without `CLAUDE.md`**.
5. **AI-as-educator exercise** (TA-facilitated).
6. **Ask Claude to review your code**.

Everything below is step-by-step. Work through it in order.

---

## 2. Set up and configure Claude Code

1. **Launch Claude Code and log in.** From the repo root, run:

   ```sh
   claude
   ```

   On first launch Claude Code asks you to authenticate (you can also trigger
   this any time with `/login`). We'll provide you with an **access code** —
   when prompted, choose the "Claude account with subscription" login method. Part of the flow happens in a browser: if the terminal prints a URL,
   open it on your Mac, sign in or paste the access code there, then copy the
   confirmation code back into the terminal if it asks for one. Grab a TA if
   you get stuck — this is the one step everyone does once and never again.

   Once you're logged in, ask something harmless to confirm it works,
   e.g. _"What does `lib/order_book` do? Don't change anything."_

2. **Turn on the `Learning` output style.** Run:

   ```
   /config
   ```

   select **Output style**, and choose **Learning**. In this mode Claude
   explains its thinking as it goes ("Insights") and hands you small,
   pieces to write yourself — it drops `TODO(human)` markers in the
   code where you should fill in. That's the point of today: stay in the loop
   instead of letting Claude do all the thinking.

   The menu saves your choice to this project's `.claude/settings.local.json`.
   To make `Learning` your default in **every** project, set it in your user
   settings instead — open `~/.claude/settings.json` and add:

   ```json
   {
     "outputStyle": "Learning"
   }
   ```

   An output-style change takes effect on your next session (or after you run
   `/clear`).

3. **Understand permission modes — and stay on `default`.** Press
   `Shift+Tab` to cycle through the modes:

   - **default** — Claude asks before each edit or command. **Use this all
     afternoon.**
   - **accept-edits** — auto-accepts file edits. Don't use it yet; the whole
     point today is to read every diff.
   - **plan** — Claude proposes a plan and makes no edits until you approve.
     Useful for multi-file changes.
   - **auto** — Claude does most things without asking, subject to background safety checks.

   For more information, see [permission modes](https://code.claude.com/docs/en/permission-modes) in the Claude Code docs.

4. **Pre-approve a few safe commands** so you're not approving the same `dune`
   call fifty times. Type:

   ```
   /permissions
   ```

   and add: `Bash(dune build:*)`, `Bash(dune runtest:*)`,
   `Bash(dune fmt:*)`, `Bash(git status:*)`, `Bash(git diff:*)`,
   `Bash(git log:*)`. Do **not** pre-approve `git commit`, `git push`, or
   anything with `rm`, `reset`, or `checkout` — you want to confirm those by
   hand.

---

## 3. Install the provided `CLAUDE.md` and skills

We're adding two kinds of artifact to the upstream `jsip-exchange` repo you
forked. You'll pull them into your fork with a one-time setup and a
merge.

- **A project `CLAUDE.md`.** A short, opinionated file that Claude Code
  auto-loads at the start of every session in this repo. It primes Claude on
  things you'd otherwise repeat in every prompt: conventions (use `Core` not
  `Stdlib`, `Or_error.t` for fallible operations, tests are `let%expect_test`,
  the local OCaml style) and project context — including that you're here to
  learn, so it should point you at existing code rather than rewrite it and
  flag when you're about to skip a concept. One way to keep them straight: the
  `Learning` output style (step 3) sets _how_ Claude teaches; the `CLAUDE.md`
  sets what it knows about _this project_. You'll see its effect directly in
  step 4.

- **A set of skills.** A _skill_ is a bundle of instructions Claude pulls in
  on demand when a task matches (the skills reference is in `doc/` if you're
  curious how they work). We're providing several, adapted for this project:
  `ocaml-style` and `ocaml-ppx` for the local OCaml conventions,
  `code-review`, and `bonsai-web` / `frontend-design` for UI work. You won't
  exercise these this afternoon — they matter most later, especially
  `bonsai-web`: Bonsai is the library Claude may not know well, and you'll build a
  Bonsai dashboard later in the program. Installing them now means they're
  ready when you need them.

Steps:

1. If you haven't already (run `git remote -v` to see what you've currently set up), add the upstream repo as a remote:

   ```sh
   git remote add upstream git@github.com:jane-street-immersion-program/jsip-exchange.git
   ```

2. **Commit any uncommitted work first** — the merge won't run on a dirty
   tree (`git status` should be clean).

3. **Pull in the updates and push them back to your fork:**

   ```sh
   git fetch upstream        # get the latest commits from the original repo
   git merge upstream/main   # merge them into your local main
   git push origin main      # push the result back to your fork
   ```

   This puts `CLAUDE.md` at the repo root and the skills under
   `.claude/skills/`.

4. **Restart Claude Code** (`Ctrl+C`, then `claude` again) so it picks up the
   new `CLAUDE.md`. Skills load on demand, so nothing extra is needed for the
   skills.

---

## 4. Exercise: write the P&L module, with and without `CLAUDE.md`

**Goal:** see for yourself what a good `CLAUDE.md` buys you. You'll have
Claude implement the same feature **twice, one run after the other** — once
with no project memory, once with the `CLAUDE.md` from step 3 — and compare
both the code and how Claude behaved.

The feature is the **Per-participant P&L tracking** stretch exercise from the
end of `doc/exercises-part-1.md`. (If you've already built it, pick another
exercise you haven't gotten to and adjust the prompt below.) Read that
exercise now so _you_ know what good output looks like — you can't judge
Claude's work if you don't understand the task.

Each run lives on its own throwaway **git branch**. A branch is an
independent line of work: commits you make on it don't touch `main` until you
decide to merge them, and if an experiment goes nowhere you can delete the
whole branch with no trace. You haven't needed branches yet — here they let
each run be a self-contained experiment you can keep or throw away. (`git
switch -c <name>` creates a branch and moves onto it; `git switch <name>`
moves between branches that already exist.)

Start from a clean `main`:

```sh
git status     # should be clean before you start
```

### Run 1 — without the `CLAUDE.md`

1. Make a branch for this run and delete the `CLAUDE.md` so Claude can't read
   it at all. (Don't just rename it — Claude might still open the renamed
   file. Deleting is safe: it's preserved in your git history, and you'll
   restore it in a moment.)

   ```sh
   git switch -c pnl-without
   rm CLAUDE.md
   ```

   Restart Claude Code (`Ctrl+C`, then `claude`) so it starts with no project
   memory loaded.

2. Give it this prompt:

   > Implement a per-participant P&L tracking module. Create
   > `lib/pnl/src/pnl.{ml,mli}`. It should track, per participant and symbol,
   > current inventory, running cost basis (for average entry price), and
   > realized cash. Expose `apply_fill : t -> Fill.t -> t`,
   > `apply_trade_report : t -> Trade_report.t -> t` (refreshes the reference
   > price used for unrealized P&L), and a `summary` function returning a
   > per-symbol breakdown plus the total. Realized P&L is cash from closed
   > positions; unrealized is `shares * (reference_price - average_entry_price)`.
   > Add expect tests that drive it through some
   > hand-rolled fills and a trade print. Set up the dune files too.

   Let it run until `dune build` and `dune runtest` pass, **reading each diff
   as you approve it** — don't blind-accept. With the `Learning` style on,
   Claude will pause and ask you to fill in a `TODO(human)` or two; write those parts yourself —
   that's the style working as intended.

3. Restore the `CLAUDE.md`, commit the run, and save its diff:

   ```sh
   git restore CLAUDE.md
   git add -A && git commit -m "P&L, no CLAUDE.md"
   git diff main > /tmp/pnl-without.diff
   ```

   (`git restore` brings the `CLAUDE.md` back from your last commit. Restoring
   it before you commit keeps it out of the diff, so the diff is purely
   Claude's work.)

### Run 2 — with the `CLAUDE.md`

1. Go back to clean `main` and branch again — this time the `CLAUDE.md` is in
   place:

   ```sh
   git switch main
   git switch -c pnl-with
   ```

   Restart Claude Code so it loads the `CLAUDE.md`.

2. Give it the **exact same prompt** as Run 1, and again let it reach a green
   build and tests, reading each diff.

   This time, watch what the `CLAUDE.md` changes. Both runs explain
   themselves and hand you `TODO(human)` pieces — that's the output style, on
   for both. What may differ is whether Claude asks you questions, follows the repo's
   conventions without being told (`Core`, `Or_error.t`, expect tests, a
   tight `.mli`), lands the module in the right place, or avoids re-deriving
   things the project already documents.

3. Commit and save the diff:

   ```sh
   git add -A && git commit -m "P&L, with CLAUDE.md"
   git diff main > /tmp/pnl-with.diff
   ```

### Compare

Compare on two axes — the **code**, and Claude's **behavior while producing
it**.

First the code. Put the two diffs side by side (`diff /tmp/pnl-without.diff
/tmp/pnl-with.diff`, or open both in VSCode) and look for differences in:

- **Idiom** — `Core` vs `Stdlib`? `Or_error.t` vs raw exceptions?
  `let%expect_test` vs something else?
- **`.mli` tightness** — did one version expose internals the other kept
  private?
- **Test quality** — are the tests checking real numbers you can verify by
  hand, or just asserting whatever the code produces? Did either reimplement
  the P&L math inside the test (a tautological test that proves nothing)?
- **File placement and dune setup** — did both land in `lib/pnl/` with the
  conventional dune stanzas?
- **What Claude assumed** vs what the codebase actually does.

Then the **behavior**. Did one run ask a clarifying question, point you at
existing code, or follow conventions you never stated — while the other just
guessed and went its own way? (Both runs explain themselves and hand you
`TODO(human)` pieces; that's the output style, constant across both. What
you're looking for is what the `CLAUDE.md` adds on top.)

**Write down any concrete differences.** Both runs likely got the code building — so every
difference you find is a quality difference the build could not catch. That's
the whole lesson: `CLAUDE.md` steers Claude toward _your_ conventions before
you have to correct it, and the compiler will never tell you when it didn't.

### Reflect, then clean up

Before you move on, look at how _far_ Run 2 actually got. Claude reached a
green build — but did it finish the task? Check the diff against your reading
of the P&L exercise:

- Does it track realized **and** unrealized P&L, or just one?
- Do the tests cover a sell that closes a position, or only buys?
- Is the reference price actually refreshed by `apply_trade_report`, or
  stubbed out?

If something's missing or thin, write down the single prompt you'd give
Claude next to push it the rest of the way. That question — "the build is
green, so what's still undone?" — is the whole point of step 4.

Carry one run forward so `main` has a P&L module to build on, and so the rest
of today happens on a single branch. Merge the run you did _with_ the
`CLAUDE.md` into `main`, then delete both throwaway branches:

```sh
git switch main
git merge pnl-with                   # bring your chosen run onto main
git branch -D pnl-without pnl-with   # delete the throwaway branches
```

---

## 5. AI-as-educator exercise (TA-facilitated)

Next, your TAs will run an
**AI-as-educator** exercise. The goal: practice using Claude to _learn_
unfamiliar code or concepts, and then prove to yourself you actually learned it — by
teaching it to someone else with Claude closed.

1. **Pair up and split the two topics** — one partner takes each:

   - **Partner A — the price process.** The Ornstein-Uhlenbeck "fundamental
     price" process in `lib/fundamental/`: what an OU process is, how this
     code discretizes it, what `volatility_cents_per_sec` means in concrete
     numbers, and how it stays reproducible from a seed.
   - **Partner B — pushback semantics.** How `Async.Pipe` pushback works and
     how `lib/gateway/` (the dispatcher and session code) uses pipes today:
     `Pipe.write` vs. `Pipe.write_without_pushback`, and what the tradeoffs are.

2. **~15 minutes with Claude.** Read the code, ask follow-ups, ask for mental
   models or diagrams. Take notes — but **do not paste Claude's prose
   verbatim** into your notes. Put it in your own words, which forces you to
   actually process it.

3. **Teach your partner, with Claude closed (~5 min each).** Explain your
   topic. Your partner asks questions. When you don't know an answer, **say
   so and go find it in the code** — don't guess, and don't make something up
   that sounds plausible. (Sounding plausible while being wrong is exactly
   Claude's failure mode; don't imitate it.)

4. **Debrief as a pair:**
   - What did Claude get _wrong_ that you caught when you tried to explain it?
   - What gap in your understanding did you only notice when you had to
     explain it?
   - Where did Claude feel like a real teacher, and where like a
     confidently-wrong textbook?

An important takeaway: "Claude told me" is not the same as "I understand."
The only reliable way to close that gap is to check Claude against the actual
code and to try to reproduce the explanation yourself.

---

## 6. Ask Claude to review your code

Now flip Claude into the reviewer's seat — on code _you_ wrote.

1. Start a fresh Claude Code session, hit `Ctrl` + `Tab` once to switch to "accept edits" mode, and have Claude review **all the code
   you've added to your fork** so far. Use a prompt like:

   > Look at all the changes I've made on top of the original starter code (use git to
   > find them — e.g. `git diff upstream/main`). Review them as if you were doing a code
   > review: correctness issues, idiom problems, missing tests, unclear naming — anything
   > you'd flag. Don't change any code, just leave code review comments and give me any
   > high-level feedback.

Once Claude finishes, you can run `git diff` or use the VSCode source control panel (`Ctrl` + `Shift` + `G`) to see the code review comments Claude left for you.

2. **Sort every comment Claude makes into one of four buckets:**

   - **Actionable** — a real issue worth fixing.
   - **Style nit** — technically fine, low value.
   - **Hallucinated** — refers to code, functions, or behavior that doesn't
     actually exist. (Check against the real file before believing it.)
   - **Missed a real issue** — something you know is wrong that Claude said
     nothing about.

3. **Pick one comment to act on and one to push back on.** Make the fix for
   the first. For the second, write one sentence on _why_ Claude is wrong or
   why you're choosing not to follow it. Be ready to defend both choices —
   this is exactly the muscle you'll use in real code review.

4. **Debrief (whole group):** one comment Claude got genuinely right, and one
   it got wrong or hallucinated. How quickly could you tell the difference,
   and what told you?

The takeaway mirrors step 5 from the other direction: Claude is a useful
reviewer, but it is _your_ judgment that decides which comments are real.
Treat its review as a list of hypotheses to evaluate, not a list of
instructions to follow.

---

## Further reading

If you want to go deeper after today, these are the useful entry points in
the official Claude Code docs (<https://docs.claude.com/en/docs/claude-code>):

- **Best Practices** — <https://code.claude.com/docs/en/best-practices>
- **Slash commands** (`/permissions`, `/login`, `/config`, …) —
  <https://docs.claude.com/en/docs/claude-code/slash-commands>
- **Memory / `CLAUDE.md`** (what you compared in step 4) —
  <https://docs.claude.com/en/docs/claude-code/memory>
- **Output styles** (the `Learning` mode you set in step 2) —
  <https://docs.claude.com/en/docs/claude-code/output-styles>
- **Skills** (like the ones you installed in step 3) —
  <https://docs.claude.com/en/docs/claude-code/skills>
- **Common workflows** (multi-step patterns and tips) —
  <https://docs.claude.com/en/docs/claude-code/common-workflows>
- **Settings** (`settings.json` and every key it accepts) —
  <https://docs.claude.com/en/docs/claude-code/settings>
