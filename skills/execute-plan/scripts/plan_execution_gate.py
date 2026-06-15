#!/usr/bin/env python3
"""Gate check for /execute-plan: deterministic, agent-free pre-flight validation.

Enforces every condition that /execute-plan used to express as agent prose:

  0. Plan was generated from the canonical template (delegated to
     plan_template_check.check_template_match — catches users who try to
     execute against a custom / homegrown template).
  1. **Status** field exists and is one of {review-plan-complete,
     plan-execution-in-progress}.
  2. **Current Plan Completeness** is a number ≥ 95%.
  3. Decisions Needed has no unresolved items (only the prose intro and the
     completeness line are allowed; numbered/bulleted decision items must
     have been migrated to Archived Decisions first).
  4. References is non-empty (must contain at least one list item / link /
     file path, not just the prose intro and Important blockquote).
  5. Implementation Steps is non-empty (must contain at least one step /
     phase / checkbox, not just template boilerplate).
  6. Every file checkbox under Files to Change (excluding the
     <!-- Example --> block) is checked.
  7. Implementation Steps structure: Phase numbered 1,2,3,… and Step restart
     at 1 inside each Phase, incrementing by 1 (no cross-phase continuous
     numbering, no step-number gaps).

Side effect: on PASS, this script also bumps **Status** in the plan file from
`review-plan-complete` → `plan-execution-in-progress`. This makes the gate
atomic — there's no window where a caller can forget to record that execution
started. Idempotent: if Status is already `plan-execution-in-progress` (resume
case), the file is left untouched.

Exit codes:
  0 — all checks pass; stdout is "PASS" (and a one-line note if the file was
      bumped to plan-execution-in-progress)
  1 — at least one check failed; stdout is "FAIL" followed by one
      "- <reason>" line per failure. Plan file is NOT modified.
  2 — usage error (bad args or plan file not found); message on stderr

Usage:
    python3 skills/execute-plan/scripts/plan_execution_gate.py <plan.md>
"""

import re
import sys
from pathlib import Path


# Co-located sibling script — works when invoked as a file path.
sys.path.insert(0, str(Path(__file__).resolve().parent))
from plan_template_check import (  # noqa: E402
    check_template_match,
    detect_template,
)


ALLOWED_STATUSES = frozenset({"review-plan-complete", "plan-execution-in-progress"})
COMPLETENESS_MIN = 95

STATUS_RE = re.compile(r"^\*\*Status\*\*:\s*(\S+)\s*$", re.MULTILINE)
COMPLETENESS_RE = re.compile(r"^\*\*Current Plan Completeness\*\*:\s*(\d+)\s*%", re.MULTILINE)
NEXT_H2_RE = re.compile(r"^##\s+", re.MULTILINE)
EXAMPLE_BLOCK_RE = re.compile(
    r"<!--\s*Example\s*:.*?BEGIN.*?-->.*?<!--\s*Example\s*:.*?END\s*-->",
    re.DOTALL,
)
HTML_COMMENT_RE = re.compile(r"<!--.*?-->", re.DOTALL)


def extract_section_body(text: str, heading: str) -> str:
    """Return text after `## <heading>` up to the next `## ` heading or EOF."""
    header = re.compile(rf"^##\s+{re.escape(heading)}\s*$", re.MULTILINE)
    m = header.search(text)
    if not m:
        return ""
    start = m.end()
    nxt = NEXT_H2_RE.search(text, pos=start)
    end = nxt.start() if nxt else len(text)
    return text[start:end]


def strip_noise(body: str) -> str:
    """Drop <!-- Example --> blocks, HTML comments, blockquote lines."""
    body = EXAMPLE_BLOCK_RE.sub("", body)
    body = HTML_COMMENT_RE.sub("", body)
    body = "\n".join(line for line in body.split("\n") if not line.lstrip().startswith(">"))
    return body.strip()


def check_status(text: str) -> str | None:
    m = STATUS_RE.search(text)
    if not m:
        return "missing the **Status** field (please use the latest templates/plan-template.md)"
    status = m.group(1)
    if status not in ALLOWED_STATUSES:
        return (
            f"**Status** = '{status}'. /execute-plan only accepts "
            "'review-plan-complete' (written after the plan review passes) or "
            "'plan-execution-in-progress' (resuming execution)"
        )
    return None


def check_completeness(decisions_body: str) -> str | None:
    m = COMPLETENESS_RE.search(decisions_body)
    if not m:
        return "missing the **Current Plan Completeness**: N% field (should be in the 'Decisions Needed' section)"
    pct = int(m.group(1))
    if pct < COMPLETENESS_MIN:
        return f"**Current Plan Completeness** = {pct}% < {COMPLETENESS_MIN}%"
    return None


def check_decisions_empty(decisions_body: str) -> str | None:
    """Decisions Needed must have no remaining decision items."""
    cleaned = strip_noise(decisions_body)
    cleaned = re.sub(r"^\*\*Current Plan Completeness\*\*:.*$", "", cleaned, flags=re.MULTILINE)
    item_re = re.compile(r"^\s*(?:\d+\.|[-*])\s+\*\*", re.MULTILINE)
    if item_re.search(cleaned):
        return "'Decisions Needed' still has unresolved items (should be moved to 'Archived Decisions' before executing)"
    return None


def check_section_has_content(text: str, heading: str) -> str | None:
    """Section must have actual content (list/link/code/heading), not just prose intro."""
    body = extract_section_body(text, heading)
    if not body:
        return f"missing section '{heading}'"
    cleaned = strip_noise(body)
    # A bare file path / bare URL / inline backtick code also count as valid content (common in References)
    has_content = bool(
        re.search(
            r"^(\s*[-*]\s|\s*\d+\.\s|\s*```|\s*\*\*(Step|Phase)|\s*###?\s|\s*\[.+\]\()",
            cleaned,
            re.MULTILINE,
        )
        or re.search(r"https?://\S+|`[^`\n]+`|^\s*\S+/\S+\s*$", cleaned, re.MULTILINE)
    )
    if not has_content:
        return f"'{heading}' appears empty (no list item / sub-heading / code block / link)"
    return None


PHASE_RE = re.compile(r"^\*\*Phase\s*(\d+)\*\*", re.MULTILINE)
STEP_RE = re.compile(r"^- \[[ xX]\] \*\*Step\s*(\d+)\*\*", re.MULTILINE)
SIZE_RE = re.compile(r"^\*\*Size\*\*:\s*(.*?)\s*$", re.MULTILINE)
VALID_SIZES = frozenset({"XS", "S", "M", "L", "XL", "XXL", "XXXL"})
LOC_ESTIMATE_RE = re.compile(r"~?\s*\d+\s*LOC|~?\s*\d+\s*lines|\d+\s*lines\s*or\s*so", re.IGNORECASE)


def check_size_token(text: str, require: bool) -> str | None:
    """Size must be a single grade token — no parenthesized scope/file-count/LOC suffix.

    require=False (review time): empty / template placeholder is allowed (Size is
    filled only after completeness ≥95%). require=True (execution gate): must be set.
    """
    m = SIZE_RE.search(text)
    if not m:
        return "missing the **Size** field (please use the latest templates/plan-template.md)" if require else None
    val = m.group(1).strip()
    if not val or val.startswith("["):
        return "**Size** not filled in (should be a single grade token: XS/S/M/L/XL/XXL/XXXL)" if require else None
    if val.strip("`") not in VALID_SIZES:
        return (
            f"**Size** = '{val}' is not a single grade token (only XS/S/M/L/XL/XXL/XXXL allowed; "
            "no appended parenthetical notes, scope, file count, line count, or work list)"
        )
    return None


def check_loc_estimates(text: str) -> list[str]:
    """The file list and Implementation Steps must not contain LOC / line-count estimates (false precision like ~20 LOC / ~50 lines)."""
    failures: list[str] = []
    for heading in ("Files to Change", "Implementation Steps"):
        cleaned = strip_noise(extract_section_body(text, heading))
        in_fence = False
        for line in cleaned.split("\n"):
            if line.lstrip().startswith("```"):
                in_fence = not in_fence
                continue
            if in_fence:
                continue
            for m in LOC_ESTIMATE_RE.finditer(line):
                failures.append(
                    f"'{heading}' contains a line-count estimate '{m.group(0).strip()}' — remove LOC/line-count estimates, "
                    "describe only responsibilities, boundaries, and behavior"
                )
    return failures


def check_nested_numbering(steps_body: str) -> list[str]:
    """No numbered sub-lists allowed inside Implementation Steps — use unordered lists '-' for step descriptions."""
    failures: list[str] = []
    cleaned = strip_noise(steps_body)
    in_fence = False
    for line in cleaned.split("\n"):
        if line.lstrip().startswith("```"):
            in_fence = not in_fence
            continue
        if in_fence:
            continue
        if re.match(r"^\s*\d+\.\s", line):
            failures.append(
                f"'Implementation Steps' contains a numbered sub-list '{line.strip()[:40]}' — use unordered lists '-' for step descriptions, "
                "order is conveyed by arrangement"
            )
    return failures


def check_steps_structure(steps_body: str) -> list[str]:
    """Phase must be 1,2,3,…; Step must restart at 1 inside each Phase and increment by 1.

    Continuous numbering across phases (Phase 2 starting at Step 3) and gaps
    (Step 4 → Step 6) are both rejected. Plans without Phase headers are treated
    as a single phase. Returns one message per violation; empty list = OK.
    """
    cleaned = strip_noise(steps_body)
    failures: list[str] = []

    tokens: list[tuple[str, int]] = []
    for m in re.finditer(r"^(?:\*\*Phase\s*(\d+)\*\*|- \[[ xX]\] \*\*Step\s*(\d+)\*\*)", cleaned, re.MULTILINE):
        if m.group(1):
            tokens.append(("phase", int(m.group(1))))
        else:
            tokens.append(("step", int(m.group(2))))
    if not any(kind == "step" for kind, _ in tokens):
        return []

    expected_phase = 1
    expected_step = 1
    current_phase: int | None = None
    for kind, n in tokens:
        if kind == "phase":
            if n != expected_phase:
                failures.append(f"'Implementation Steps' phase numbering is not contiguous: expected Phase {expected_phase}, got Phase {n}")
            current_phase = n
            expected_phase = n + 1
            expected_step = 1
        else:
            if n != expected_step:
                where = f"in Phase {current_phase} " if current_phase is not None else ""
                if n > 1 and expected_step == 1:
                    failures.append(
                        f"'Implementation Steps' {where}step numbering must restart from Step 1 (got Step {n}) — "
                        "steps within each phase are numbered independently from 1, do not use continuous numbering across phases"
                    )
                else:
                    failures.append(
                        f"'Implementation Steps' {where}step numbering has a gap: expected Step {expected_step}, got Step {n}"
                    )
            expected_step = n + 1
    return failures


def check_file_checkboxes(files_body: str) -> str | None:
    cleaned = EXAMPLE_BLOCK_RE.sub("", files_body)
    unchecked = re.findall(r"^- \[ \] \*\*(?:New File|Changed File)\*\*", cleaned, re.MULTILINE)
    checked = re.findall(r"^- \[[xX]\] \*\*(?:New File|Changed File)\*\*", cleaned, re.MULTILINE)
    if unchecked:
        total = len(unchecked) + len(checked)
        return f"'Files to Change' still has {len(unchecked)}/{total} unchecked (the developer must review and check each file)"
    if not checked:
        # An empty list would silently PASS and bypass the per-file review gate
        return (
            "'Files to Change' has no file checkbox entries "
            "(expected `- [x] **New File/Changed File**: …`; changes outside the template-exempt file types must be listed per file)"
        )
    return None


def gate(text: str) -> list[str]:
    failures: list[str] = []

    # 0. Plan must be generated from the canonical template.
    _, template_path = detect_template(text)
    if template_path.is_file():
        for tmpl_failure in check_template_match(text, template_path.read_text()):
            failures.append(tmpl_failure)
    else:
        failures.append(f"canonical template missing: {template_path} (abnormal repo structure)")

    if err := check_status(text):
        failures.append(err)

    decisions_body = extract_section_body(text, "Decisions Needed")
    if not decisions_body:
        failures.append("missing section 'Decisions Needed'")
    else:
        if err := check_completeness(decisions_body):
            failures.append(err)
        if err := check_decisions_empty(decisions_body):
            failures.append(err)

    if err := check_section_has_content(text, "References"):
        failures.append(err)
    if err := check_section_has_content(text, "Implementation Steps"):
        failures.append(err)
    failures.extend(check_steps_structure(extract_section_body(text, "Implementation Steps")))
    failures.extend(check_nested_numbering(extract_section_body(text, "Implementation Steps")))
    if err := check_size_token(text, require=True):
        failures.append(err)
    failures.extend(check_loc_estimates(text))

    files_body = extract_section_body(text, "Files to Change")
    if not files_body:
        failures.append("missing section 'Files to Change'")
    else:
        if err := check_file_checkboxes(files_body):
            failures.append(err)

    return failures


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print(
            "usage: plan_execution_gate.py <plan.md>",
            file=sys.stderr,
        )
        return 2
    plan_path = Path(argv[1])
    if not plan_path.is_file():
        print(f"error: {plan_path} not found", file=sys.stderr)
        return 2

    text = plan_path.read_text()
    failures = gate(text)
    if failures:
        print("FAIL")
        for f in failures:
            print(f"- {f}")
        return 1

    # Atomic side effect: gate-pass also marks the plan as in-execution.
    status_match = STATUS_RE.search(text)
    current_status = status_match.group(1) if status_match else None
    if current_status == "review-plan-complete":
        new_text = STATUS_RE.sub("**Status**: plan-execution-in-progress", text, count=1)
        plan_path.write_text(new_text)
        print("PASS")
        print("- Status: review-plan-complete → plan-execution-in-progress")
    else:
        # current_status == "plan-execution-in-progress" (resume case); no bump needed.
        print("PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
