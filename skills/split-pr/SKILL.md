---
name: split-pr
description: Split the current branch's multi-purpose PR into several single-purpose, independent PRs, each based on origin/main. Use when the user asks to "split PR", "break up this PR", "this PR is too big — split it", or "split pr". Works across agents (claude / cursor / codex) — based on git + gh.
---

Split the current branch's multi-purpose PR into several single-purpose, independent PRs. Each new PR is based independently on origin/main (no inter-dependencies); all diff analysis is against origin/main. Based on git + gh.

```
========== VALIDATE ==========

source_branch = `git branch --show-current`
IF source_branch is "main" or "master"
  ERROR "Cannot split a PR from the main/master branch."

========== ANALYZE ==========

-- All diffs and comparisons are against origin/main
-- This means: what would change if this branch were merged into main right now

`git fetch origin`
diff_stat = `git diff --stat origin/main...HEAD`      # files changed vs origin/main
diff      = `git diff origin/main...HEAD`              # full diff vs origin/main
commits   = `git log --oneline --name-only origin/main..HEAD`  # commits since origin/main

-- Check for existing PR on this branch
existing_pr = `gh pr list --head <source_branch> --state open --json number,title,url`

-- Analyze the diff (against origin/main) and commits to identify independent purposes
-- Group files by purpose (each group = one future PR)
-- A "purpose" is a cohesive change that can be independently reviewed, merged, and rolled back
-- Guidelines for grouping:
--   - New feature + its tests + its docs + its plan → one group
--   - Guide/doc-only updates that span multiple guides → one group if they share a theme
--   - Infra/tooling changes (CI, scripts, commands) → one group per independent concern
--   - If a file has changes for multiple purposes, put it in the most relevant group
--   - Prefer fewer groups over many tiny ones — don't split what naturally belongs together

========== PROPOSE ==========

-- Present the split plan as a table (in English)
-- Format:

  | #  | Purpose       | Files                                   |
  |----|---------------|-----------------------------------------|
  | 1  | [description] | file1.swift, file2.swift                |
  | 2  | [description] | file3.md, file4.md                      |

-- After the table, ask:
  "Confirm the split plan? (y/n) If you want to adjust, describe which groups to merge or re-split."

-- STOP and wait for user confirmation
-- If user says no or requests changes, adjust the table and re-propose
-- Only proceed after explicit approval

========== EXECUTE ==========

FOR each group_i (i = 1..N):
  branch_name = "<username>-<kebab-case-purpose>"    # derive from the purpose; follow the repo's branch naming habit

  1. `git checkout -b <branch_name> origin/main`       # each new branch starts from origin/main
  2. Bring this group's final file state onto the new branch:
     -- Added/modified files:
        `git checkout <source_branch> -- <file1> <file2> ...`
     -- Deleted files (source branch deleted them vs origin/main):
        `git rm <file>`        # checkout cannot reproduce a deletion; without this the new PR misses the delete
     -- If a file needs additional session-requested edits, apply them after checkout
  3. `git add <file1> <file2> ...`               # specific files only, never -A or . (deletes are already staged by git rm)
  4. `git commit` with HEREDOC:
       [type] English title

       English description

       <Co-Authored-By trailer per agent convention, if applicable — follow repo AGENTS.md / CLAUDE.md; do not hardcode a model name>
  5. Push with SSH/HTTPS fallback:
     TRY: `git push --set-upstream origin <branch_name>`
     IF failed:
       current_url = `git remote get-url origin`
       IF current_url starts with "git@":
         alternate_url = HTTPS version
       ELSE:
         alternate_url = SSH version
       `git remote set-url origin <alternate_url>`
       TRY: `git push --set-upstream origin <branch_name>`
       IF failed:
         `git remote set-url origin <current_url>`
         ERROR "Push failed via both SSH and HTTPS"
  6. Run the `pr` skill to create the PR for this branch
  7. Record the PR URL

  -- Switch back to source branch before next iteration
  `git checkout <source_branch>`

========== CLOSE ORIGINAL ==========

IF existing_pr was found (number = existing_pr[0].number):
  -- Comment on the original PR with links to all new PRs
  `gh pr comment <number> --body "$(HEREDOC)"`
    This PR has been split into the following independent PRs:
    - #xx
    - #xx
    ...

  -- Close the original PR
  `gh pr close <number>`

========== OUTPUT ==========

-- Switch back to source branch, then print summary table of all created PRs
`git checkout <source_branch>`

Print:
  "Split complete. Original PR closed. New PRs:"

  | #  | PR     | Branch                | Purpose     |
  |----|--------|-----------------------|-------------|
  | 1  | #xx    | branch-name-1         | description |
  | 2  | #xx    | branch-name-2         | description |
```
