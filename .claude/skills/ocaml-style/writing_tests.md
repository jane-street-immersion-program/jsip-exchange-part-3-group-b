---
summary: Read for detailed OCaml test-writing guidance and good expect test practices.
---

# Writing Tests

Good tests in this tree show the real artifact a human would inspect while
debugging. Prefer preserving the real shape of the output and explicitly
trimming noise. Trim unstable fields, not the substance of the artifact.

## Workflow: start from real output

- Snapshot the real output first; then explicitly elide unstable fields. Trim
  noise, not signal.
- Start by printing or capturing the artifact you actually care about.
- Only after seeing the real output should you decide what is too noisy.
- Prefer removing or rewriting specific unstable fields over replacing the whole
  artifact with a bespoke summary.
- Do not replace a rich artifact with derived booleans like `contains_*`,
  `mentions_*`, or `*_matches` unless there is no stable richer representation.

## Prefer `let%expect_test` by default

- Default to `let%expect_test` for behaviorful tests. It supports both
  assertion-style and printing-style evidence, so it scales better as a test
  grows.
- Inside an expect test, use `[%test_result]` when a simple equality check is the
  clearest assertion.
- Keep `let%test` / `let%test_unit` for tiny pure checks, especially when the surrounding
  code already uses that style.
- Use `let%quick_test` when you want to check an invariant over many inputs, and keep
  the assertion inside the property body small and direct (often `[%test_result]`).

## Prefer readable expect tests over clever ones

- Print structured data with `print_s`, `[%sexp]`, or `[%message]`.
- Put each `[%expect]` block immediately after the print it is checking.
- Show state transitions step by step instead of printing one giant final blob.
- Keep snapshots focused by eliding unstable or irrelevant fields while
  preserving the real structure.
- If the raw output is noisy, capture it and post-process it so the snapshot
  still shows the real artifact.
- Prefer rewriting or sanitizing unstable fields over hiding the artifact behind
  `contains_*`, `mentions_*`, or `*_matches` summaries.
- When output is sexp-shaped, prefer Sexpresso-style rewriting to selectively
  keep, drop, or deselect noisy fields while preserving the useful structure.
- Useful tools here include `[%expect.output]`,
  `Expect_test_helpers_core.expect_test_output`, and
  `Sexpresso.rewrite_expect_output`.
- An empty `[%expect {| |}]` is fine when the test is asserting "no output" or when a
  property test should succeed silently.

```ocaml
let%expect_test "writes a warning only for the bad input" =
  print_s [%sexp (run "good" : Result.t)];
  [%expect {| (Ok ()) |}];
  print_s [%sexp (run "bad" : Result.t)];
  [%expect {| (Error "bad input") |}]
;;
```

## Keep setup helpers, but keep behavior in the test body

- Extract helpers for repetitive plumbing: temp dirs, fake inputs, queue setup,
  constructors, fixture loading.
- If a test file keeps threading the same harness arguments or derived paths
  through many calls, introduce a shallow local wrapper with sensible defaults
  rather than repeating that plumbing at every callsite.
- Do not hide the key behavior or assertion behind a helper with a vague name.
- A good helper makes the test shorter without making the control flow harder to see.
- If a directory has many focused test modules, an aggregator file that simply includes
  them is fine.

## Prefer external test suites and narrow test-only interfaces

- When practical, write tests in a separate `test/` directory rather than inline with the
  implementation.
- This keeps tests pointed at the public API, keeps the implementation library lighter,
  and makes code navigation easier.
- Small inline expect tests are still fine when they are tightly coupled to the code they
  document and keeping them inline avoids adding new test-target dependencies or extra
  `dune` plumbing.
- If a test truly needs non-public access, expose a narrow `For_testing` module rather
  than widening the main interface.
- Do not use `For_testing` values outside tests and other `For_testing` code.

## Make tests deterministic

- Use fixed clocks, fixed IDs, and stable names when time or randomness would otherwise
  leak into the output.
- Sort directory listings or map keys before printing them.
- Prefer temp directories and explicit fixture files over ambient machine state.
- Avoid relying on environment variables unless the test is specifically about them.
- In Async expect tests, return `Deferred.t` and end with `return ()` so the runtime
  does not race the test harness.

## Make parallel test runs safe

- Expect tests in different files should be able to run concurrently.
- Do not share temp filenames, ports, mutable global state, or other process-wide
  resources across test files unless the test infrastructure explicitly isolates them.
- Always clean up temporary files and directories.
- Prefer `Expect_test_helpers_async.with_temp_dir` (or the corresponding helper in the
  non-Async stack) so temp directories are unique and automatically cleaned up.
- When output contains unstable temp paths or other non-deterministic text, prefer
  post-processing or eliding those values before printing rather than making runtime
  behavior diverge in tests.

## Test the behavior you own

- Assert externally visible behavior: returned values, printed messages, persisted
  artifacts, queue movement, notifications, generated files.
- Prefer tests that cover behavior introduced or changed by your code.
- Do not spend broad integration-test surface revalidating libraries or helpers
  that you are not changing.
- When your code composes a trusted dependency, test the part your code is
  responsible for: what you pass in, what you do with the result, and any
  feature-specific decisions around it.
- Cover the happy path and the main failure path. Add more cases only when they exercise
  a distinct branch or invariant.
- Avoid low-value tests for behavior that is hard to break or is already guaranteed by
  the type system.

## Keep fixtures realistic, but cheap

- Use small, representative inputs that still look like real data.
- For external systems, prefer a local fake or test seam when it preserves the real
  control flow.
- If a real service is cheap and important to the behavior, using it in tests can be
  worthwhile, but keep the test deterministic and easy to diagnose.

## Prefer local clarity over clever abstraction

- Good test names describe the behavior, not the implementation detail.
- One test should usually cover one behavior or one closely related cluster of cases.
- Repeated cases inside one test are fine when they make a table of behavior easy to
  scan.
- When output is large, trim it to the fields that carry the assertion.

## Test file conventions

- Match the surrounding project conventions before introducing a new style.
- Test `.mli` files should normally contain:

```ocaml
(*_ This signature is deliberately empty. *)
```

- If an expect test leaves `expect.uncaught_exn` or `expect.unreachable` in corrected
  output, treat that as a real failure even if the build got far enough to generate the
  file.

## A simple checklist

- Does the test show the real thing a human would want to inspect?
- Did you trim noise rather than hide the artifact?
- Is the test style the simplest one that makes the failure obvious?
- Is the output deterministic?
- Can a reader see the setup, action, and assertion without hunting through helpers?
- Does the test cover behavior introduced or changed by your code?
- Would a failure tell you what broke without additional debugging?
