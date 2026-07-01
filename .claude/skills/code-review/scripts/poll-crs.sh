#!/bin/bash
set -euo pipefail

timeout="${1:-900}"
interval=15
elapsed=0

user="${USER:-$(whoami)}"
# The "base" to diff against is the merge point with the main branch.
base=$(git merge-base HEAD origin/main 2>/dev/null || git merge-base HEAD main 2>/dev/null)

while [ "$elapsed" -lt "$timeout" ]; do
  changed_files=$(git diff --name-only "$base" 2>/dev/null)
  if [ -n "$changed_files" ]; then
    open_crs=$(echo "$changed_files" | xargs awk -v user="$user" '
      BEGIN {
        reviewer_pattern = "(" user "|claude)"
      }
      $0 ~ (" CR " reviewer_pattern "( for [^:]+)?: ") {
        found = 1
        print FILENAME ":" NR ":" $0
        next
      }
      found {
        # Strip leading comment indicators and whitespace to check continuation.
        line = $0
        gsub(/^[[:space:]]*(#|;;|\*|\(\*|\/\/)?[[:space:]]*/, "", line)
        if (line == "" || line ~ ("^" reviewer_pattern ": ") || line ~ ("^claude on behalf of " user ": ")) {
          print FILENAME ":" NR ":" $0
        } else {
          found = 0
        }
      }
    ' 2>/dev/null || true)
    if [ -n "$open_crs" ]; then
      echo "$open_crs"
      exit 0
    fi
  fi
  sleep "$interval"
  elapsed=$((elapsed + interval))
done

echo "No open CRs found after ${timeout}s"
exit 0
