<!--
  The standard format for the /review-plan round artifact review.md.
  Explanatory comments (HTML comment blocks and the word "Example") must not appear in the final artifact.
  The artifact is written to temp/review-plan/<branch_slug>/<plan_basename>/<reviewer>/round-NN/review.md
  (<branch_slug> = branch name with non-[A-Za-z0-9_-] characters replaced by -).
  Reminder: the reviewer is read-only on the plan file — all fixes are given as "Suggested" with a concrete change;
  the plan author independently evaluates each finding and decides whether to adopt it, recording the rationale where the
  reviewer can see it when declining (architecture-level goes into Archived Decisions).
  Archived Decisions are the developer's settled choices and are not evaluated within the rounds; the body being inconsistent with a decision is a finding, the decision itself is not.
  The artifact is a defect report, not an appraisal, and must be agent-anonymous — from the output alone it must be impossible to tell whether it came from claude or codex:
  - The chat reply = the text of review.md minus the "Areas Explored This Round" section (that section is lane bookkeeping, kept on file only, not sent out),
    with no narrative, pleasantries, or "Want me to …?" closing offers before or after
  - No praise / overall appraisal; a section with no findings just says "None"
  - No severity grading (Blocking / Suggested are routing tags, not severity)
  - No first-person narration, no recap of the exploration process; evidence is only conclusion + path:line
  - Retracting your own prior-round mis-report = one row in the reconciliation table (Retracted · mis-review + a one-line reason), not a paragraph of self-criticism
  - The section order and headings are fixed, all present; each finding is wound up per location/problem/impact/fix
-->

# Format: plan review round

```markdown
# Review Round <N> — Plan Review

**Plan**: <plans/xxx.md>
**Reviewer**: <reviewer lane>
**Posture**: standard | devils-advocate
**Date**: <YYYY-MM-DD>

## Prior-Issue Reconciliation

<!-- Round 1 writes only "None" here, and does not keep the table below; from round 2 on, reconcile each item per the table. -->

| # | Source | Problem | Reconciliation status | Evidence |
|---|--------|---------|-----------------------|----------|
| 1 | R<round>-<seq> | <problem summary> | Root-cause fixed / Justified rejection / Surface patch / Unaddressed / Retracted (mis-review) | <diff hunk / code path:line / author-archived rejection rationale / one-line retraction reason> |

## New Findings & Suggestions

<!-- Includes implicit-decision findings: an architecture choice silently made in the body but not archived, given as a "Suggested"
     finding requiring the author to archive it explicitly (only requesting the record, not judging the choice). -->

### <number. title> (Blocking | Suggested)
- **Location**: <plan section / specific location>
- **Problem**: <what it is>
- **Impact**: <what happens to the executing agent if unresolved>
- **Options / Fix**: <for Blocking items, list optional fixes with pros and cons; for Suggested items, give paste-able replacement text/snippet
  so the author can apply it mechanically without interpretation>

## Areas Explored This Round

<!-- Bookkeeping section: written to review.md only, used by this lane's later rounds for convergence (exploration dedupe); does not enter the chat reply. -->

- Source files Read: <path list>
- Test scenarios cross-checked: <scenario list>
- Implementation steps traced: <step numbers>

## Plan Readiness

- **Verdict**: Ready | Needs refinement | Not ready | Abandon
- **Suggested status**: review-plan-complete | create-plan-complete | abandoned
- **Convergence trend**: <this round vs prior rounds — the number and spread of findings, whether converging; round 1 writes "first round">
```
