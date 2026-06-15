<!--
  The standard format for /review-pr round artifacts review.md.
  Explanatory annotations (HTML comment blocks and the word "Example") must NOT appear in the final artifact.
  The artifact is written to temp/review-pr/<branch>/<reviewer>/round-NN/review.md.
  Reminder: the reviewer is read-only over the code — all fixes are given as Suggested with a concrete
  change (path:line + a directly applicable replacement snippet); the code author independently evaluates
  each finding and decides whether to adopt it, and when declining should record the rationale where the
  reviewer can see it (PR description / commit message / code-side comment).
  The artifact is a defect report, not an appraisal, and it must be agent-anonymous — from the output alone
  it must be impossible to tell whether it came from claude or codex:
  - The chat reply = review.md with the "Areas Explored This Round" section removed (that section is lane
    bookkeeping, kept on file only), with no narrative, pleasantries, or "Want me to …?" closing offers
    before or after
  - No praise / overall appraisal; a section with no findings just says "None"
  - No severity levels (Blocking / Suggested are routing tags, not severity; the guide's abandon mapping →
    Blocking, needs-refinement mapping → Suggested, do not layer critical/high/medium/low on top)
  - No first-person narration, no recap of the exploration; evidence is just conclusion + path:line
  - Retracting your own prior mis-finding = one reconcile-table row (Retracted (mis-review) + a one-line
    reason), not a paragraph of self-criticism
  - Findings from the built-in /code-review lane, once verified and merged, become ordinary findings with
    no source tag
  - Section order and headings are fixed, all present; each finding is bounded by location/dimension/issue/impact/fix
-->

# Format: Code Review Round

```markdown
# Review Round <N> — Code Review

**Branch**: <branch> @ <HEAD short sha>
**Base**: <base ref> @ <short sha>
**Plan (if any)**: <plans/xxx.md | None>
**Reviewer**: <reviewer lane>
**Posture**: standard | devils-advocate
**Date**: <YYYY-MM-DD>

## Prior-Issue Reconciliation

<!-- In round 1 this section just says "None" and omits the table below; from round 2 reconcile each entry in the table. -->

| # | Source | Issue | Reconcile Status | Evidence |
|---|--------|-------|------------------|----------|
| 1 | R<round>-<seq> | <issue summary> | Root-cause fixed / Justified rejection / Surface patch / Unaddressed / Retracted (mis-review) | <delta hunk / code path:line / author's recorded rejection rationale / one-line retraction reason> |

## Plan Completeness Check

<!-- Fill in only when --plan is provided, otherwise write "No plan provided". Corresponds to guide dimension 1. -->

- **Uncovered plan items**: <list each missing file/step/test | "None">
- **Deviations from archived decisions**: <what the plan says / what the code does | "None">

## New Findings & Suggestions

### <number. title>(Blocking | Suggested)
- **Location**: <path:line>
- **Dimension**: <one of the code-review-guide's 13 review dimensions>
- **Issue**: <what it is>
- **Impact**: <what happens if unaddressed>
- **Fix**: <for Blocking items list the candidate fix options with pros/cons; for Suggested items give a
  directly applicable replacement snippet; Bug-class findings (dimension 13) must include reproduction test /
  fix suggestion / regression test>

## Areas Explored This Round

<!-- Bookkeeping section: written only to review.md, used by this lane's later rounds for convergence (exploration dedup); not included in the chat reply. -->

- Source files Read: <path list>
- Tests run: <commands and results | "None">
- Review dimensions covered: <guide dimension numbers run this round>

## Code Readiness

- **Verdict**: Ready | Needs Refinement | Abandon
- **Convergence trend**: <this round vs prior rounds in finding count and scope, whether it is converging; in round 1 write "first round">
```
