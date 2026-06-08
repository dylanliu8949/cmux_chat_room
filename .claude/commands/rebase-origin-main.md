---
description: Rebase the current branch onto the latest origin/main and force-push to the tracked remote.
---

Rebase the current branch onto the latest `origin/main`, resolve conflicts, and force-push to the branch's tracked remote.

> Note: in this repo `origin` is the upstream (the PR base) and `fork` is the push target. Rebase replays onto `origin/main` and force-pushes back to wherever the branch tracks (usually `fork`).

```
-- Rules
- Auto-resolve minor conflicts (imports, formatting, non-overlapping regions, docs/comments).
- Ask the developer for major conflicts (same function modified both sides, signature changes, logic conflicts, delete-vs-modify).

========== VALIDATE ==========

branch = `git branch --show-current`
IF branch is "main" or "master"
  ERROR "Already on main/master — nothing to rebase."

========== FETCH & REBASE ==========

`git fetch origin`
`git rebase origin/main`

IF no conflicts → skip to PUSH

========== RESOLVE CONFLICTS ==========

FOR EACH conflicted file
  Read the file to understand both sides.

  IF minor conflict (import order, whitespace, formatting, non-overlapping edits, docs/comments)
    Resolve automatically
    `git add <file>`

  ELSE (same function/method modified by both sides, signature changes, logic conflicts, delete-vs-modify, uncertain)
    Show the conflict content to the developer
    AskUserQuestion — how to resolve?
    Apply the developer's choice
    `git add <file>`

`git rebase --continue`
REPEAT until the rebase completes.

-- Submodule pointers in a conflict: never resolve to a commit that is not reachable from the
-- submodule's remote main (CLAUDE.md orphaned-commit pitfall). If unsure, ask.

========== PUSH ==========

-- Force-push to the tracked remote (do not hardcode origin; this repo tracks fork).
tracking    = `git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null`
push_remote = remote part of <tracking>, else "fork" if it exists, else "origin"
`git push --force-with-lease <push_remote> <branch>`

========== OUTPUT ==========

Print the rebase result (commits replayed, conflicts resolved) and the push status (remote + range).
```
