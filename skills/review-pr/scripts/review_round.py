#!/usr/bin/env python3
"""Round prologue for /review-pr: deterministic prereq check + round bookkeeping.

No agent judgment, and NO repo mutation: the reviewer is read-only over the code;
the only writes are this script's own round artifacts under temp/review-pr/.

What it does:

  1. Prereq (prereq not met → FAIL):
     - inside a git work tree, on a named branch that is not main/master
     - base ref (default origin/main) resolvable
     - committed diff `git diff <base>...HEAD` is non-empty (nothing to review otherwise)

  2. Round bookkeeping under temp/review-pr/<branch>/<reviewer>/:
     - each reviewer gets an isolated lane — multi-reviewer lanes must not collide
       on round dirs, and lanes stay independent so reviewers don't anchor on each
       other's findings
     - --reviewer omitted → the stable 'default' lane, so repeated bare
       `/review-pr` on a branch continues the SAME lane and accumulates rounds
       (one branch = one purpose). Parallel independent reviewers opt in by
       each passing a distinct --reviewer <lane>; concurrent bare invocations
       would otherwise share the default lane and collide on round dirs.
     - completed round = round-NN/ dir containing review.md
     - a round dir WITHOUT review.md is an aborted round → resumed (same NN)
     - snapshots the current committed diff into round-NN/diff-snapshot.patch
     - if a previous completed round exists in this lane, writes the unified diff
       of its snapshot vs the current snapshot to round-NN/diff-delta.patch
       (covers new commits, fix-ups AND rebases — the diff-vs-base is canonical)

  3. Mode: "full" if this lane has no completed rounds; "incremental" otherwise.

  Uncommitted working-tree changes are OUT of review scope (reported as NOTE).

stdout on success (KEY=VALUE, one per line; paths repo-relative):
  ROUND=2
  MODE=incremental
  POSTURE=standard | devils-advocate
  REVIEWER=<lane>
  BRANCH=<branch>
  BASE=<base ref> @ <short sha>
  HEAD=<short sha>
  STATE_DIR=temp/review-pr/<branch>/<lane>
  DIFF_SNAPSHOT=.../round-02/diff-snapshot.patch
  DIFF_DELTA=.../round-02/diff-delta.patch                     (or "none")
  PREV_REVIEWS=.../round-01/review.md                          (comma-joined, or "none")
  PLAN=<plan-file>                                             (or "none")
  NOTE=...                                                     (zero or more)

Exit codes:
  0 — pass; 1 — prereq failed ("FAIL" + "- <reason>" lines); 2 — usage error

Usage:
    python3 skills/review-pr/scripts/review_round.py \
        [--base <ref>] [--reviewer <lane>] [--devils-advocate] [--plan <plan.md>]
"""

import argparse
import difflib
import re
import subprocess
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parent.parent.parent.parent


def rel(path: Path) -> str:
    try:
        return str(path.relative_to(REPO_ROOT))
    except ValueError:
        return str(path)


def git(*args: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        ["git", *args], cwd=REPO_ROOT, capture_output=True, text=True
    )


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("--base", default="origin/main")
    parser.add_argument("--reviewer", default=None)
    parser.add_argument("--devils-advocate", action="store_true", dest="devils_advocate")
    parser.add_argument("--plan", default=None)
    try:
        args = parser.parse_args(argv[1:])
    except SystemExit:
        print(
            "usage: review_round.py [--base <ref>] [--reviewer <lane>]"
            " [--devils-advocate] [--plan <plan.md>]",
            file=sys.stderr,
        )
        return 2
    # When --reviewer is omitted, use the stable 'default' lane: one branch = one
    # purpose, so repeated bare `/review-pr` calls should continue the SAME lane's
    # round history — otherwise every call opens a new lane, falls back to full mode
    # forever, and Prior-Issue Reconciliation is always empty. When parallel
    # multi-reviewer (1 claude + N codex, each an independent perspective) is needed,
    # each reviewer explicitly passes --reviewer <lane> to open an independent lane;
    # concurrent bare invocations would share the default lane and collide on round
    # dirs, which the caller must avoid.
    default_lane = args.reviewer is None
    if default_lane:
        reviewer = "default"
    else:
        reviewer = re.sub(r"[^A-Za-z0-9_-]", "-", args.reviewer) or "default"

    plan_path: Path | None = None
    if args.plan is not None:
        plan_path = Path(args.plan)
        if not plan_path.is_file():
            print(f"error: --plan {plan_path} not found", file=sys.stderr)
            return 2

    failures: list[str] = []
    branch = git("branch", "--show-current").stdout.strip()
    if not branch:
        failures.append("HEAD is detached — run /review-pr on a named branch")
    elif branch in ("main", "master"):
        failures.append("currently on main/master — no branch changes to review")
    if git("rev-parse", "--verify", "--quiet", args.base).returncode != 0:
        failures.append(f"base ref '{args.base}' cannot be resolved (do you need to git fetch origin first?)")

    diff_text = ""
    if not failures:
        diff_proc = git("diff", f"{args.base}...HEAD")
        if diff_proc.returncode != 0:
            failures.append(f"git diff {args.base}...HEAD failed: {diff_proc.stderr.strip()}")
        else:
            diff_text = diff_proc.stdout
            if not diff_text.strip():
                failures.append(f"git diff {args.base}...HEAD is empty — no committed changes to review")

    if failures:
        print("FAIL")
        for f in failures:
            print(f"- {f}")
        return 1

    notes: list[str] = []
    if default_lane:
        notes.append(
            "--reviewer not specified, using the default lane 'default' (repeated calls on the same branch will continue the round history); "
            "for parallel multi-reviewer independent perspectives, each should explicitly pass --reviewer <lane>"
        )
    if git("status", "--porcelain").stdout.strip():
        notes.append("the working tree has uncommitted changes — they are out of review scope (review covers the committed diff only)")

    branch_slug = re.sub(r"[^A-Za-z0-9_-]", "-", branch)
    state_dir = REPO_ROOT / "temp" / "review-pr" / branch_slug / reviewer
    state_dir.mkdir(parents=True, exist_ok=True)
    round_dirs = sorted(d for d in state_dir.glob("round-*") if d.is_dir())
    completed = [d for d in round_dirs if (d / "review.md").is_file()]
    aborted = [d for d in round_dirs if not (d / "review.md").is_file()]

    if aborted:
        current = aborted[-1]
        notes.append(f"resuming the previous unfinished round dir {current.name}")
    else:
        current = state_dir / f"round-{len(completed) + 1:02d}"
        current.mkdir(exist_ok=True)
    round_n = int(current.name.split("-")[1])

    (current / "diff-snapshot.patch").write_text(diff_text)

    delta_path: Path | None = None
    if completed:
        prev_snapshot = completed[-1] / "diff-snapshot.patch"
        if prev_snapshot.is_file():
            delta_lines = list(
                difflib.unified_diff(
                    prev_snapshot.read_text().splitlines(keepends=True),
                    diff_text.splitlines(keepends=True),
                    fromfile=f"{completed[-1].name}/diff-snapshot.patch",
                    tofile=f"{current.name}/diff-snapshot.patch",
                )
            )
            delta_path = current / "diff-delta.patch"
            delta_path.write_text("".join(delta_lines))
            if not delta_lines:
                notes.append("no code changes since the last review round")
        else:
            notes.append(f"{completed[-1].name} is missing diff-snapshot.patch, no incremental delta this round")

    base_sha = git("rev-parse", "--short", args.base).stdout.strip()
    head_sha = git("rev-parse", "--short", "HEAD").stdout.strip()

    print(f"ROUND={round_n}")
    # MODE is decided by "does this lane have any completed rounds", not the round
    # number: a leftover aborted high-numbered round dir should not flip the mode to
    # incremental when there are no PREV_REVIEWS at all
    print(f"MODE={'incremental' if completed else 'full'}")
    print(f"POSTURE={'devils-advocate' if args.devils_advocate else 'standard'}")
    print(f"REVIEWER={reviewer}")
    print(f"BRANCH={branch}")
    print(f"BASE={args.base} @ {base_sha}")
    print(f"HEAD={head_sha}")
    print(f"STATE_DIR={rel(state_dir)}")
    print(f"DIFF_SNAPSHOT={rel(current / 'diff-snapshot.patch')}")
    print(f"DIFF_DELTA={rel(delta_path) if delta_path else 'none'}")
    prev_reviews = ",".join(rel(d / "review.md") for d in completed)
    print(f"PREV_REVIEWS={prev_reviews if prev_reviews else 'none'}")
    print(f"PLAN={rel(plan_path) if plan_path else 'none'}")
    for note in notes:
        print(f"NOTE={note}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
