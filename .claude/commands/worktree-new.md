---
description: Create a new git worktree for parallel development (branches from origin/main, inits submodules).
---

Create a new git worktree for parallel development. If the branch already exists, check it out; otherwise create a new branch based on the latest `origin/main`. Submodules are initialized so the worktree builds.

Branch name: $ARGUMENTS

```
========== VALIDATE ==========

IF $ARGUMENTS is empty
  ERROR "Provide a branch name. Usage: /worktree-new <branch-name>"

-- Confirm we are inside a git repo
TRY: `git rev-parse --git-dir`
IF failed
  ERROR "Current directory is not a git repository."

repo_root   = absolute path from `git rev-parse --show-toplevel`
repo_parent = dirname of <repo_root>
repo_name   = basename of <repo_root>
worktree_path = "<repo_parent>/<repo_name>-$ARGUMENTS"
display_worktree_path = <worktree_path> with the user's home directory prefix replaced by "~"
IF <worktree_path> is not under the user's home directory
  display_worktree_path = <worktree_path>

Use <worktree_path> for all filesystem and git operations.
Use <display_worktree_path> only for user-facing output and copy/paste terminal commands.

========== CREATE ==========

`git fetch origin main`

-- Worktree path already exists?
IF <worktree_path> directory exists
  IF `git worktree list` contains <worktree_path>
    Print "Worktree already exists at <display_worktree_path>; reuse it."
    SKIP to SUBMODULES
  ELSE
    ERROR "<display_worktree_path> already exists but is not a valid worktree. Remove it or pick another branch name."

-- Branch already exists?
IF `git branch --list $ARGUMENTS` is not empty
  IF `git worktree list` shows $ARGUMENTS is checked out somewhere
    existing_path = that worktree's path
    display_existing_path = <existing_path> with the home-dir prefix replaced by "~" (else the raw path)
    ERROR "Branch $ARGUMENTS is already checked out at <display_existing_path>. Switch to that directory."
  `git worktree add <worktree_path> $ARGUMENTS`
ELSE
  `git worktree add <worktree_path> -b $ARGUMENTS origin/main`

========== SUBMODULES ==========

-- This repo has submodules (ghostty, homebrew-cmux, vendor/bonsplit). A fresh worktree shares the
-- main repo's submodule git objects but needs the working trees checked out, or the build (GhosttyKit,
-- bonsplit) fails. Run inside the new worktree via -C (do NOT cd — see note below).
`git -C <worktree_path> submodule update --init --recursive`

========== OUTPUT ==========

IMPORTANT: Do NOT attempt to `cd` into the worktree directory. Claude Code cannot change its own working directory — any `cd` in a Bash call only affects that single subprocess and does not persist. Use `git -C <worktree_path> …` for any git command you must run there.

Print:
  "Worktree created:"
  "  Path:   <display_worktree_path>"
  "  Branch: $ARGUMENTS"
  IF new branch: "  Based on: origin/main"
  IF existing branch: "  Using existing branch"
  ""
  "Next steps:"
  "1. Exit this Claude Code session (Ctrl+C or /exit)."
  "2. In a terminal, switch to the new worktree and start Claude Code:"
  ""
  "   cd <display_worktree_path> && claude"
  ""
  "   To resume the prior conversation context there:"
  "   cd <display_worktree_path> && claude --resume"
  ""

`git worktree list`
```
