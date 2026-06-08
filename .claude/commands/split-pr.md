---
description: Split the current branch's multi-purpose PR into several single-purpose PRs.
---

Split the current branch's multi-purpose PR into multiple independent single-purpose PRs.
Each new PR is based independently on `origin/main` (they do not depend on each other); all diff analysis is relative to `origin/main`.

```
========== VALIDATE ==========

branch = `git branch --show-current`        # = source_branch
IF branch is "main" or "master"
  ERROR "Cannot split a PR from main/master."

========== ANALYZE ==========

-- All diffs and comparisons are against origin/main: what would change if this branch merged into main now.

`git fetch origin`
diff_stat = `git diff --stat origin/main...HEAD`               # files changed vs origin/main
diff      = `git diff origin/main...HEAD`                       # full diff vs origin/main
commits   = `git log --oneline --name-only origin/main..HEAD`   # commits since origin/main

-- Existing PR on this branch?
existing_pr = `gh pr list --head <branch> --state open --json number,title,url`

-- Identify independent purposes from the diff + commits. Group files by purpose (each group = one future PR).
-- A "purpose" is a cohesive change that can be independently reviewed, merged, and rolled back.
-- Guidelines:
--   - New feature + its tests + its docs + its plan → one group.
--   - Doc-only updates spanning multiple files → one group if they share a theme.
--   - Infra/tooling changes (CI, scripts, commands, pbxproj wiring) → one group per independent concern.
--   - If a file has changes for multiple purposes, put it in the most relevant group.
--   - Prefer fewer groups over many tiny ones — don't split what naturally belongs together.

========== PROPOSE ==========

-- Present the split plan as a table:
  | #  | Purpose            | Files                         |
  |----|--------------------|-------------------------------|
  | 1  | <description>      | file1.swift, file2.swift      |
  | 2  | <description>      | file3.md, file4.md            |

-- Then ask:
  "Confirm this split? (y/n) — to adjust, say which groups to merge or split."

-- STOP and wait for user confirmation.
-- If the user declines or requests changes, adjust the table and re-propose.
-- Only proceed after explicit approval.

========== EXECUTE ==========

FOR each group_i (i = 1..N):
  branch_name = "<type>/<kebab-case-purpose>"     # match this repo's style, e.g. feat/..., fix/..., docs/...

  1. `git checkout -b <branch_name> origin/main`          # each new branch starts from origin/main
  2. `git checkout <source_branch> -- <file1> <file2> ...`  # copy final file state from the source branch
     -- For files needing extra uncommitted edits requested during the session, apply them after checkout.
  3. `git add <file1> <file2> ...`                # specific files only, never -A or .
  4. `git commit` with HEREDOC:
       [type] English title

       English description

       Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
  5. Push to the fork (this repo's push target) with SSH/HTTPS fallback:
     push_remote = "fork" if `git remote` lists "fork", else "origin"
     TRY: `git push --set-upstream <push_remote> <branch_name>`
     IF failed:
       current_url = `git remote get-url <push_remote>`
       IF current_url starts with "git@": alternate_url = HTTPS version
       ELSE:                              alternate_url = SSH version
       `git remote set-url <push_remote> <alternate_url>`
       TRY: `git push --set-upstream <push_remote> <branch_name>`
       IF failed:
         `git remote set-url <push_remote> <current_url>`
         ERROR "Push failed via both SSH and HTTPS"
  6. Run `/pr` to create the PR for this branch.
  7. Record the PR URL.

  `git checkout <source_branch>`                  # switch back before the next iteration

========== CLOSE ORIGINAL ==========

IF existing_pr was found:
  `gh pr comment <number> --body "$(HEREDOC)"`
    This PR was split into the following independent PRs:
    - #xx
    - #xx
  `gh pr close <number>`

========== OUTPUT ==========

`git checkout <source_branch>`

Print:
  "Split complete. The original PR was closed; new PRs:"

  | #  | PR    | Branch          | Purpose       |
  |----|-------|-----------------|---------------|
  | 1  | #xx   | <branch-name-1> | <purpose>     |
  | 2  | #xx   | <branch-name-2> | <purpose>     |
```
