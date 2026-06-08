---
description: Generate a PR title/description for the current branch and create or update the PR on GitHub.
---

Generate a PR title and description for the current branch, then create or update the PR on GitHub.

```
-- Rules
- PR title and description in English (technical terms stay as-is).
- The checklist section must include ALL items from templates/pr-template.md verbatim (do not invent or drop items).

========== VALIDATE ==========

branch = `git branch --show-current`
IF branch is "main" or "master"
  ERROR "Cannot open a PR from main/master. Create a feature branch first."

========== FETCH BASE ==========

-- origin is the upstream / PR base in this repo. Fetch with SSH/HTTPS fallback.
TRY: `git fetch origin`
IF failed:
  current_url = `git remote get-url origin`
  IF current_url starts with "git@":
    alternate_url = HTTPS version  (git@github.com:org/repo.git → https://github.com/org/repo.git)
  ELSE:
    alternate_url = SSH version    (https://github.com/org/repo.git → git@github.com:org/repo.git)
  `git remote set-url origin <alternate_url>`
  TRY: `git fetch origin`
  IF failed:
    `git remote set-url origin <current_url>`
    ERROR "git fetch failed via both SSH and HTTPS"

========== BUMP PLAN STATUS ==========

-- If this branch is associated with a plan doc under plans/, bump its 状态 line so the change
-- rides on the same push (this happens before /commit-and-push below). The agent infers the
-- associated plan from the conversation context and/or the branch name; if none, skip this step.
-- Valid 状态 values (from templates/plan-template.md): review-plan-in-progress / review-plan-complete /
-- plan-execution-in-progress / plan-execution-complete / manual-test-* / automated-ui-test-* /
-- code-review-in-progress / code-review-complete / merge-complete / abandoned.
IF an associated plans/<name>.md exists on disk
  -- Pick target_status from conversation context:
  --   * Default (PR being opened/updated for review): code-review-in-progress
  --   * If the agent has clear context the PR has already merged (user said so, or
  --     `gh pr view --json state` returns MERGED): merge-complete  (the only place
  --     merge-complete is auto-written; otherwise plans never leave code-review-in-progress).
  target_status = "code-review-in-progress" by default
  IF context indicates the PR has merged → target_status = "merge-complete"
  Edit(plans/<name>.md, replace the `**状态**：…` line with `**状态**：<target_status>`)

========== PR READINESS ==========

Run the shared PR gate commands in this exact order:
  `/commit-and-push` → `/rebase-origin-main`

Notes:
  - `/rebase-origin-main` must run after the commits land so the PR diff reflects the branch replayed onto the latest origin/main.
  - Per this repo's CLAUDE.md, tests (E2E/UI/unit), coverage, and lint are NOT run locally — they run on CI. Do not add local test/lint steps here. If you want to kick off cloud tests, the user runs `gh workflow run test-e2e.yml` separately.
  - Submodule pitfall (CLAUDE.md): if this branch bumps a submodule pointer, that submodule commit must already be on the submodule's remote main before the PR.

========== GATHER CHANGES ==========

Read(templates/pr-template.md)
diff    = `git diff origin/main...HEAD`
commits = `git log origin/main..HEAD --oneline`

========== GENERATE PR CONTENT ==========

Generate the title and body strictly per templates/pr-template.md, based on the rebased changes only.
Fill all fields, including 大小 (size — use the definition in the template) and 计划文档 (link the plan if one exists).

Title format: `[type] English summary` — type ∈ [plan|feat|fix|refactor|infra|data|perf|chore|test|docs|build|arch].

Checklist section: copy ALL items from templates/pr-template.md exactly, leaving every box unchecked (`[ ]`).

========== CREATE OR UPDATE ==========

-- This repo pushes to `fork` and PRs into origin (upstream). gh resolves the fork head from the
-- pushed branch; pass an explicit head if gh cannot infer it.
fork_owner = owner parsed from `git remote get-url fork`   (if a `fork` remote exists)
existing   = `gh pr list --head <branch> --state open --json number,title,url`

IF existing PR found
  `gh pr edit <number> --title "[type] ..." --body "$(HEREDOC)"`
ELSE
  `gh pr create --base main --title "[type] ..." --body "$(HEREDOC)"`
  -- If gh errors because the head is ambiguous (fork workflow), retry with:
  --   `gh pr create --base main --head <fork_owner>:<branch> --title "..." --body "$(HEREDOC)"`

========== OUTPUT ==========

Print the PR title, a short description summary, and the PR URL.
`open <PR_URL>`    # open in browser
```
