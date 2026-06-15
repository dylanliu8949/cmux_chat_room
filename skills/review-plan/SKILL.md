---
name: review-plan
description: Iteratively review a plan document under plans/: round 1 reviews the entire body, later rounds reconcile prior findings, review the increment, and explore uncovered areas; round artifacts live in temp/. Archived decisions are the developer's settled choices and are not evaluated within the rounds (the developer consults separately and manually when they want opinions). The reviewer is read-only on the plan, supports parallel multi-reviewer lanes and a --devils-advocate adversarial posture; when subagents are available, fan out the guide's review dimensions in groups to several narrow subagents for parallel deep dives, plus an unguided fresh-eyes subagent, and the main agent compiles, verifies, and dedupes all sources into a single report. Use when the user asks to "review the plan", "review plan", "review this plan", or "/review-plan <plan file>". Works across agents (claude / cursor / codex).
---

Review a plan document. Multi-round iteration: each round focuses on the increment and unexplored areas; round state lives in `temp/review-plan/` (gitignored). The SOT of review principles is [guides/plan-review-guide.md](../../guides/plan-review-guide.md); this skill only defines the execution order.

The default usage is a single reviewer continuing multi-round review of one plan on one branch until convergence: just repeatedly run `/review-plan` (even without the plan path), and each round continues the same lane's round history, with later rounds reconciling prior findings. One branch = one plan is the norm, so this is the default path.

When multiple perspectives are needed, dispatch multiple agents to review in parallel (e.g. 1 claude + 2 codex reviewers); each reviewer explicitly passes its own `--reviewer <lane>` to hold an independent round history; lanes are invisible to each other — independent perspectives are intentional design, to avoid reviewers anchoring on each other. The plan author is responsible for digesting all lanes' review.md.

**Scope boundary**: this skill serves formal multi-round review that needs a paper trail (round artifacts, reconciliation ledger, multiple parallel lanes). When the developer only wants a one-off opinion (a casual "how's this plan?"), read the plan and source per the guide's standard and give a conversational answer directly — do not go through this skill's round ritual.

```
INPUT  $ARGUMENTS = [<plan-file>] [--reviewer <lane>] [--devils-advocate]
  <plan-file>         OPTIONAL. One branch = one plan: when omitted, the script reuses this branch's
                      last-reviewed plan (temp/review-plan/<branch_slug>/.last-plan), and with no
                      record auto-selects the only plans/*.md changed on this branch. So you can
                      repeatedly run bare /review-plan until convergence without re-typing the path;
                      with 0 or multiple candidates the script FAILs and asks you to specify. The
                      script's PLAN= output is the plan path resolved this round.
  --reviewer          OMITTED → the stable 'default' lane: repeated calls on the same branch continue
                      the same round history (this is exactly the prerequisite for Prior-Issue
                      Reconciliation to have something to reconcile). Only when parallel multi-reviewer
                      independent perspectives are needed does each reviewer explicitly pass a distinct
                      lane id (claude-1 / codex-1 / codex-2); parallel bare calls would share the
                      default lane and collide on the same round dir, which the caller must avoid.
  --devils-advocate   adversarial posture, see POSTURE below

========== HARD RULE: THE PLAN IS READ-ONLY ==========

-- The reviewer NEVER writes to the plan file during review process
-- No exceptions:
--   - do not "auto-fix" even trivial wording — propose the exact fix text instead
--   - do not check/uncheck any checkbox
--   - do not bump Status; status changes happen only when the developer explicitly asks,
--     and that ask is outside this skill
-- The guide's "fix directly and pass" (throughput-first) is realized in the multi-agent flow as:
--   reviewer proposes the concrete fix → the PLAN AUTHOR independently evaluates each
--   finding (receiving-code-review style: technical rigor, no blind implementation)
--   and decides whether to act on it. Findings are input to the author, not orders.
--   Single writer also avoids N reviewers conflicting on one plan file.
-- The ONLY thing this skill writes is its own round artifacts under temp/review-plan/.

========== OUTPUT DISCIPLINE ==========

-- The review output is a defect report, not an appraisal — and it must be
-- AGENT-ANONYMOUS: from the output alone it must be impossible to tell whether
-- claude or codex produced it. The format is strict, the style is fixed:
--   - The chat reply IS round-NN/review.md MINUS the Areas Explored This Round section — that
--     section is lane bookkeeping for later rounds (files Read / scenarios
--     cross-checked / steps traced) and stays in the FILE only; printing it to
--     the developer is noise. No preamble, no narrative wrap-up, no
--     "Want me to …?" closing offers, nothing else before or after the artifact.
--   - NO praise, no "overall the plan is solid" commentary, no singing the plan's merits.
--     A section with no findings says "None" — nothing more.
--   - NO severity levels (P0/P1, critical/major/minor, high/medium/low). The Blocking | Suggested
--     tag is routing (developer decides vs author may apply mechanically), not a
--     severity scale; do not add one on top.
--   - NO first-person narration: no "I verified / I was wrong / I think", no
--     self-correction stories, no recounting of the exploration journey, no irony or
--     rhetorical flourish. Retracting your own earlier finding is a reconciliation row
--     (Retracted · mis-review) with a one-line reason — not a paragraph of mea culpa.
--   - Declarative sentences. Evidence = conclusion + path:line, never the process
--     of discovering it. Each finding states location/problem/impact/fix and stops.
--   - Every line must be a finding, a recommendation, a reconciliation verdict, a ledger
--     entry, or the readiness verdict. Anything else is noise.

========== ROUND PROLOGUE (script, deterministic) ==========

-- The script does prereq + bookkeeping only — no agent judgment, no plan mutation:
--   prereq: template match + Status ∈ {create-plan-complete, review-plan-in-progress}
--           + Decisions Needed has no open items (decisions are resolved by the
--           developer during create-plan; per plan-template Plan Generation Rules the plan
--           body isn't even generated until they are — open items = prerequisite not met)
--           (anything else = prerequisite not met / wrong phase → FAIL with reasons)
--   resolves the plan: explicit arg → .last-plan pointer → auto-detect the single
--           plans/*.md changed on this branch (records it as the branch's plan)
--   bookkeeping under temp/review-plan/<branch_slug>/<plan_basename>/<reviewer>/:
--     (<branch_slug> = branch name with non-[A-Za-z0-9_-] characters replaced by -)
--     counts COMPLETED rounds (round dir containing review.md); resumes an aborted round dir
--     snapshots the current plan into round-NN/plan-snapshot.md
--     diffs this lane's previous snapshot vs current plan → round-NN/plan-diff.patch
--   prints KEY=VALUE lines: ROUND / MODE (full|incremental) / POSTURE / REVIEWER /
--     BRANCH / PLAN / STATE_DIR / SNAPSHOT / DIFF / PREV_REVIEWS / NOTE

`python3 skills/review-plan/scripts/review_round.py [<plan-file>] [--reviewer <lane>] [--devils-advocate]`

IF exit code != 0
  Relay the script's stdout/stderr to the user verbatim, then STOP.
IF NOTE says round history lost (Status is already review-plan-in-progress but this lane's temp
  is empty, e.g. new worktree / new reviewer)
  Tell the user; this lane restarts from round-1 rules — the plan Status is the durable
  signal, the temp history is an accelerator, not the source of truth.

Read(guides/plan-review-guide.md)                       # principles SOT: review dimensions / four conclusions / blocking vs fix suggestions
Read(skills/review-plan/references/review-formats.md)   # the standard round-note format
plan = Read(PLAN)              # the plan path resolved by the script (from .last-plan / auto-detect on bare calls);
                               # review reads the FULL plan — never a stripped copy
                               # (Archived Decisions is needed as the consistency baseline)

========== POSTURE ==========

IF POSTURE == devils-advocate
  Follow plan-review-guide.md "Calibrating the adversarial posture (--devils-advocate): doubt,
    but do not disdain" — by default do not take things on faith, actively falsify, and do not
    take any of the plan's claims for granted; but doubt is a deeper pursuit of truth, not a faster
    rejection — the counter-argument must itself pass the verification bar, and if it cannot be
    refuted the original proposal stands. A clean "reasonable" conclusion must be marked
    "challenged" + what was tried. (Archived decisions are still out of scope; see ARCHIVED
    DECISIONS ARE SETTLED.)
  -- Mechanism only: --devils-advocate only changes the questioning posture, it does not turn off
  --   any normal process — Prior-Issue Reconciliation, incremental review, and known-issue
  --   verification proceed as usual; it makes the challenge harder and verification deeper, not
  --   the review scope narrower.
ELSE
  Standard posture per the guide.

========== FRESH-EYES LANE (optional accelerator, when subagent dispatch is supported) ==========

-- A deliberately UNGUIDED second perspective. The structured pass below follows the
-- guide's checklists — but a checklist also anchors: a fresh reader with no guide and
-- no format surfaces problems the categories don't name. Works on any agent that can
-- spawn subagents (claude: Agent tool; codex: sub-tasks). Without subagent support,
-- skip — the guide-driven review below is the complete review either way.

IF executing agent supports subagent dispatch
  Dispatch ONE subagent with a deliberately MINIMAL prompt:
    "Read <plan-file> in full, and the source files it touches where you need to
     check its claims. List everything that seems wrong, unclear, missing,
     contradictory, or unlikely to work as planned. Raw list, one finding per line
     with where-it-is; no format requirements, no guide to follow."
  Plus exactly two constraints (scope, not formality):
    - read-only — never edit the plan or the repo
    - Archived Decisions are settled developer choices: inconsistency WITH them is fair
      game, their merit is not (see ARCHIVED DECISIONS ARE SETTLED)
  Treat the returned findings as CANDIDATES, not conclusions:
    - verify each against the guide's principles AND the actual plan/source before
      adoption; a finding with no guide-level concern behind it (style nit,
      function-level detail — guide: plan review makes only macro-level judgments) → drop
    - dedupe against your own findings AND this lane's prior rounds — do not
      resurrect a finding the author already closed as Justified rejection
    - adopted findings become ordinary findings in New Findings & Suggestions — no source tag
      (OUTPUT DISCIPLINE: agent-anonymous)
ELSE
  Skip — no substitute needed.

========== DIMENSION FAN-OUT (parallel division of the structured review, when subagent dispatch is supported) ==========

-- This is HOW the "structured review" itself is executed, not an extra accelerator. The review
-- surface of plan-review-guide.md spans many dimensions (ambiguity / omission / internal conflict /
-- inconsistency with the codebase / unarchived implicit decisions + various "deprecation"-level
-- architecture issues); when one agent runs them serially, attention disperses toward the end, and
-- the later dimensions (test-scenario coverage / naming consistency / implicit decisions) tend to be
-- crowded out by the earlier architecture issues and surface only in later rounds — exactly one source
-- of dragged-out review rounds. Slicing the dimensions into groups and dispatching a narrow-focused
-- subagent per group for parallel deep dives covers more, deeper, in a single round and converges faster.
-- Any agent that can dispatch subagents can use this (claude: Agent tool; codex / cursor: sub-tasks).

IF executing agent supports subagent dispatch
  Slice the guide's review dimensions into several narrow groups, dispatching ONE subagent per group.
  Suggested grouping (adjust the number of groups by the plan's change surface; for a very small plan,
  use fewer groups or even inline — don't split for the sake of splitting):
    - Architecture & boundary group: "deprecation" class (multi-purpose plan / breaking existing
      boundaries·architecture / reinventing the wheel / circular dependencies / business logic placed
      in the wrong layer) + Clean Architecture principles (layering / dependency direction / minimal
      visibility / KISS·DRY·YAGNI·minimal change surface) + unarchived implicit decisions (require the
      author to archive explicitly, do not judge the choice itself)
    - Completeness & consistency group: omission (files / steps) / internal conflict / inconsistency
      with the codebase (MUST Read source to confirm)
    - Ambiguity & testing group: ambiguity / test-scenario coverage (the guide's unit-test coverage rules)
  Each subagent prompt fixedly includes:
    - the dimensions it owns, requiring Read(guides/plan-review-guide.md) and reviewing only along those dimensions
    - the plan path (PLAN), requiring it to Read the full plan + the source / architecture.md it
      references/touches to verify its claims (never judge from plan prose alone, guide guardrail)
    - read-only: must not change the plan or the repo
    - Archived Decisions are settled developer choices: inconsistency with them is a finding, their
      own merit is not evaluated (see ARCHIVED DECISIONS ARE SETTLED)
    - make only macro-level judgments; function-level detail / style nit → do not report (guide); return
      a raw findings list, each with plan location / problem / impact / fix
  These subagents are this lane's internal division of labor, not independent reviewers — lane isolation
    targets top-level multiple reviewers (who don't read each other's review.md); fan-out subagents do
    not each write a review.md, all findings flow back to the main agent.

  CONVERGE (the main agent compiles into a single deduped report): all sources — this fan-out's per-group
  subagents + the FRESH-EYES lane + the main agent's self-review — produce findings that are CANDIDATES,
  closed out by the main agent:
    - verify each against the guide's principles + the actual plan/source; drop those with no guide-level
      concern (style nit, function-level detail); do not resurrect findings already Justified rejection in
      this lane's prior rounds
    - global dedupe: the same problem is often caught by multiple sources (a boundary issue → architecture
      group + completeness group; fresh-eyes overlapping with some dimension group), merge by plan location
      + same root cause into one entry, keep the strongest-evidence wording, never let the same problem
      appear twice
    - adopted items go into New Findings & Suggestions, with no source tag (OUTPUT DISCIPLINE: agent-anonymous)
  The final output is a single round-NN/review.md — the subagents' division of labor is invisible to the
  reader, presented as one unified, non-duplicated report.
ELSE
  This agent runs through all of the guide's review dimensions serially (the MODE flow below is unchanged).

========== ARCHIVED DECISIONS ARE SETTLED ==========

-- Archived Decisions records choices the developer already made with the plan author during
-- create-plan. The review rounds do NOT evaluate or re-litigate them — they are
-- CONSTRAINTS the rest of the plan must be consistent with, not findings material.
-- When the developer wants opinions on a decision, they ask agents separately and
-- manually; that consultation is outside this skill.
-- What IS still findings material:
--   - the plan body contradicting an archived decision (internal conflict → finding)
--   - implicit decision: an architecture choice silently made in Current State Analysis /
--     Files to Change / Implementation Steps but absent from Archived Decisions → flag it so the
--     writer archives it explicitly (this asks for the record, it does not judge the choice)

========== MODE = full (round 1) ==========

-- No prior rounds in this lane: review the ENTIRE plan body against the guide's
-- checklists — ambiguity / omission / internal conflict / inconsistency with the codebase
--   (MUST Read source to confirm) / test-scenario coverage.
-- This structured-review pass runs per DIMENSION FAN-OUT (parallel division of labor with deep dives
--   when subagents are supported, main agent compiles and dedupes; otherwise serial).
-- MUST Read the referenced code / module / architecture.md BEFORE any verdict —
--   never judge from plan prose alone (guide guardrail).
-- Hunt implicit decisions per ARCHIVED DECISIONS ARE SETTLED.
-- Record what this round explored in the ledger (source files Read / test scenarios
--   cross-checked / steps traced) — later rounds converge by filling it up.
-- Classify findings and write round-NN/review.md exactly as steps 4-6 below.
The chat reply is round-NN/review.md minus Areas Explored This Round — nothing else (see OUTPUT DISCIPLINE).
EXIT

========== MODE = incremental (from round 2 on) ==========

prev_reviews = Read every file in PREV_REVIEWS        # this lane's history only
diff         = Read(round-NN/plan-diff.patch)         # what the writer changed since this lane last reviewed

-- 1. Prior-Issue Reconciliation
FOR EACH issue from prev_reviews not yet closed (Root-cause fixed / Justified rejection / Retracted)
  Judge: Root-cause fixed / Justified rejection / Surface patch / Unaddressed / Retracted (mis-review, with a one-line reason)
    based on the diff + re-reading the plan, and the actual code where needed
  Justified rejection = the author declined the suggestion AND recorded the rationale where the
    reviewer can see it (architecture-level rejections belong in Archived Decisions).
    If the reviewer finds the rationale sound → closed. If not → stays open, marked
    Disputed — the developer arbitrates; do not re-argue it every round.
  Plan unchanged + no recorded rationale = Unaddressed (silent rejection is
    indistinguishable from oversight).
  Surface patch / Unaddressed stay open and carry into this round's report
  -- A symptom patch (wording tweaked, root cause intact) does NOT close an issue.

-- 2. Incremental review
Review every changed/added hunk in diff, with extra weight on
  Files to Change, Test Plan, Implementation Steps.
Diff hunks are FRESH review surface — full round-1 rigor and the guide's guardrail
  apply (independent examination, claims re-verified in source), not just
  confirmation that the edit addresses the prior finding; a fix introducing a
  new inconsistency is the classic case this step exists for.
Archived decisions stay out of scope (see ARCHIVED DECISIONS ARE SETTLED); if the diff
  added NEW entries to Archived Decisions, check the body is consistent with them — nothing more.

-- 3. Explore uncovered areas
explored = union of all Areas Explored This Round ledgers from prev_reviews
Pick areas NOT yet in explored:
  source files the plan touches but no round has Read,
  test scenarios not yet cross-checked against the guide's unit-test coverage rules,
  implementation steps not yet traced against the actual codebase
Run the guide's checklists there:
  ambiguity / omission / internal conflict / inconsistency with the codebase (MUST Read source to confirm) / test-scenario coverage
When the dimensions to explore this round still form multiple groups, dispatch them to parallel subagents
  per DIMENSION FAN-OUT (covering only the "not yet explored" dimensions / source, avoiding re-covering
  reconciled areas), main agent compiles and dedupes; inline if the scope is small.
Record what THIS round explored in the ledger — convergence comes from the ledger
  filling up, not from re-reading everything every round.

-- 4. Finding classification (plan stays READ-ONLY — see HARD RULE)
implementation-detail issues → Suggested finding: include the EXACT replacement text /
  snippet so the author can apply it mechanically IF they agree — the author still
  evaluates every finding independently; acceptance is never assumed
architecture-level issues    → Blocking finding, each with problem / impact / options

-- 5. Write round-NN/review.md per references/review-formats.md:
     Prior-Issue Reconciliation (round 1 writes "None") / New Findings & Suggestions (Blocking + Suggested) / Areas Explored This Round / Plan Readiness

-- 6. Readiness is the agent's own judgment — no fixed round count, no pressure to
--    declare Ready by round N. The bar:
--      all prior issues Root-cause fixed, no new blocking findings, and ledger coverage the
--      agent judges sufficient for this plan's Size.
--    Ready must be EARNED by the ledger, not by running out of patience: macro-only
--      bounds the KIND of findings (architecture/boundary/omission/test-scenario/
--      execution caveat), NOT their NUMBER — keep surfacing in-scope Suggested findings with
--      paste-able fixes until a round over fresh territory genuinely comes back dry.
--      "in-scope" is per the guide's "Finding admissibility and the Ready bar (stop rule)": details
--      that do not change the architecture direction / module ownership / lifecycle / verification
--      bar / cross-target contract are not in-scope and do not block Ready — when the remaining issues
--      are all details the implementing agent can decide on its own, judge Ready; pressing the
--      contract finer is review theater.
--      A low finding count is meaningful only when the ledger shows wide exploration.
--    What matters is the TREND: each round should surface fewer findings in
--    narrower areas.
--    If findings are not shrinking, say so explicitly — that itself is a signal the
--    plan (or the review focus) needs rethinking.

The chat reply is round-NN/review.md minus Areas Explored This Round — nothing else (see OUTPUT DISCIPLINE).
  Suggested status: Ready → review-plan-complete; needs developer decision → revert to create-plan-complete;
  fundamental problem → abandoned
-- Recommendation only — the developer explicitly asks for any Status write.
```
