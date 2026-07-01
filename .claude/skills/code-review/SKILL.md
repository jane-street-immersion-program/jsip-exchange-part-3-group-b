---
name: code-review
description: "CR comments in code and feature descriptions: CR, XCR, CR-soon, CR-someday."
---

_Note: For technical reasons, the CR examples in this document use bracketed placeholders -- `[CR]` / `[XCR]`. (a precommit check would prevent us from checking in unresolved comments). In real code, they would appear without the square brackets._

# Code review at Jane Street

Jane Street's code review system works by directly injecting special comments into source code, rather than as a overlay in a separate system.

The way this works for humans is:

1. The reviewer edits the file to inject a CR comment
2. The author makes the requested code change, optionally adds a short response, and then changes the CR to an XCR
3. The reviewer sees the XCR and deletes the XCR if they are happy with the resolution, or turns it back into a CR, continuing the conversation.

For agents, the process is the same. Follow the CR/XCR syntax below so reviewers and
authors can find and track each comment. JSIP is on git (not Iron), so there's no `fe`
tool tracking CRs — they're found by reading the diff and grepping the tree.

## [CR]/[XCR] Syntax

CR comments are styled the same as regular comments, but prefixed with CR or XCR. Here are a few examples of valid code review exchanges.

- Leave a CR:
```ocaml
(* [CR] $REVIEWER for $AUTHOR: Can you please update X? *)
```

- Implicit CR - if `for $AUTHOR` is omitted, the CR is aimed at the feature author:
```ocaml
(* [CR] $REVIEWER: Can you please update X? *)
```
- Addressed CR: After addressing a CR, the marker is changed to XCR, with a reply:
```ocaml
(* [XCR] $REVIEWER for $AUTHOR: Can you please update X?

   $AUTHOR: I've updated X by doing Y and Z. I did this because of P, Q, and R.
*)
```
- The reviewer may change it back to CR if they want to continue the discussion:
```ocaml
(* [CR] $REVIEWER for $AUTHOR: Can you please update X?

   $AUTHOR: I've updated X by doing Y and Z. I did this because of P, Q, and R.

   $REVIEWER: Y looks good, but Z is a bit off because of S. Can you do W instead?
*)
```
- CRs can be written in the native commenting syntax of the host language:
```markdown
# [CR] $REVIEWER: Can you add some explanation for X?
```

```html
<!-- [CR] $REVIEWER: Can you abstract this into a component? -->
```
- `CR-soon` and `CR-someday` are different from CRs in that they do not block merging
  (e.g., `CR-soon $AUTHOR: ...`; `CR-someday $AUTHOR: ...`), and don't need to be addressed unless
  the user asks.

## Workflow for agents

### Finding CRs

There's no `fe` here, so grep the tree for open CRs. `CR` is a word (and so is `XCR`),
so `rg -nw CR` matches `CR` / `CR-soon` / `CR-someday` but not the resolved `XCR` form:

```bash
rg -nw CR path/to/dir
```

You'll also notice CRs while reading the diff (`git diff`) during review.

### Creating CRs

When you review code, sign CRs with your name and put your name first
(`CR <you> for <author>: ...`) so the author knows who left it.

Agent-generated CRs are assumed to be DUA, since there is not a human on the other end to sign off on the CR response.

### Addressing CRs

In general:

- If the user asks to fix a specific CR, fix that one, but don't touch any other CRs.
- When fixing a CR, check if the same mistake is made in multiple places and fix those too.
- If the user asks to address CRs generally, only address CRs directed at the current
user: either the CR doesn't have a `for` clause and the user is the feature owner,
or the CR is explicitly `for` them.

After addressing the CR, you should do one of the following:
- The CR ends with "DUA" ("delete upon addressing") or "DAR" ("delete after reading"), or
  similar: delete the CR.
- In all other cases: change the CR to an XCR.
  - In most cases, changing the CR to the XCR with no further response is enough. Only add
    a reply if the implementation is non-straightforward in some way or if you have
    followup discussion to have with the author. When adding the reply, sign off with your
    agent name (in JSIP, `claude`):

```ocaml
(* GOOD *)
(* [XCR] $REVIEWER: Can you please update X?

   claude on behalf of $AUTHOR: I've updated X by doing Y and Z. I did this because of P, Q, and R.
*)
```
### Polling workflow

Some users prefer to work asynchronously with their agents by editing files to leave CRs for the agent, while the agent polls for new CRs and addresses them. If the user explicitly requests this workflow, read `references/poll-for-crs.md`.

### Common OCaml gotchas

A set of common agent mistakes is compiled at `references/style-preferences.md`. If the user makes comments about poor OCaml style, you should read this doc and apply its recommendations.
