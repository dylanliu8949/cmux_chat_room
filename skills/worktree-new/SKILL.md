---
name: worktree-new
description: Create a new git worktree for parallel development. Reuses the branch if it already exists, otherwise creates it from the latest origin/main. Use when the user asks to "create a worktree", "new worktree", "start parallel development on a new branch", or "worktree new". Works across agents (claude / cursor / codex). Argument: branch name.
---

Create a new git worktree for parallel development. Reuse the branch if it already exists, otherwise create a new one from the latest origin/main. After creation, the new worktree is ready to build/test/commit out of the box. Runnable by any AI agent.

Branch name: $ARGUMENTS

```
========== VALIDATE ==========

IF $ARGUMENTS is empty
  ERROR "Branch name required. Usage: worktree-new <branch-name>"

-- Check if we are inside a git repo
TRY: `git rev-parse --git-dir`
IF failed
  ERROR "Current directory is not inside a git repository."

repo_root     = `git rev-parse --show-toplevel`
repo_parent   = dirname of <repo_root>
repo_name     = basename of <repo_root>
safe_branch   = $ARGUMENTS with "/" replaced by "-"   # dir name only — avoids nested dirs for user/feat-x; git branch keeps original $ARGUMENTS
worktree_path = "<repo_parent>/<repo_name>-<safe_branch>"

display_worktree_path = <worktree_path> with the user's home directory prefix replaced by "~"
IF <worktree_path> is not under the user's home directory
  display_worktree_path = <worktree_path>

Use <worktree_path> for all filesystem and git operations.
Use <display_worktree_path> only for user-facing output and copy/paste terminal commands.

========== CREATE ==========

`git fetch origin main`

created = false

-- Worktree path already exists
IF <worktree_path> directory exists
  IF `git worktree list` contains <worktree_path>
    Print "Worktree already exists at <display_worktree_path> — skipping creation."
    SKIP to LINK CLAUDE MEMORY
  ELSE
    ERROR "Directory <display_worktree_path> already exists but is not a valid worktree. Delete it manually or choose a different branch name."

-- Local branch already exists
ELSE IF `git branch --list $ARGUMENTS` is not empty
  IF `git worktree list` shows $ARGUMENTS checked out somewhere
    existing_path = that worktree's path
    display_existing_path = <existing_path> with the user's home directory prefix replaced by "~"
    ERROR "Branch $ARGUMENTS is already checked out at <display_existing_path>. Switch to that directory instead."
  `git worktree add <worktree_path> $ARGUMENTS`
  created = true

-- Only the remote has this branch
ELSE IF `git ls-remote --heads origin $ARGUMENTS` is not empty
  `git worktree add <worktree_path> -b $ARGUMENTS origin/$ARGUMENTS`   # track the remote branch; avoids forking a new same-named branch off origin/main
  created = true

-- Brand-new branch
ELSE
  `git worktree add <worktree_path> -b $ARGUMENTS origin/main`
  created = true

========== PROVISION ==========

-- Only when `created` (i.e. a `git worktree add` actually ran). The "already exists" path SKIPped here.
-- `git worktree add` does NOT check out submodules: any submodule is empty in the new worktree.
-- AI agents cannot persist a cwd: run each command as `cd <worktree_path> && …` in a SINGLE shell call.

IF created
  # TODO(cmux): cmux is a Swift/Xcode project — no llmi submodule or JS deps.
  # If the project has submodules, init them here:
  #   `cd <worktree_path> && git submodule update --init --recursive`
  # If the project has Swift Package dependencies resolved locally, they are typically
  # shared from the main worktree's .build / DerivedData and require no extra step.
  # Run any repo-specific bootstrap here (e.g. `cd <worktree_path> && make bootstrap`).

  provision_ok = true   # update this based on actual bootstrap outcome

========== LINK CLAUDE MEMORY ==========

-- Claude Code keys its auto-memory by ABSOLUTE project path:
--     ~/.claude/projects/<slug>/memory/   where <slug> = the abs path with every "/" replaced by "-".
--   So a worktree at /Users/.../cmux_chat_room-<branch> gets its OWN memory dir, separate from the main repo's.
--   Memories written while working in the worktree would land there and be orphaned once worktree-close
--   removes the directory — never reconnected to the main project.
-- Fix: symlink the worktree's memory dir to the MAIN repo's memory dir, so every memory written in any
--   worktree lands in ONE canonical store that already survives worktree-close (it lives under ~/.claude,
--   not inside the worktree). Runs on both the freshly-created and the already-exists paths.
-- Codex needs nothing here: ~/.codex/memories is a single global git-backed store, not path-keyed.

main_slug  = <repo_root> abs path with every "/" replaced by "-"
wt_slug    = <worktree_path> abs path with every "/" replaced by "-"
main_mem   = ~/.claude/projects/<main_slug>/memory
wt_proj    = ~/.claude/projects/<wt_slug>
wt_mem     = <wt_proj>/memory

-- Single shell call (HOME-relative paths, never rely on a persisted cwd):
`mkdir -p "<main_mem>" "<wt_proj>"`
-- If a pre-link session already wrote real memories into the worktree slot, fold them into the canonical
--   store before replacing the dir with a symlink (no-clobber so canonical wins on name collisions):
`if [ -d "<wt_mem>" ] && [ ! -L "<wt_mem>" ]; then cp -n "<wt_mem>"/*.md "<main_mem>"/ 2>/dev/null; rm -rf "<wt_mem>"; fi`
`ln -sfn "<main_mem>" "<wt_mem>"`

memory_linked = true on success

========== OUTPUT ==========

IMPORTANT: A `cd` in a Bash call only affects that single subprocess and does NOT persist across calls.
Single-command `cd <worktree_path> && …` (as used in PROVISION) is fine; just never rely on a cwd
surviving into a later separate call, and don't try to `cd` into the worktree as a lasting move for your
session — have the user do that in their own terminal (below).

Print:
  "Worktree created:"
  "  Path:   <display_worktree_path>"
  "  Branch: $ARGUMENTS"
  IF new branch:                       "  Base: origin/main"
  IF existing branch:                  "  Using existing branch"
  IF created and provision_ok:         "  Dependencies: provisioned successfully"
  IF created and not provision_ok:     "  Dependencies: ⚠️ provisioning failed (see above) — enter the directory and fix manually"
  IF memory_linked:                    "  Memory: Claude memory symlinked to the main repo's shared store (safe across worktree-close; Codex already shares globally)"
  ""
  "Next steps:"
  "1. Exit the current AI session"
  "2. Switch to the new worktree in your terminal and start your AI tool:"
  ""
  "   cd <display_worktree_path>"
  ""

`git worktree list`
```
