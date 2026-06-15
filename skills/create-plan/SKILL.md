---
name: create-plan
description: Generate a plan document based on templates/plan-template.md and save it to plans/. Use when the user asks to "create a plan", "write a plan", "generate a plan document", "make a plan", "create plan", or "/create-plan <task description>". Works across agents (claude / cursor / codex).
---

Generate a plan document from the user-provided prompt and save it to the `plans/` directory.

```
INPUT  prompt = $ARGUMENTS
OUTPUT plan file at plans/<date>-<name>.md

-- Template
template = templates/plan-template.md      # the only canonical template in this repo

-- File naming
date = today in YYYY-MM-DD
name = prompt condensed to ~5 english words, joined by "-", lowercase, no punctuation
path = plans/<date>-<name>.md
IF path already exists
  append "-1", "-2", … until no conflict

-- Read template
Read(template)

-- Context discovery before deciding
Locate the code the task touches:
  search the codebase for the relevant types / files (grep / ripgrep)
  Read the architecture / module docs near the code the task touches
Read the architecture doc matching the task type (under guides/):
  Swift app architecture     → guides/mvvm-guide.md
  other domain-specific docs → the relevant guide under guides/
For work that spans multiple targets, the plan must keep names and structure consistent:
  file/class/interface names, user-visible strings, and physical structure aligned across them.
Also inspect the existing implementation in the touched modules; prefer existing repo patterns
over inventing a new abstraction.

-- Populate metadata
author      = `gh api user -q .login`        # verify logged in with `gh auth status` first
commit_hash = `git rev-parse HEAD`
branch      = `git branch --show-current`
created     = today in YYYY-MM-DD
status      = create-plan-in-progress        # set on first write; bumped to create-plan-complete after the file is saved
Prerequisite tasks = from prompt, or "None"
Follow-up tasks    = from prompt, or "None"
title       = concise title matching prompt intent

-- Populate allowed sections
Fill Current State Analysis: summarize current state and constraints from prompt plus what was learned from existing code,
                  module / architecture docs, and relevant product/UX conventions
Fill References:     list relevant docs/paths/links actually read or needed
  IF critical references are missing → STOP, ask user to provide them
Fill Decisions Needed:
  Decision triage rules:
  - Do NOT list every possible implementation choice as an open decision.
  - First resolve choices from, in order:
    1. existing code and architecture conventions in this repo (including cross-target consistency requirements)
    2. the touched modules' architecture docs and the docs listed in the root CLAUDE.md
    3. standard UX conventions for the product surface being touched
    4. the smallest implementation that preserves existing module boundaries and dependency direction
  - If one option is clearly correct by those signals, choose it and put it in Archived Decisions with rationale.
  - Only leave an item in Decisions Needed when it is genuinely product-defining, risky, irreversible,
    has no clear precedent, or requires user/business preference.
  - For simple or conventional tasks, Decisions Needed may be "no items to confirm" and all non-trivial choices
    should be recorded in Archived Decisions.
  - Avoid "ask the human to tick every small choice" planning. A good plan should reduce review burden, not expand it.
Fill Archived Decisions:
  - Record confident decisions made from existing code, architecture, and industry-standard UX.
  - Include a short "rationale" field for each archived decision, citing code paths/docs/conventions used.
  - If choosing the repo's established pattern, say so explicitly.
  - If intentionally diverging from an established pattern, this must be an open decision unless the prompt already
    explicitly requested the divergence.

-- Sections that must stay empty until template rules are satisfied
Size / Implementation Steps / Files to Change / Test Plan = empty
  (template-specific optional sections like Analytics Events, Error Tracking, Assertion Checks — same rule)
  Code snippets in Files to Change must NOT contain import statements

-- Immutable sections
Copy all immutable sections from template verbatim (Rule Priority, Plan Generation Rules, Plan Execution Rules)

-- Save
Write(path, generated content)

-- Status bump: file is on disk, ready for review.
-- If anything is missing (see below), leave status at create-plan-in-progress instead.
IF all required sections are populated AND no STOP condition was hit
  Edit(path, replace `**Status**: create-plan-in-progress` → `**Status**: create-plan-complete`)

-- Output
Print path
Remind: the plan must be reviewed and have its Status set to review-plan-complete before it can be executed with /execute-plan
IF anything is missing → list what's needed and STOP (leave Status at create-plan-in-progress)
```
