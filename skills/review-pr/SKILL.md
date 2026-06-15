---
name: review-pr
description: Iteratively review the current branch's code changes (git diff origin/main...HEAD): a full review in the first round, then later rounds reconcile prior findings, review the increment, and explore uncovered areas, with round artifacts kept under temp/. The reviewer is read-only over the code, supports multiple parallel reviewer lanes and a --devils-advocate adversarial posture; when subagents are available, fan out the guide's 13 review dimensions in groups to several narrow subagents for parallel deep-dives, plus an unguided fresh-eyes subagent (and on Claude Code an extra built-in /code-review subagent), with the main agent assembling, verifying, and deduping every source into a single report. Use when the user asks to "review the code", "review the PR", "review pr", "review this branch", or "/review-pr". Cross-agent (claude / cursor / codex).
---

Review the current branch's code changes. Multi-round iterative: each round focuses on the increment and unexplored areas, with round state kept under `temp/review-pr/` (gitignored). The SOT for review principles is [guides/code-review-guide.md](../../guides/code-review-guide.md) (review scope / 13 review dimensions / three verdicts / guardrails / nitpicking definition); this skill only defines execution order.

The default usage is a single reviewer running multiple rounds on one branch until convergence: just call `/review-pr` repeatedly, each round continuing the same lane's round history, with later rounds reconciling prior findings. One branch with one purpose is the norm, so this is the default path.

When multiple perspectives are needed, dispatch several agents to review in parallel (e.g. 1 claude + 2 codex reviewers), each reviewer explicitly passing its own `--reviewer <lane>` to hold an independent round history; lanes are mutually invisible — independent perspectives are intentional, to keep reviewers from anchoring on each other. The code author is responsible for digesting every lane's review.md.

```
INPUT  $ARGUMENTS = [--base <ref>] [--reviewer <lane>] [--devils-advocate] [--plan <plan-file>]
  --base              review base (default origin/main); scope = git diff <base>...HEAD
  --reviewer          OMITTED → the stable 'default' lane: repeated calls on the same
                      branch continue the same round history (this is exactly the
                      precondition for "Prior-Issue Reconciliation" to have something to
                      reconcile). Only when parallel multi-reviewers each need an
                      independent perspective should each reviewer explicitly pass a
                      distinct lane id (claude-1 / codex-1 / codex-2); concurrent bare
                      invocations share the default lane and collide on the same round
                      dir, which the caller must avoid.
  --devils-advocate   adversarial posture, see POSTURE below
  --plan              associated plan doc; enables the guide's plan-vs-code completeness check dimension

========== HARD RULE: THE CODE IS READ-ONLY ==========

-- The reviewer NEVER mutates the repo during review:
--   - no file edits/creates/deletes — propose the exact fix (path:line + replacement
--     snippet) instead, even for trivial typos
--   - no git mutations (add/commit/checkout/stash/rebase), no formatters, no `--fix`
--   - running tests/compiles READ-ONLY to verify a suspected finding is allowed and
--     encouraged (guide "running tests": selective, diff-related only — CI owns the full suite)
-- The author independently evaluates each finding (receiving-code-review style:
--   technical rigor, no blind implementation) and decides whether to act on it.
--   Findings are input to the author, not orders. Single writer also avoids N
--   reviewers conflicting on one working tree.
-- The ONLY thing this skill writes is its own round artifacts under temp/review-pr/.

========== OUTPUT DISCIPLINE ==========

-- The review output is a defect report, not an appraisal — and it must be
-- AGENT-ANONYMOUS: from the output alone it must be impossible to tell whether
-- claude or codex produced it. The format is strict, the style is fixed:
--   - The chat reply IS round-NN/review.md MINUS the Areas Explored This Round
--     section — that section is lane bookkeeping for later rounds (files Read /
--     tests run / dimensions covered) and stays in the FILE only; printing it to
--     the developer is noise. No preamble, no narrative wrap-up, no "Want me to …?"
--     closing offers, nothing else before or after the artifact.
--   - NO praise, no "overall the implementation quality is good" commentary. A
--     section with no findings says "None" — nothing more.
--   - NO severity levels (P0/P1, critical/major/minor, high/medium/low). The
--     Blocking | Suggested tag is routing derived from the guide's severity mapping
--     (abandon → Blocking, needs-refinement → Suggested); do not add a scale on top.
--     The guide's critical/high/medium/low presentation is superseded by this routing.
--   - NO first-person narration, no recounting of the exploration journey.
--     Retracting your own earlier finding is a reconcile row (Retracted (mis-review))
--     with a one-line reason — not a paragraph of mea culpa.
--   - Declarative sentences. Evidence = conclusion + path:line, never the process
--     of discovering it. Each finding states location/dimension/issue/impact/fix and stops.
--   - Every line must be a finding, a recommendation, a reconcile verdict, a ledger
--     entry, or the readiness verdict. Anything else is noise.

========== ROUND PROLOGUE (script, deterministic) ==========

-- The script does prereq + bookkeeping only — no agent judgment, no repo mutation:
--   prereq: on a named non-main branch, base resolvable, committed diff non-empty
--   bookkeeping under temp/review-pr/<branch>/<reviewer>/:
--     counts COMPLETED rounds (round dir containing review.md); resumes an aborted round dir
--     snapshots `git diff <base>...HEAD` into round-NN/diff-snapshot.patch
--     diffs this lane's previous snapshot vs current → round-NN/diff-delta.patch
--       (snapshot-vs-snapshot covers new commits, fix-ups AND rebases uniformly)
--   prints KEY=VALUE lines: ROUND / MODE (full|incremental) / POSTURE / REVIEWER /
--     BRANCH / BASE / HEAD / STATE_DIR / DIFF_SNAPSHOT / DIFF_DELTA / PREV_REVIEWS /
--     PLAN / NOTE

`python3 skills/review-pr/scripts/review_round.py [--base <ref>] [--reviewer <lane>] [--devils-advocate] [--plan <plan-file>]`

IF exit code != 0
  Relay the script's stdout/stderr to the user verbatim, then STOP.
IF NOTE says the working tree has uncommitted changes
  Tell the user up front: review covers the COMMITTED diff only.

Read(guides/code-review-guide.md)                       # principles SOT
Read(skills/review-pr/references/review-formats.md)     # the standard round-note format
diff = Read(DIFF_SNAPSHOT)
IF PLAN != none
  plan = Read(PLAN)

========== POSTURE ==========

IF POSTURE == devils-advocate
  Follow code-review-guide.md's "calibrating the adversarial posture (--devils-advocate):
    doubt, but not contempt" — by default distrust, actively try to falsify, take nothing
    for granted in any claim outside the code itself; but doubt is a deeper pursuit of truth,
    not a faster rejection — the counter-argument must itself pass the verification bar, and
    if it cannot be refuted the original implementation stands. A clean verdict must be
    annotated "challenged" + what was tried.
  -- Mechanism only: --devils-advocate only changes the questioning posture, it does not
  --   disable any of the normal flow — Prior-Issue Reconciliation, incremental review, and
  --   known-issue verification proceed as usual; it makes challenges sharper and verification
  --   deeper, not the review scope narrower.
ELSE
  Standard posture per the guide.

========== BUILT-IN LANE (Claude Code only, optional accelerator) ==========

-- The built-in /code-review skill exists only on Claude Code — codex/cursor don't
-- have it. It is an accelerator, never a substitute: the guide-driven review below
-- runs IN FULL either way, so a codex lane produces a complete review, not a
-- degraded one.

IF executing agent is Claude Code (subagent dispatch + built-in /code-review available)
  Dispatch ONE subagent: run the built-in /code-review on this branch's diff vs BASE,
    return its findings as a raw list (path:line + description), no fixes applied
  Treat the returned findings as CANDIDATES, not conclusions:
    - verify each against the guide's dimensions AND the actual source before adoption;
      a finding that maps to no guide dimension is likely nitpicking → drop (guide rule)
    - dedupe against your own findings
    - adopted findings become ordinary findings in New Findings & Suggestions — no source tag
      (OUTPUT DISCIPLINE: agent-anonymous)
ELSE
  Skip — no substitute needed.

========== FRESH-EYES LANE (when subagent dispatch is supported, optional accelerator) ==========

-- A deliberately UNGUIDED second perspective, independent of the built-in lane above
-- and available on ANY subagent-capable agent (claude: Agent tool; codex: sub-tasks).
-- The structured pass below follows the guide's dimensions — but a checklist also
-- anchors: a fresh reader with no guide and no format surfaces problems the
-- categories don't name.

IF executing agent supports subagent dispatch
  Dispatch ONE subagent with a deliberately MINIMAL prompt:
    "Read the diff at <DIFF_SNAPSHOT>, then read the touched files in full and
     whatever callers/tests you need to judge them. List everything that seems
     wrong, broken, missing, inconsistent, or likely to bite later. Raw list, one
     finding per line with path:line; no format requirements, no guide to follow."
  Plus exactly two constraints (scope, not formality):
    - read-only — never edit the repo, never run git mutations
    - untouched modules are out of scope (touched files are fair game in full)
  Treat the returned findings as CANDIDATES — same flow as the BUILT-IN LANE:
    verify against the guide's dimensions + actual source, dedupe against your own
    findings and this lane's prior rounds (do not resurrect Justified rejections), merge
    adopted findings untagged (OUTPUT DISCIPLINE: agent-anonymous).
ELSE
  Skip — no substitute needed.

========== DIMENSION FAN-OUT (parallel division of labor for the structured review, when subagent dispatch is supported) ==========

-- This is how "structured review" itself is executed, not an extra accelerator. code-review-guide.md
-- has 13 review dimensions; one agent running them serially gets progressively less focused, and the
-- later dimensions (dead code / naming / logging / test boundaries) tend to get crowded out by the
-- earlier architecture/correctness issues and slip to later rounds — which is one source of review
-- rounds being dragged out. Splitting the dimensions into a few groups and dispatching a narrow-focused
-- subagent for each to dig in parallel covers more ground more deeply in one round and converges faster.
-- Available on any agent that can dispatch subagents (claude: Agent tool; codex / cursor: sub-tasks).

IF executing agent supports subagent dispatch
  Split the guide's review dimensions into several narrow groups, dispatching ONE subagent per group.
  Suggested grouping (add/remove groups based on the diff's actual footprint; if the change is small,
  split less or even inline — don't split for the sake of splitting):
    - Structure group: dimension 1 plan completeness check / 2 architecture & design / 3 technical
      choices / 12 PR single purpose + Clean Architecture principles (layering / dependency direction /
      minimal visibility / KISS·DRY·YAGNI)
    - Correctness group: dimension 4 correctness / 5 security / 13 bug mental walkthrough
    - Test & observability group: dimension 6 test coverage / 7 logging & assertion coverage
    - Hygiene group: dimension 8 dead code / 9 naming & comments / 10 TODO·FIXME / 11 empty function bodies
  Each subagent's prompt always includes:
    - the dimension numbers it owns, with a requirement to Read(guides/code-review-guide.md) and review
      only along those dimensions
    - the DIFF_SNAPSHOT path, with a requirement to Read the full current state of the touched files
      (not just the hunk, guide guardrails 1/3)
    - read-only: no file / git mutations allowed; run only tests directly related to the diff to verify
      suspected points (guide "running tests" section)
    - severity mapping follows the guide, no self-promotion/demotion (guide nitpicking section); return a
      raw findings list, each with path:line / dimension / issue / impact / fix
  These subagents are internal division of labor within this lane, not independent reviewers — guardrail 9's
    lane isolation applies to top-level multi-reviewers (who don't read each other's review.md); fan-out
    subagents don't each write their own review.md, all findings flow back to the main agent.

  CONVERGE (the main agent assembles a single deduplicated report): all sources — each fan-out group
  subagent + BUILT-IN lane + FRESH-EYES lane + the main agent's own self-review — produce findings that are
  CANDIDATES, finalized by the main agent:
    - verify each against guide dimensions + source (guardrails 1-4 / 6 / 11); anything mapping to none of
      the 13 dimensions is judged nitpicking → drop
    - global dedup: the same issue is often caught by multiple sources (boundary issue → structure group +
      correctness group; fresh-eyes overlapping some dimension group); merge by path:line + same root cause
      into a single entry, keep the strongest-evidence wording, never let the same issue appear twice
    - adopted items merge into New Findings & Suggestions, untagged (OUTPUT DISCIPLINE: agent-anonymous)
  The final output is a single round-NN/review.md — the subagents' division of labor is invisible to the
  reader, presented as one unified, non-duplicated report.
ELSE
  This agent runs the guide's 13 dimensions serially (the MODE flow below is unchanged).

========== MODE = full (round 1) ==========

-- Scope per guide "review scope": not limited to changed lines — a touched file/module is
-- fair game in its entirety; untouched modules are out of scope. Findings in touched
-- files that are unrelated to this change are Suggested (non-blocking), per the guide's
-- "findings beyond the diff scope are raised as needs-refinement suggestions".

IF PLAN != none
  Run the guide's dimension 1 (plan-vs-code completeness check) FIRST — missing files /
  missing steps / half-finished work / missing tests / deviation from archived decisions

FOR EACH touched file in diff
  Read the file (the FULL current file, not just the hunks) — never judge from the
  diff alone (guide guardrail: read the code before concluding, don't guess)

Review against the guide's 13 dimensions (architecture & design / technical choices / correctness / security /
  test coverage / logging coverage / dead code / naming & comments / TODO / empty function bodies / PR single purpose / bug mental walkthrough …)
  — execute this structured pass per DIMENSION FAN-OUT (parallel division of labor when subagents are
  supported, otherwise serial); the guide's severity mapping decides Blocking vs Suggested; do not re-map

Write round-NN/review.md per references/review-formats.md
The chat reply is round-NN/review.md minus Areas Explored This Round — nothing else (see OUTPUT DISCIPLINE).
EXIT

========== MODE = incremental (round 2 onward) ==========

prev_reviews = Read every file in PREV_REVIEWS        # this lane's history only
delta        = Read(DIFF_DELTA)                       # what changed since this lane last reviewed

-- 1. Prior-Issue Reconciliation
FOR EACH issue from prev_reviews not yet closed (Root-cause fixed / Justified rejection / Retracted)
  Judge: Root-cause fixed / Justified rejection / Surface patch / Unaddressed / Retracted (mis-review, with a one-line reason)
    based on the delta + re-reading the actual code
  Justified rejection = the author declined the suggestion AND recorded the rationale where the
    reviewer can see it (PR description / commit message / code-side comment).
    If the reviewer finds the rationale sound → closed. If not → stays open, marked
    Disputed — the developer arbitrates; do not re-argue it every round.
  Code unchanged + no recorded rationale = Unaddressed (silent rejection is
    indistinguishable from oversight).
  Surface patch / Unaddressed stay open and carry into this round's report
  -- A symptom patch (rename, comment added, root cause intact) does NOT close an issue.

-- 2. Incremental review
Review every changed/added hunk in delta against the guide's dimensions.
Delta hunks are FRESH review surface — full round-1 rigor and the guide's guardrails
  apply (independent examination, claims re-verified in source), not just
  confirmation that the patch addresses the prior finding; a fix introducing
  a new bug is the classic case this step exists for.
Already-reviewed unchanged code is NOT re-reviewed wholesale — that's what
  exploration (step 3) is for, selectively.

-- 3. Explore uncovered areas
explored = union of all Areas Explored This Round ledgers from prev_reviews
Pick areas NOT yet in explored:
  touched files no round has Read in full,
  guide dimensions not yet run against this diff,
  test scenarios not yet cross-checked against the guide's test coverage rules,
  call sites of changed public symbols not yet traced (Grep, read-only)
When several dimensions still remain to explore this round, dispatch them to parallel subagents per
  DIMENSION FAN-OUT (covering only the dimensions / files not yet explored, to avoid redoing reconciled
  areas); inline it when the scope is small.
Record what THIS round explored in the ledger — convergence comes from the ledger
  filling up, not from re-reading everything every round.

-- 4. Finding classification (code stays READ-ONLY — see HARD RULE)
guide-severity abandon    → Blocking finding, each with issue / impact / options
everything else actionable → Suggested finding: include the EXACT replacement snippet
  so the author can apply it mechanically IF they agree — the author still evaluates
  every finding independently; acceptance is never assumed

-- 5. Write round-NN/review.md per references/review-formats.md:
     Prior-Issue Reconciliation / Plan Completeness Check / New Findings & Suggestions / Areas Explored This Round / Code Readiness

-- 6. Readiness is the agent's own judgment — no fixed round count, no pressure to
--    declare Ready by round N. The bar (guide's three verdicts):
--      Ready: all prior issues closed (Root-cause fixed / Justified rejection), no open Blocking finding,
--        ledger coverage the agent judges sufficient for this diff's footprint
--      Needs Refinement: mergeable, open Suggested findings remain
--      Abandon: any guide-abandon finding stands unrefuted
--    What matters is the TREND: each round should surface fewer findings in
--    narrower areas. If findings are not shrinking, say so explicitly — that itself
--    is a signal the change (or the review focus) needs rethinking.

The chat reply is round-NN/review.md minus Areas Explored This Round — nothing else (see OUTPUT DISCIPLINE).
-- Recommendation only — merging/closing the PR is the developer's call, outside this skill.
```
