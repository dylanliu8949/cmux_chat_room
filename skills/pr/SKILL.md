---
name: pr
description: Generate a PR title and description for the current branch, run PR readiness checks (commit/rebase/format/lint/unit tests), and create or update the PR on GitHub using gh. Use when the user asks to "open PR", "create PR", "raise a PR", "update PR", or "generate PR description". Works across agents (claude / cursor / codex) — based on git + gh.
---

Generate a PR title and description for the current branch, run the readiness checks, and create or update the PR with `gh`. Based on git + gh; runnable by any AI agent.

```
-- Rules
- PR title and description in English (technical terms stay as-is)

========== VALIDATE ==========

branch = `git branch --show-current`     # reused later for `gh pr list/edit --head <branch>`
IF branch is "main" or "master"
  ERROR "Cannot create a PR from the main/master branch. Create a feature branch first."

========== FETCH BASE ==========

-- Fetch with SSH/HTTPS fallback
TRY: `git fetch origin`
IF failed:
  current_url = `git remote get-url origin`
  IF current_url starts with "git@":
    alternate_url = HTTPS version  (git@github.com:org/repo.git → https://github.com/org/repo.git)
  ELSE:
    alternate_url = SSH version    (https://github.com/org/repo.git → git@github.com:org/repo.git)
  `git remote set-url origin <alternate_url>`
  TRY: `git fetch origin`
  IF failed: ERROR "git fetch failed via both SSH and HTTPS"

========== PR READINESS CHECKS ==========

-- Run in order; proceed only once the prior step is green.
-- Steps 1/2/5 always run; 3/4/6 are gated by footprint (a docs-only PR skips them).
-- A step that ran-and-failed must be fixed before continuing.

  1. `commit-and-push` skill     -- commit & push outstanding changes first
  2. `rebase-origin-main` skill  -- rebase onto latest origin/main BEFORE the rest, so <changed> below is the
                                 --   final replayed list and every check validates the replayed branch

changed = `git diff --name-only origin/main...HEAD`     -- post-rebase, so it's final
touches_swift  = any <changed> matches  **/*.swift  OR  **/*.xcodeproj  OR  **/*.xcworkspace  OR  **/Package.swift
touches_ts     = any <changed> matches  **/*.ts  OR  **/*.tsx  OR  **/*.js

  3. IF touches_swift  →  `swiftlint --fix` on changed Swift files, then `swiftformat` on changed Swift files
     -- (substituted from `./run format format-changed --base origin/main`; intent: format only changed files)
     IF touches_ts    →  equivalent formatter for TS files (e.g. prettier --write on changed files)
     -- ELSE skip (nothing to format)
  4. IF touches_ts  →  run eslint --fix on changed TS files, then tsc for type checking
     -- ELSE skip (lint-and-fix only applies to TS; non-TS changes skip this step)
     -- ORDER INVARIANT: this step must run before unit tests (step 6).
  5. `commit-and-push` skill     -- land any format/lint fixes from steps 3–4
  6. IF touches_swift  →  `xcodebuild test` (or `swift test`) for the affected targets
     -- (substituted from `./run test unit -p ios`; intent: run unit tests for changed platform)
     IF touches_ts    →  run jest for the affected packages
     -- TODO(cmux): adjust test commands to match the actual cmux test targets/schemes

========== GATHER CHANGES ==========

Read(references/pr-template.md)        # in this skill's dir
diff    = `git diff origin/main...HEAD`
commits = `git log origin/main..HEAD --oneline`

========== GENERATE PR CONTENT ==========

Generate title and body strictly per template, based on the rebased changes only.
Fill all fields (including the Size definition in the template).

========== CREATE OR UPDATE ==========

existing = `gh pr list --head <branch> --state open --json number,title,url`
number   = existing[0].number       # if an open PR already exists

-- Feed the body via stdin with --body-file - + HEREDOC (avoids the quoting/escaping issues of --body "...")
IF existing PR found
  `gh pr edit <number> --title "<title>" --body-file - <<'EOF'`
    <PR body>
  `EOF`
ELSE
  `gh pr create --title "<title>" --body-file - <<'EOF'`
    <PR body>
  `EOF`

-- Outward-facing action (create/update PR) is publicly visible once published.
-- Unless the user has already authorized "open PR / update PR", confirm before running gh pr create/edit.

========== OUTPUT ==========

Print PR title, description summary, and PR URL
```
