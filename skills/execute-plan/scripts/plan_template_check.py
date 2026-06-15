#!/usr/bin/env python3
"""Verify a plan was generated from the canonical template.

A plan passes this check iff, for the canonical template
(templates/plan-template.md):

  1. Every required `## ` section appears in the plan. "Required" =
     every `## ` heading in the template that does NOT contain
     "(if applicable)". Optional sections are ignored.
  2. Every immutable-block MARKER PAIR FROM A POPULATED template block
     appears in the plan — i.e. for each `<!-- <name>: BEGIN -
     immutable -->` / `<!-- <name>: END -->` pair in the template that
     has non-empty body, both markers exist in the plan with non-empty
     body between them.

     Why not byte-match the block bodies? Plans are immutable snapshots
     tied to a base commit. Template content evolves; a plan generated
     last quarter legitimately carries last-quarter's rule wording. The
     markers themselves are the proof of canonical origin — a custom
     template wouldn't ship the `immutable` markers verbatim, and an
     adversary who bothers to fake the markers AND populate them would
     also bother to write a real plan.

Exit codes:
  0 — plan matches the canonical template; stdout is "PASS"
  1 — at least one mismatch; stdout is "FAIL" then "- <reason>" lines
  2 — usage error (bad args or files not found); stderr message

Usage:
    python3 skills/execute-plan/scripts/plan_template_check.py <plan.md>

Also importable: `from plan_template_check import check_template_match`.
"""

import re
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parent.parent.parent.parent
TEMPLATE_PATH = REPO_ROOT / "templates" / "plan-template.md"

H2_RE = re.compile(r"^##\s+(.+?)\s*$", re.MULTILINE)
IMMUTABLE_BLOCK_RE = re.compile(
    r"<!--\s*(.+?):\s*BEGIN\s*-\s*immutable\s*-->(.*?)<!--\s*\1:\s*END\s*-->",
    re.DOTALL,
)
# Used against plans (no '- immutable' qualifier required, since the body may
# have evolved but the marker should still bear the canonical name).
PLAN_BLOCK_OPEN_RE_TEMPLATE = r"<!--\s*{name}:\s*BEGIN[^>]*-->"
PLAN_BLOCK_CLOSE_RE_TEMPLATE = r"<!--\s*{name}:\s*END\s*-->"


def detect_template(plan_text: str) -> tuple[str, Path]:
    # Single canonical template in this repo; signature kept for gate compatibility.
    return ("regular", TEMPLATE_PATH)


def required_sections(template_text: str) -> list[str]:
    return [m.group(1) for m in H2_RE.finditer(template_text) if "(if applicable)" not in m.group(1)]


def immutable_block_names(template_text: str) -> list[str]:
    # Only blocks the template author intentionally populates carry enforcement
    # meaning. Skip blocks whose template body is empty/whitespace.
    return [m.group(1) for m in IMMUTABLE_BLOCK_RE.finditer(template_text) if m.group(2).strip()]


def check_template_match(plan_text: str, template_text: str) -> list[str]:
    # Return list of mismatch reasons; empty list means PASS.
    failures: list[str] = []

    for section in required_sections(template_text):
        section_re = re.compile(rf"^##\s+{re.escape(section)}\s*$", re.MULTILINE)
        if not section_re.search(plan_text):
            failures.append(f"missing required section '## {section}'")

    for name in immutable_block_names(template_text):
        open_re = re.compile(PLAN_BLOCK_OPEN_RE_TEMPLATE.format(name=re.escape(name)))
        close_re = re.compile(PLAN_BLOCK_CLOSE_RE_TEMPLATE.format(name=re.escape(name)))
        open_match = open_re.search(plan_text)
        close_match = close_re.search(plan_text)
        if not open_match or not close_match or close_match.start() <= open_match.end():
            failures.append(
                f"missing the '{name}' immutable-block marker pair"
                f" (expected `<!-- {name}: BEGIN ... -->` and `<!-- {name}: END -->`);"
                " the plan does not appear to be generated from the canonical template"
            )
            continue
        body = plan_text[open_match.end() : close_match.start()].strip()
        if not body:
            failures.append(f"the '{name}' immutable-block body is empty")

    return failures


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print("usage: plan_template_check.py <plan.md>", file=sys.stderr)
        return 2

    plan_path = Path(argv[1])
    if not plan_path.is_file():
        print(f"error: {plan_path} not found", file=sys.stderr)
        return 2

    plan_text = plan_path.read_text()
    _, template_path = detect_template(plan_text)
    if not template_path.is_file():
        print(f"error: template {template_path} not found", file=sys.stderr)
        return 2

    template_text = template_path.read_text()
    failures = check_template_match(plan_text, template_text)

    if failures:
        print("FAIL (compared against the canonical template)")
        for f in failures:
            print(f"- {f}")
        return 1

    print("PASS (matches the canonical template)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
