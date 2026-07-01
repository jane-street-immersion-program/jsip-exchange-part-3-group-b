---
name: poll-for-crs
description: "Use this skill when polling for and addressing code review comments (CRs) on a git branch. Covers the polling loop: find open CRs, address them, generalize feedback across the diff, and poll for new ones as the reviewer works asynchronously. Keywords: CR, XCR, code review, git, review comments, address CRs, poll."
---

# Poll for CRs

Find and address all CRs on the current branch, then poll for new ones as the
reviewer works asynchronously.

## Setup

Use the `poll-crs.sh` script (bundled in `scripts/`) to get the full list of open CRs.
Note every instance before you start addressing any.

**Finding CRs:** `poll-crs.sh` greps the files changed on your branch (vs the main
branch) directly, which is what makes the polling loop work.

**Delete vs X is different here:** when polling, always X CRs rather than deleting
them — the reviewer is actively watching and will delete accepted CRs themselves.
Exception: DUA/DAA/DWA and DUR/DAR/DWR CRs can still be deleted.

## The CR lifecycle (polling context)

- You X a CR, reviewer deletes it -> they accepted your change.
- You X a CR, reviewer un-Xes it -> follow-up feedback. Re-read the CR in the file —
  new comments will be at the end. Address those.
- A CR you've never seen appears -> new feedback.

**Important:** When `poll-crs.sh` returns a CR you think you already addressed, don't
assume you forgot to X it. Re-read the CR in the file — the reviewer likely un-X'd it
and added new comments at the end.

## Polling workflow

After addressing all current CRs, run `poll-crs.sh` to poll for new ones. The reviewer
works asynchronously and types slower than you, so polling lets you pick up new CRs as
they arrive without waiting for a prompt.

The script polls every 15s for up to 15 minutes (configurable via first arg). It looks
for open CRs in files changed on the current branch and prints matching lines with
file/line context.
