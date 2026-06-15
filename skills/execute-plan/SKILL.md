---
name: execute-plan
description: Execute a plan document under plans/: deterministic gate pre-check, strip template noise, analyze step dependencies, and dispatch subagents in parallel where possible. Use when the user asks to "execute the plan", "execute plan", "run this plan", or "/execute-plan <plan file>". Works across agents (claude / cursor / codex).
---

Execute the plan document $ARGUMENTS.

Before execution, the plan must have passed review (**Status**: review-plan-complete). Review catches ambiguity, omissions, and conflicts before code is generated — fixing the plan text costs far less than fixing generated code.

```
========== GATE: pre-check + status transition ==========

-- All gate checks (template match, status enum, completeness ≥95%, decisions resolved,
-- sections non-empty, file checkboxes all checked) are deterministic and live in a
-- standalone script — no agent judgment.
--
-- On PASS the script ALSO writes **Status**: plan-execution-in-progress back to
-- the plan file (atomic: gate-pass IS the transition to execution; impossible
-- to forget to record it). Idempotent for resume case.
--
-- Exit 0 = PASS; exit 1 = FAIL with reasons on stdout; exit 2 = usage error.

`python3 skills/execute-plan/scripts/plan_execution_gate.py "$ARGUMENTS"`

IF exit code != 0
  Relay the script's stdout/stderr to the user verbatim, then STOP.
  (Don't editorialize — the script's failure list IS the action list.)

-- The gate MUTATES the plan file on PASS (the status write-back). Any read of $ARGUMENTS
-- made before the gate is now stale — re-read it before editing checkboxes.

========== STRIP PLAN (only after the GATE passes) ==========

-- Now that the gate has passed, produce a stripped copy of the plan for the agent to read
-- during execution. The stripped copy removes template boilerplate, resolved decisions, and
-- noise blockquotes (Size guide / Status guide / Mechanical-change downgrade rule / Important /
-- Note / Rule Priority / Plan Generation Rules / Plan Execution Rules / Archived Decisions /
-- HTML Example comments).
--
-- Important: the stripped file is a READ-ONLY snapshot for the agent. All checkbox updates
-- (steps, file reviews) and the final Status bump still apply to the ORIGINAL $ARGUMENTS file.
-- The stripped file is throwaway (temp/ is gitignored).

timestamp     = current UTC time as YYYYMMDD-HHmmss
plan_basename = basename of $ARGUMENTS without .md
stripped_path = temp/execute-plan/<timestamp>/<plan_basename>-stripped.md

`python3 skills/execute-plan/scripts/strip_plan.py "$ARGUMENTS" "<stripped_path>"`

-- From this point forward, read implementation content (Implementation Steps, Files to Change,
-- Test Plan, Analytics Events, Error Tracking, Assertion Checks, etc.) from <stripped_path>. Keep using
-- $ARGUMENTS only for mutations (checking checkboxes, bumping Status).
plan = Read(<stripped_path>)

========== BRANCH PREPARATION ==========

current_branch = `git branch --show-current`

IF current_branch is "main" or "master"
  username   = `gh api user -q .login`
  plan_name  = filename of plan without .md, path, and date prefix
                e.g. plans/2026-06-11-debug-http-server.md → debug-http-server
  new_branch = "<username>-<plan_name>"

  IF there are uncommitted changes
    `git stash push -m "WIP before execute-plan"`
  `git pull origin <current_branch>`    # current_branch is main or master here — pull its own remote, don't hardcode main
  `git checkout -b <new_branch>`        # branch off local default; never `-b xxx origin/main` (would set upstream to main)
  IF stash was pushed
    `git stash pop`
ELSE
  # already on feature branch — proceed as-is

========== EXECUTION RULES ==========

-- Engineering principles for execution live in ONE place — do not restate them here:
Read(guides/plan-execution-guide.md)
  -- core engineering principles / comment quality / logging / architecture-layer boundaries / unit-test rules / git boundaries
Follow it for the entire execution; it binds the orchestrator and every subagent.

========== BASELINE CAPTURE (required before execution) ==========

-- Run the plan-named test suites ONCE before any step executes. Two outputs, both injected
-- into every subagent prompt, so N agents don't independently re-discover the same
-- environment facts or chase failures the plan didn't cause:

IF Test Plan specifies tests
  Run each specified suite once, BEFORE any code changes
  test_env_notes    = the exact commands that worked (runner, flags, per-package vs
                      root-level invocation, sandbox workarounds) — whatever had to be
                      figured out to get the suites running
  baseline_failures = failing tests/files with a one-line failure signature each —
                      pre-existing, known, NOT the plan's to fix
ELSE
  test_env_notes = ""; baseline_failures = []

========== PARALLELIZATION ANALYSIS (required before execution) ==========

-- Before executing anything, analyze the plan's Phase/Step structure and decide what can be
-- delegated to subagents and run in parallel. Works for any agent that can spawn subagents
-- (claude: Task/Agent tool; codex: spawn sub-tasks); without subagent support, fall back to
-- sequential execution with the same schedule.

FOR EACH step in Implementation Steps
  owned_files(step) = files it touches, derived from the step text + Files to Change

Two steps are PARALLELIZABLE when ALL hold:
  - disjoint owned_files (no shared file)
  - no produce/consume dependency (one defines a type/API/file the other uses)
  - neither is marked (manual action required)
Typical parallel groups in this repo:
  - two targets / platforms of the same feature kept consistent with each other
  - independent packages/modules
  - test-only steps for already-finished code, docs steps
Phases (Phase N) are COMMIT/PR boundaries, not execution boundaries. Schedule by
file-ownership + produce/consume across the WHOLE plan, not phase by phase:
  - pulling a producer step into an earlier wave is explicitly allowed (e.g. a later
    phase's constants/types step that multiple current-wave groups import)
  - steps from a later phase may run alongside an earlier phase when their file sets
    are disjoint
  - constraint: each phase's files must stay separable, so the working tree can still
    be split into per-phase commits/PRs afterward — if two phases would touch the same
    file, they stay sequential

schedule = ordered list of waves; each wave = 1..N parallel groups of steps

-- The orchestrator is coordinator-only: it dispatches, verifies, checks checkboxes and
-- accumulates deviations — it never implements steps itself. Dispatch every group as a
-- subagent EVEN WHEN a wave has only one group, so the orchestrator's context stays
-- reserved for bookkeeping across long plans instead of filling with implementation churn.
-- Exception: a group containing a (manual action required) step is not dispatched — it runs via
-- EXECUTE so the orchestrator can stop and prompt the user.

IF agent supports subagents
  FOR EACH wave (in order)
    Dispatch one subagent per group. The prompt MUST give both full context and a
    specific task brief — a subagent that only sees its own steps will reinvent
    context the plan already settled:
      - FULL CONTEXT: <stripped_path> (READ-ONLY) with the instruction to read the
        ENTIRE stripped plan first — Current State Analysis, architecture constraints, and the
        other groups' steps — before touching anything; its slice must fit the whole
      - TASK BRIEF: its assigned steps QUOTED VERBATIM from Implementation Steps (step text +
        Expected result), plus the matching Files to Change entries for its file set —
        not just step numbers
      - OWNERSHIP: the file set it owns; it MUST NOT touch files owned by a
        concurrent group
      - GUIDE: guides/plan-execution-guide.md — the subagent must Read and
        follow it (engineering principles SOT; includes the no-git rule for subagents)
      - VERIFICATION: which compile/test commands prove its slice (from Test Plan /
        the step's Expected result)
      - TEST ENV: test_env_notes — how tests actually run in this repo/sandbox;
        do not re-discover
      - BASELINE: baseline_failures — pre-existing failures; known, do NOT chase or
        fix; only NEW failures relative to this list are the subagent's problem
      - REPORT BACK: what was done, test/compile results, any deviation from the
        plan text (what plan said / what was done / why)
    Subagents never edit the ORIGINAL plan file — checkboxes are checked by the
    orchestrator after the wave (avoids concurrent edits to the same file).
    WAIT for all subagents in the wave, then:
      - verify the wave's result compiles / passes the tests the plan specifies
      - check the wave's step checkboxes in $ARGUMENTS
      - merge subagent-reported deviations into `deviations`
ELSE
  Execute the schedule sequentially (see EXECUTE below).

========== EXECUTE ((manual action required) groups / everything when no subagent) ==========

deviations = []  -- running list, accumulated across the whole execution

FOR EACH remaining step in Implementation Steps (in schedule order)
  Execute the step
  Check the step's checkbox in the ORIGINAL plan document at $ARGUMENTS
  (never edit the stripped file; it's read-only)
  IF step is marked (manual action required)
    STOP and prompt user to complete it manually
  -- Record any deviation from what the plan specified for this step, e.g.:
  --   • implemented differently than the plan described (different approach/API/file)
  --   • added/removed/renamed something the plan didn't mention
  --   • skipped or reordered a step, or split/merged steps
  --   • a plan instruction was wrong/ambiguous/infeasible and you improvised
  --   • tests, file names, or signatures diverged from the plan text
  -- For each, append to `deviations`: { step, what the plan said, what you did, why }.
  -- If the step matched the plan exactly, record nothing.

========== EXIT CHECK ==========

IF Test Plan specifies tests
  Run all specified tests (same commands as BASELINE CAPTURE)
  Completion bar: zero NEW failures relative to baseline_failures, AND every test the
  plan introduces or touches passes.
  IF new failures → fix and re-run; do NOT declare completion until the bar is met
  IF baseline_failures still fail → does NOT block completion; list them in the final
  report as pre-existing (fixing them is a separate, user-authorized pass)
ELSE
  # no tests specified — continue

========== STATUS: execution complete ==========

-- Only bump to plan-execution-complete after all steps finish AND the EXIT CHECK bar is met.
-- If any (manual action required) step is still pending, leave Status at plan-execution-in-progress.
IF all Implementation Steps checkboxes are checked AND the EXIT CHECK completion bar is met
  Update plan metadata at $ARGUMENTS: **Status**: plan-execution-complete
ELSE
  -- Status stays at plan-execution-in-progress; user resumes /execute-plan after handling manual steps

========== DEVIATION REPORT (final step) ==========

-- Always end by reporting how execution diverged from the plan, so the user can
-- decide whether the plan, the code, or both need follow-up.

IF deviations is empty
  Report to the user: "Execution followed the plan exactly, no deviations."
ELSE
  Present `deviations` to the user as a numbered list. For each entry show:
    - what the plan specified
    - what was actually done
    - why it deviated
```
