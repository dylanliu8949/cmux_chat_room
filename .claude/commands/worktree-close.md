---
description: Clean up the worktree and local/remote branch of a merged branch.
---

The branch's PR has merged — clean up its worktree and local branch (and optionally the remote branch).

Branch name: $ARGUMENTS (defaults to the current branch if omitted)

```
========== VALIDATE ==========

-- Confirm we are inside a git repo
TRY: `git worktree list`
IF failed
  ERROR "Current directory is not a git repository; cannot clean up a worktree."

-- Determine the branch name
IF $ARGUMENTS is not empty
  branch = $ARGUMENTS
ELSE
  branch = `git branch --show-current`
  IF branch is empty
    ERROR "Detached HEAD — provide a branch name. Usage: /worktree-close <branch-name>"

IF branch is "main" or "master"
  ERROR "Refusing to clean up main/master."

current_path  = `pwd`
main_worktree = first entry of `git worktree list` (the primary worktree path)

========== FIND WORKTREE ==========

-- Prune stale worktree entries (handles already-deleted directories)
`git -C <main_worktree> worktree prune`

-- Find the worktree path for this branch
worktree_path = the `git -C <main_worktree> worktree list` entry whose branch matches <branch>

IF worktree_path not found
  Print "No worktree found for branch <branch>; cleaning up the local branch only."
  SKIP worktree removal

-- Detect if we are running from inside the target worktree
is_inside_target = (current_path == worktree_path)
IF is_inside_target
  Print "⚠️ Running from inside the target worktree — this directory will not exist after cleanup."

========== CLEANUP ==========

IMPORTANT: Do NOT use `cd` to switch directories. Claude Code cannot change its own working directory. Use `git -C <main_worktree> …` for all git commands from here on.

-- Remove the worktree (if found)
IF worktree_path found
  TRY: `git -C <main_worktree> worktree remove <worktree_path>`
  IF failed (dirty worktree with uncommitted changes):
    Print "⚠️ Worktree <worktree_path> has uncommitted changes:"
    `git -C <worktree_path> status --short`
    Print "Force-remove the worktree (discards all uncommitted changes)?"
    -- STOP and wait for user confirmation.
    -- If confirmed: `git -C <main_worktree> worktree remove --force <worktree_path>`

-- Delete the local branch
TRY: `git -C <main_worktree> branch -d <branch>`
IF failed (not fully merged):
  Print "⚠️ Branch <branch> is not fully merged. Force-delete?"
  -- STOP and wait for user confirmation.
  -- If confirmed: `git -C <main_worktree> branch -D <branch>`

-- Delete the remote branch if it still exists (this repo pushes to `fork`)
push_remote = "fork" if `git -C <main_worktree> remote` lists "fork", else "origin"
IF `git -C <main_worktree> ls-remote --heads <push_remote> <branch>` is not empty
  Print "Remote branch <push_remote>/<branch> still exists. Delete it?"
  -- STOP and wait for user confirmation.
  -- If confirmed: `git -C <main_worktree> push <push_remote> --delete <branch>`

-- Prune remote-tracking refs
`git -C <main_worktree> fetch --prune <push_remote>`

========== OUTPUT ==========

Print:
  "Cleanup complete:"
  "  Removed worktree: <worktree_path>"        (if applicable)
  "  Deleted branch:   <branch>"
  "  Deleted remote:   <push_remote>/<branch>" (if applicable)
  ""

`git -C <main_worktree> worktree list`

IF is_inside_target
  Print ""
  Print "Next steps:"
  Print "1. Exit this Claude Code session (Ctrl+C or /exit)."
  Print "2. In a terminal, switch to the main worktree and start Claude Code:"
  Print ""
  Print "   cd <main_worktree> && claude"
  Print ""
```
