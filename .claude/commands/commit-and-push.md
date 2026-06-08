---
description: Commit current changes (one thing per commit) and push to the tracked remote.
---

Analyze the current changes, split them into commits following "each commit does exactly one thing", and push to the tracked remote.

```
-- Guard: reject if on main branch
branch = `git branch --show-current`
IF branch == "main" or "master"
  Print "❌ You are on main. Direct commit-and-push is not allowed. Create a feature branch first:\n\n  git checkout -b <branch-name>\n"
  STOP

-- Rules
Commit messages in English (this repo's history is English).
Never use `git add -A` or `git add .` — add files individually.
Each commit should do exactly one thing:
  - one feature slice
  - one bug fix
  - one test-only change
  - one docs-only change
  - one tooling/config change
Do not mix unrelated docs, tooling, tests, generated files, and production behavior in the same commit unless they are required for the same logical change.
Do not commit pre-existing unrelated dirty worktree changes unless the user explicitly asked for them.
Commit or push only when the user asked (this command is that ask).
This repo uses submodules (ghostty, homebrew-cmux, vendor/bonsplit). Per CLAUDE.md, never commit a submodule pointer bump unless that submodule commit is already reachable from the submodule's remote main — otherwise the commit is orphaned. If a submodule pointer changed, verify with `cd <submodule> && git merge-base --is-ancestor HEAD origin/main` before staging it.

-- Gather info
status        = `git status`                                # never use -uall
short_status  = `git status --short`
unstaged_diff = `git diff`
staged_diff   = `git diff --staged`
name_status   = union of:
  `git diff --name-status`
  `git diff --name-status --staged`
  `git ls-files --others --exclude-standard`

IF no changes:
  Print "Nothing to commit."
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
  - If `cmux.xcodeproj/project.pbxproj` changed, it rides with the commit that added/removed the files or packages that caused it (run `scripts/normalize-pbxproj.py` first if the pre-commit hook is not installed).

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
    title = "[type] English summary"          # type: feat/fix/refactor/docs/style/test/build/chore/infra/perf/arch
    body  = 2-3 sentence English description if useful

  Run `git commit` with HEREDOC:
    [type] English title

    English description (if useful)

    Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>

  Record commit hash and files included.

-- Resolve push remote
tracking = `git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null`
IF tracking exists:
  push_cmd     = `git push`
  push_remote  = the remote part of <tracking> (e.g. "fork" from "fork/<branch>")
ELSE:
  push_remote  = "fork" if `git remote` lists "fork", else "origin"   # this repo pushes to the fork
  push_cmd     = `git push --set-upstream <push_remote> <branch>`

-- Push with SSH/HTTPS fallback (operate on <push_remote>, not a hardcoded origin)
TRY: run push_cmd
IF failed:
  current_url = `git remote get-url <push_remote>`
  IF current_url starts with "git@":
    alternate_url = HTTPS version  (git@github.com:org/repo.git → https://github.com/org/repo.git)
  ELSE:
    alternate_url = SSH version    (https://github.com/org/repo.git → git@github.com:org/repo.git)
  `git remote set-url <push_remote> <alternate_url>`
  TRY: run push_cmd
  IF failed:
    `git remote set-url <push_remote> <current_url>`   # restore original
    ERROR "Push failed via both SSH and HTTPS"

-- Output
Print:
  - commit count
  - each commit title / hash / files
  - any remaining uncommitted files intentionally left out
  - push result (remote + range)
```
