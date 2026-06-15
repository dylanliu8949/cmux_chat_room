---
name: commit-and-push
description: Analyze the current git changes, split into commits following "each commit does exactly one thing", then push to the remote branch. Use when the user asks to "commit", "commit and push", "push my changes", or "split into multiple commits". Works across agents (claude / cursor / codex) — pure git operations, no agent-specific tools required.
---

Analyze the current changes, split them into commits following "each commit does exactly one thing", then push to the remote branch. Pure git/gh; runnable by any AI agent (claude / cursor / codex).

```
-- Guard: reject if on main branch
branch = `git branch --show-current`
IF branch == "main" or "master"
  Print "❌ Currently on the main branch — direct commit and push is not allowed. Create a feature branch first:\n\n  git checkout -b <branch-name>\n"
  STOP

-- Rules
Commit message in English (technical identifiers like module names, class names, API names stay as-is)
Never use `git add -A` or `git add .` — add files individually
Each commit should do exactly one thing:
  - one feature slice
  - one bug fix
  - one test-only change
  - one docs-only change
  - one tooling/config change
Do not mix unrelated docs, tooling, tests, generated files, and production behavior in the same commit unless they are required for the same logical change.
Do not commit pre-existing unrelated dirty worktree changes unless the user explicitly asked for them.

-- Gather info
status = `git status`                                      # never use -uall
short_status = `git status --short`
unstaged_diff = `git diff`
staged_diff   = `git diff --staged`
name_status   = union of:
  `git diff --name-status`
  `git diff --name-status --staged`
  `git ls-files --others --exclude-standard`

IF no changes:
  Print "No changes to commit."
  STOP

-- Analyze commit groups
Read the changed files and diffs.
Group changes by logical purpose, not by file extension alone.

Suggested grouping rules:
  - Production code and its directly required tests can be one commit when they prove the same behavior.
  - Pure test additions for existing behavior can be their own commit.
  - Docs/guide updates should usually be separate from code changes.
  - Lint/tooling/CI command changes should usually be separate from product code.
  - Mechanical renames/moves should be separate from behavioral edits when practical.
  - Generated files should be committed with the source change that generated them, if required.

Write an execution plan before staging:
  Commit 1:
    Purpose: <one thing>
    Files/hunks: <paths and, if needed, hunk descriptions>
    Message: [type] <English summary>
  Commit 2:
    ...

If one file contains unrelated hunks for different commits:
  Use `git add -p <file>` to stage only the intended hunk.
  If interactive staging is too risky, ask the user before proceeding.

-- Commit loop
FOR EACH planned commit group:
  Confirm working tree still contains the expected files.
  Stage only this commit group's files/hunks:
    `git add <file1> <file2> ...`             # specific files only
    or `git add -p <file>`                    # only when one file has mixed-purpose hunks

  Verify staged content:
    `git diff --staged --name-status`
    `git diff --staged`

  IF staged content includes unrelated changes:
    Unstage only the unrelated paths/hunks.
    Re-check staged diff.

  Compose commit message:
    title = "[type] English title"          # type: feat/fix/refactor/docs/style/test/build/chore
    body  = 2-3 sentence English description if useful
    Append the Co-Authored-By trailer per your agent's own convention (if it has one);
      also follow the repo's AGENTS.md / CLAUDE.md commit rules. Do NOT hardcode a model name.

  Run `git commit` with HEREDOC:
    [type] English title

    English description (if needed)

    <Co-Authored-By trailer per agent convention, if applicable>

  Record commit hash and files included.

-- Push with SSH/HTTPS fallback
tracking = `git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null`
IF tracking exists: push_cmd = `git push`
ELSE:               push_cmd = `git push --set-upstream origin <current-branch>`

TRY: run push_cmd
IF failed:
  current_url = `git remote get-url origin`
  IF current_url starts with "git@":
    alternate_url = HTTPS version  (git@github.com:org/repo.git → https://github.com/org/repo.git)
  ELSE:
    alternate_url = SSH version    (https://github.com/org/repo.git → git@github.com:org/repo.git)
  `git remote set-url origin <alternate_url>`
  TRY: run push_cmd
  IF failed:
    `git remote set-url origin <current_url>`   # restore original
    ERROR "Push failed via both SSH and HTTPS"

-- Output
Print:
  - commit count
  - each commit title/hash/files
  - any remaining uncommitted files intentionally left out
  - push result
```
