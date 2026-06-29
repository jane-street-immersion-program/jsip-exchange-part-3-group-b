#!/usr/bin/env python3
"""Convert Core_bench `-sexp` output into github-action-benchmark JSON.

Reads the sexp emitted by

    bench_order_book.exe -sexp

(either from a file argument or stdin) and writes a JSON array in the
`customSmallerIsBetter` format expected by benchmark-action/github-action-benchmark:

    [{"name": "...", "unit": "ns", "value": <float>}, ...]

We track time-per-run (nanoseconds) for every benchmark. The Core_bench sexp
has a flat, regular structure, so we extract the two fields we need with
regexes rather than pulling in a full s-expression parser.
"""

import json
import re
import sys

# Each benchmark record contains `(full_benchmark_name NAME)` and
# `(time_per_run_nanos <float>)`. These appear once per benchmark and in the
# same order, so we can zip them together. sexplib renders a name as a quoted
# string when it contains spaces/special characters (e.g. "find_match (n=10)")
# but as a bare atom otherwise (e.g. submit_sweep_10_levels), so we accept both.
NAME_RE = re.compile(r'\(full_benchmark_name\s*(?:"([^"]*)"|([^)\s][^)]*))\)')
NANOS_RE = re.compile(r"\(time_per_run_nanos\s+([0-9.eE+-]+)\)")

# Some benchmark names embed a measured quantity (e.g.
# "find_match_alloc (n=100, 12.0 words/call)"). That value drifts run-to-run, so
# leaving it in the name would make github-action-benchmark treat each run as a
# new series and break the trend line. Strip it to keep the series key stable:
#   "find_match_alloc (n=100, 12.0 words/call)" -> "find_match_alloc (n=100)"
WORDS_PER_CALL_RE = re.compile(r",\s*[0-9.]+\s*words/call")


def normalize_name(name: str) -> str:
    return WORDS_PER_CALL_RE.sub("", name)


def main() -> int:
    text = open(sys.argv[1]).read() if len(sys.argv) > 1 else sys.stdin.read()

    # findall returns (quoted, bare) tuples; exactly one group is non-empty.
    names = [normalize_name(quoted or bare) for quoted, bare in NAME_RE.findall(text)]
    nanos = NANOS_RE.findall(text)

    if not names or len(names) != len(nanos):
        print(
            f"error: parsed {len(names)} names but {len(nanos)} timings; "
            "is this Core_bench -sexp output?",
            file=sys.stderr,
        )
        return 1

    results = [
        {"name": name, "unit": "ns", "value": float(value)}
        for name, value in zip(names, nanos)
    ]
    json.dump(results, sys.stdout, indent=2)
    print()
    return 0


if __name__ == "__main__":
    sys.exit(main())
