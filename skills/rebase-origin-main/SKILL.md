---
name: rebase-origin-main
description: Rebase the current branch onto the latest origin/main, resolve conflicts, then force push. Use when the user asks to "rebase", "sync with main", "update to latest main", or "resolve conflicts and push". Works across agents (claude / cursor / codex) — pure git operations.
---

Rebase the current branch onto the latest origin/main, resolve conflicts, then force push. Pure git; runnable by any AI agent.

```
-- Rules
- Auto-resolve minor conflicts (imports, formatting, non-overlapping regions, docs/comments)
- Ask developer for major conflicts (same function modified both sides, signature changes, logic conflicts, delete-vs-modify)
- Shared infra is NEVER the feature branch's to merge: always take origin/main's version on conflict for
  shared lockfiles and submodule gitlinks — never hand-merge or regenerate them. A lockfile mismatch
  is an upstream issue fixed by inheriting a newer origin/main, not by editing the lockfile on the branch.

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
  Read the file to understand both sides

  IF file is a shared-infra lockfile or submodule gitlink
    -- During a rebase, ours/theirs are INVERTED: --ours = origin/main (the base), --theirs = your replayed commit.
    -- So "take origin/main's version" = --ours. Never hand-edit or regenerate these.
    `git checkout --ours -- <file>`
    `git add <file>`

  ELSE IF minor conflict (import order, whitespace, formatting, non-overlapping edits, docs/comments)
    Resolve automatically
    `git add <file>`

  ELSE (same function/method modified by both sides, signature changes, logic conflicts, delete-vs-modify, uncertain)
    Show conflict content to developer
    AskUserQuestion — how to resolve?
    Apply developer's choice
    `git add <file>`

`git rebase --continue`
REPEAT until rebase completes

========== PUSH ==========

`git push --force-with-lease origin <branch>`

========== OUTPUT ==========

Print rebase result (commits replayed, conflicts resolved) and push status
```
