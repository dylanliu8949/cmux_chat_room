---
name: worktree-close
description: After the current branch's PR has merged, clean up its git worktree and local/remote branch. Use when the user asks to "clean up worktree", "close worktree", "delete merged branch", or "PR merged, clean up the branch". Works across agents (claude / cursor / codex) — pure git operations. Argument: branch name (defaults to current branch).
---

The current branch's PR has merged — clean up its worktree and local branch (and the remote branch if needed). Pure git; runnable by any AI agent.

Branch name: $ARGUMENTS (uses the current branch if not provided)

```
========== VALIDATE ==========

-- Check if we are inside a git repo
TRY: `git worktree list`
IF failed
  ERROR "Current directory is not inside a git repository — cannot perform worktree cleanup."

-- Determine branch name
IF $ARGUMENTS is not empty
  branch = $ARGUMENTS
ELSE
  branch = `git branch --show-current`
  IF branch is empty
    ERROR "Currently in detached HEAD state. Provide a branch name explicitly. Usage: worktree-close <branch-name>"

IF branch is "main" or "master"
  ERROR "Cannot clean up the main/master branch."

current_path  = `pwd`
main_worktree = first entry of `git worktree list` (the main worktree path)

========== FIND WORKTREE ==========

-- Prune stale worktree entries (handles already-deleted directories)
`git -C <main_worktree> worktree prune`

-- Find the worktree path for this branch
worktree_path = entry of `git -C <main_worktree> worktree list` matching <branch>

IF worktree_path not found
  Print "No worktree found for branch <branch> — will only clean up the local branch."
  SKIP worktree removal

-- Detect if running from inside the target worktree
is_inside_target = (current_path == worktree_path)
IF is_inside_target
  Print "⚠️ Currently running inside the target worktree — this directory will no longer exist after cleanup."

========== RESCUE CLAUDE MEMORY ==========

-- Claude Code keys auto-memory by ABSOLUTE project path (~/.claude/projects/<slug>/memory/, slug = abs path
--   with every "/" → "-"). worktree-new symlinks the worktree's memory dir to the main repo's, so normally
--   there is nothing to rescue. But a worktree created BEFORE that linking existed holds a REAL memory dir
--   in its own slug — those files would be silently orphaned the moment this worktree is gone.
-- So before deleting anything, fold any such real memories back into the MAIN repo's canonical store.
-- (Codex needs nothing: ~/.codex/memories is a single global store, shared across every worktree already.)

main_slug = <main_worktree> abs path with every "/" replaced by "-"
wt_slug   = <worktree_path> abs path with every "/" replaced by "-"   # skip if worktree_path was not found
main_mem  = ~/.claude/projects/<main_slug>/memory
wt_mem    = ~/.claude/projects/<wt_slug>/memory

IF <wt_mem> exists AND is a real directory (NOT a symlink) AND holds any *.md
  `mkdir -p "<main_mem>" && cp -n "<wt_mem>"/*.md "<main_mem>"/ 2>/dev/null`
  Print "Merged worktree Claude memory files into the main repo's shared store (check MEMORY.md manually if there are index conflicts)."

========== CLEANUP ==========

IMPORTANT: Do NOT use `cd` to switch directories. AI agents cannot change their own working directory.
Use `git -C <main_worktree>` for all git commands after this point.

-- Remove worktree (if found)
IF worktree_path found
  TRY: `git -C <main_worktree> worktree remove <worktree_path>`
  IF failed (dirty worktree with uncommitted changes):
    Print "⚠️ Worktree <worktree_path> has uncommitted changes:"
    `git -C <worktree_path> status --short`
    Print "Confirm force-delete the worktree (all uncommitted changes will be lost)?"
    -- STOP and wait for user confirmation
    -- If confirmed: `git -C <main_worktree> worktree remove --force <worktree_path>`

-- Delete local branch
TRY: `git -C <main_worktree> branch -d <branch>`
IF failed (not fully merged):
  Print "⚠️ Branch <branch> is not fully merged. Confirm force-delete?"
  -- STOP and wait for user confirmation
  -- If confirmed: `git -C <main_worktree> branch -D <branch>`

-- Delete remote branch if it still exists
IF `git -C <main_worktree> ls-remote --heads origin <branch>` is not empty
  Print "Remote branch origin/<branch> still exists. Delete it?"
  -- STOP and wait for user confirmation
  -- If confirmed: `git -C <main_worktree> push origin --delete <branch>`

-- Prune remote tracking
`git -C <main_worktree> fetch --prune`

========== OUTPUT ==========

Print:
  "Cleanup complete:"
  "  Worktree deleted: <worktree_path>"  (if applicable)
  "  Local branch deleted: <branch>"
  "  Remote branch deleted: origin/<branch>"  (if applicable)
  ""

`git -C <main_worktree> worktree list`

IF is_inside_target
  Print ""
  Print "Next steps:"
  Print "1. Exit the current AI session"
  Print "2. Switch to the main worktree in your terminal: cd <main_worktree>"
  Print ""
```
