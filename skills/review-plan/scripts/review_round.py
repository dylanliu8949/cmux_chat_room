#!/usr/bin/env python3
"""Round prologue for /review-plan: deterministic prereq check + round bookkeeping.

No agent judgment, and — unlike plan_execution_gate.py — NO plan mutation:
Status writes are out of scope for /review-plan (the developer asks for them
explicitly).

What it does:

  1. Prereq (prerequisite not met → FAIL):
     - plan was generated from the canonical template (plan_template_check)
     - **Status** ∈ {create-plan-complete, review-plan-in-progress}
       (in-progress plan not finished / plan-execution-* already in execution phase / abandoned all rejected)
     - Decisions Needed has NO open items — decisions are resolved by the developer
       with the plan author during create-plan (per plan-template Plan Generation
       Rules, the plan body isn't even generated until they are); open items mean
       the plan isn't review-ready, not that a special review mode should run

  Plan file is optional: one branch = one plan = one purpose. Omitting it
  resumes the plan recorded for this branch (temp/review-plan/<branch_slug>/.last-plan);
  with no record, it auto-detects the single plans/*.md changed on the branch
  (0 or >1 candidates → FAIL asking to specify). This lets the developer run bare
  `/review-plan` repeatedly until convergence without re-typing the path.

  2. Round bookkeeping under temp/review-plan/<branch_slug>/<plan_basename>/<reviewer>/:
     - keyed by branch so bare invocations resume the same lane; per-plan-stem
       sub-dir keeps the rare two-plans-on-one-branch case from mixing history
     - --reviewer omitted → the stable 'default' lane, so repeated bare
       `/review-plan` continues the SAME lane and accumulates rounds (this is
       what makes Prior-Issue Reconciliation non-empty). Parallel independent
       reviewers (1 writer + claude/codex/codex in parallel) opt in by each
       passing a distinct --reviewer <lane>; concurrent bare invocations would
       otherwise share the default lane and collide on round dirs
     - completed round = round-NN/ dir containing review.md
     - a round dir WITHOUT review.md is an aborted round → resumed (same NN)
     - snapshots the current plan into round-NN/plan-snapshot.md
     - if a previous completed round exists in this lane, writes the unified
       diff of its snapshot vs the current plan to round-NN/plan-diff.patch

  3. Mode: "full" if this lane has no completed rounds; "incremental" otherwise.
     (Decision evaluation is not part of the review rounds: archived decisions are
     the developer's settled choices; when the developer wants opinions they ask an
     agent separately and manually, outside /review-plan.)

  The plan Status is the durable workflow signal; the temp history is only an
  accelerator. If Status is review-plan-in-progress but no round history exists
  in this lane (temp wiped / fresh worktree / new reviewer), this is reported
  as a NOTE and the lane's round counter starts at 1 — not an error.

stdout on success (KEY=VALUE, one per line; paths repo-relative):
  ROUND=2
  MODE=incremental
  POSTURE=standard | devils-advocate
  REVIEWER=<lane>
  BRANCH=<branch>
  PLAN=<resolved plan-file>
  STATE_DIR=temp/review-plan/<branch_slug>/<basename>/<lane>
  SNAPSHOT=.../round-02/plan-snapshot.md
  DIFF=.../round-02/plan-diff.patch                            (or "none")
  PREV_REVIEWS=.../round-01/review.md                          (comma-joined, or "none")
  NOTE=...                                                     (zero or more)

Exit codes:
  0 — pass; 1 — prereq failed ("FAIL" + "- <reason>" lines); 2 — usage error

Usage:
    python3 skills/review-plan/scripts/review_round.py [<plan.md>] \
        [--reviewer <lane>] [--devils-advocate]
"""

import argparse
import difflib
import re
import subprocess
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parent.parent.parent.parent

# Shared deterministic checks live in the execute-plan skill — import, don't duplicate.
sys.path.insert(0, str(REPO_ROOT / "skills" / "execute-plan" / "scripts"))
from plan_execution_gate import (  # noqa: E402
    STATUS_RE,
    check_decisions_empty,
    check_loc_estimates,
    check_nested_numbering,
    check_size_token,
    check_steps_structure,
    extract_section_body,
)
from plan_template_check import (  # noqa: E402
    check_template_match,
    detect_template,
)


ALLOWED_STATUSES = frozenset({"create-plan-complete", "review-plan-in-progress"})


def rel(path: Path) -> str:
    try:
        return str(path.relative_to(REPO_ROOT))
    except ValueError:
        return str(path)


def git(*args: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        ["git", *args], cwd=REPO_ROOT, capture_output=True, text=True
    )


def current_branch() -> str:
    # One branch = one plan: lane history is archived by branch, so bare `/review-plan` can
    # continue rounds on the same branch. In detached / non-git environments fall back to the
    # _detached_ sentinel and still leave a trail keyed by plan stem.
    branch = git("branch", "--show-current").stdout.strip()
    return branch or "_detached_"


def detect_branch_plan_docs() -> list[Path]:
    """The plans/*.md changed on this branch relative to origin/main (including uncommitted), deduped and sorted."""
    names: set[str] = set()
    diff = git("diff", "--name-only", "origin/main...HEAD")
    if diff.returncode == 0:
        names.update(diff.stdout.split())
    for line in git("status", "--porcelain").stdout.splitlines():
        # A porcelain line looks like 'XY <path>'; strip the status code to get the path. rename/copy looks like 'old -> new'; take the new path.
        path = line[3:].strip()
        if " -> " in path:
            path = path.split(" -> ", 1)[1]
        if path:
            names.add(path)
    plans = {
        REPO_ROOT / n
        for n in names
        if n.startswith("plans/") and n.endswith(".md")
    }
    return sorted(p for p in plans if p.is_file())


def prereq_failures(text: str) -> list[str]:
    failures: list[str] = []

    _, template_path = detect_template(text)
    if template_path.is_file():
        failures.extend(check_template_match(text, template_path.read_text()))
    else:
        failures.append(f"canonical template missing: {template_path} (abnormal repo structure)")

    m = STATUS_RE.search(text)
    if not m:
        failures.append("missing the **Status** field (please use the latest templates/plan-template.md)")
    elif m.group(1) not in ALLOWED_STATUSES:
        failures.append(
            f"**Status** = '{m.group(1)}'. /review-plan only accepts "
            "'create-plan-complete' (plan saved to disk awaiting review) or "
            "'review-plan-in-progress' (continuing review)"
        )

    # Decision evaluation is not part of the review rounds: under the template rules the plan
    # body (Size / Implementation Steps / etc.) is not generated until all decisions are resolved,
    # so the presence of unresolved decision items means the plan is not yet review-ready
    # (prerequisite not met), not that a special "decision review mode" is needed
    decisions_body = extract_section_body(text, "Decisions Needed")
    if decisions_body and check_decisions_empty(decisions_body) is not None:
        failures.append(
            "'Decisions Needed' still has unresolved items — decisions are resolved by the developer "
            "during the create-plan phase (the plan body is not generated until decisions are resolved); resolve them before submitting for review"
        )

    # Mechanical format checks (shared with the execution gate)
    # Size is allowed to be empty during the review phase (filled only after completeness ≥95%)
    steps_body = extract_section_body(text, "Implementation Steps")
    failures.extend(check_steps_structure(steps_body))
    failures.extend(check_nested_numbering(steps_body))
    if err := check_size_token(text, require=False):
        failures.append(err)
    failures.extend(check_loc_estimates(text))
    return failures


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("plan", nargs="?", default=None)
    parser.add_argument("--reviewer", default=None)
    parser.add_argument("--devils-advocate", action="store_true", dest="devils_advocate")
    try:
        args = parser.parse_args(argv[1:])
    except SystemExit:
        print(
            "usage: review_round.py [<plan.md>] [--reviewer <lane>] [--devils-advocate]",
            file=sys.stderr,
        )
        return 2

    branch = current_branch()
    branch_dir = REPO_ROOT / "temp" / "review-plan" / re.sub(r"[^A-Za-z0-9_-]", "-", branch)
    pointer = branch_dir / ".last-plan"

    notes: list[str] = []
    # The plan file is optional: one branch = one plan, so when omitted we reuse this branch's
    # last-reviewed plan, letting the user repeatedly run bare `/review-plan` until convergence
    # without re-typing the path.
    if args.plan is not None:
        plan_path = Path(args.plan)
        # An explicit relative path is resolved against CWD first, falling back to REPO_ROOT when not found, for compatibility with calls from outside the repo
        if not plan_path.is_file() and not plan_path.is_absolute():
            anchored = REPO_ROOT / args.plan
            if anchored.is_file():
                plan_path = anchored
        if not plan_path.is_file():
            print(f"error: {plan_path} not found", file=sys.stderr)
            return 2
    elif pointer.is_file():
        # The pointer stores a repo-relative path, resolved against REPO_ROOT, independent of the working directory at call time
        recorded = pointer.read_text().strip()
        plan_path = Path(recorded) if Path(recorded).is_absolute() else REPO_ROOT / recorded
        if not plan_path.is_file():
            print(
                f"error: the plan {plan_path} recorded for this branch no longer exists; please specify explicitly: /review-plan <doc>",
                file=sys.stderr,
            )
            return 2
        notes.append(f"no plan specified, reusing this branch's last-reviewed plan {rel(plan_path)}")
    else:
        candidates = detect_branch_plan_docs()
        if len(candidates) == 1:
            plan_path = candidates[0]
            notes.append(f"no plan specified, auto-selected the only plan document changed on this branch {rel(plan_path)}")
        else:
            print("FAIL")
            if not candidates:
                print(
                    "- no plan file specified, and no plan change under plans/ was detected on this branch; "
                    "please specify explicitly: /review-plan <doc>"
                )
            else:
                print("- this branch changed multiple plan documents, cannot auto-select; please specify explicitly /review-plan <doc>:")
                for c in candidates:
                    print(f"  - {rel(c)}")
            return 1

    # When --reviewer is omitted, use the stable 'default' lane: repeated bare `/review-plan`
    # calls should continue the same lane's round history — otherwise each call opens a new lane,
    # always falls into full mode, and Prior-Issue Reconciliation is always empty. When parallel
    # multiple reviewers are needed (1 claude + N codex, each an independent perspective), each
    # reviewer explicitly passes --reviewer <lane> to open an independent lane; parallel bare calls
    # would share the default lane and collide on the same round dir.
    default_lane = args.reviewer is None
    if default_lane:
        reviewer = "default"
    else:
        reviewer = re.sub(r"[^A-Za-z0-9_-]", "-", args.reviewer) or "default"

    text = plan_path.read_text()
    failures = prereq_failures(text)
    if failures:
        print("FAIL")
        for f in failures:
            print(f"- {f}")
        return 1

    # After the plan passes the prereq check, record it as this branch's "last-reviewed plan" for subsequent bare calls to reuse
    branch_dir.mkdir(parents=True, exist_ok=True)
    pointer.write_text(rel(plan_path) + "\n")

    status = STATUS_RE.search(text).group(1)
    if default_lane:
        notes.append(
            "no --reviewer specified, using the default lane 'default' (repeated calls on the same branch continue the round history); "
            "for parallel multi-reviewer independent perspectives, each should pass --reviewer <lane> explicitly"
        )

    state_dir = branch_dir / plan_path.stem / reviewer
    state_dir.mkdir(parents=True, exist_ok=True)
    round_dirs = sorted(d for d in state_dir.glob("round-*") if d.is_dir())
    completed = [d for d in round_dirs if (d / "review.md").is_file()]
    aborted = [d for d in round_dirs if not (d / "review.md").is_file()]

    if status == "review-plan-in-progress" and not completed:
        notes.append(
            f"Status is review-plan-in-progress but lane '{reviewer}' has no round history "
            "(temp wiped / new worktree / new reviewer) — this lane starts from round 1"
        )

    if aborted:
        current = aborted[-1]
        notes.append(f"reusing the previous unfinished round dir {current.name}")
    else:
        current = state_dir / f"round-{len(completed) + 1:02d}"
        current.mkdir(exist_ok=True)
    round_n = int(current.name.split("-")[1])

    (current / "plan-snapshot.md").write_text(text)

    diff_path: Path | None = None
    if completed:
        prev_snapshot = completed[-1] / "plan-snapshot.md"
        if prev_snapshot.is_file():
            diff_lines = list(
                difflib.unified_diff(
                    prev_snapshot.read_text().splitlines(keepends=True),
                    text.splitlines(keepends=True),
                    fromfile=f"{completed[-1].name}/plan-snapshot.md",
                    tofile=f"{current.name}/plan-snapshot.md",
                )
            )
            diff_path = current / "plan-diff.patch"
            diff_path.write_text("".join(diff_lines))
            if not diff_lines:
                notes.append("the plan has had no changes since the previous review round")
        else:
            notes.append(f"{completed[-1].name} is missing plan-snapshot.md, no incremental diff this round")

    print(f"ROUND={round_n}")
    # MODE is determined by "whether this lane has completed rounds", not the round number: a
    # leftover high-numbered aborted round dir must not cause the mode to be judged as incremental
    # when there are no PREV_REVIEWS at all
    print(f"MODE={'incremental' if completed else 'full'}")
    print(f"POSTURE={'devils-advocate' if args.devils_advocate else 'standard'}")
    print(f"REVIEWER={reviewer}")
    print(f"BRANCH={branch}")
    print(f"PLAN={rel(plan_path)}")
    print(f"STATE_DIR={rel(state_dir)}")
    print(f"SNAPSHOT={rel(current / 'plan-snapshot.md')}")
    print(f"DIFF={rel(diff_path) if diff_path else 'none'}")
    prev_reviews = ",".join(rel(d / "review.md") for d in completed)
    print(f"PREV_REVIEWS={prev_reviews if prev_reviews else 'none'}")
    for note in notes:
        print(f"NOTE={note}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
