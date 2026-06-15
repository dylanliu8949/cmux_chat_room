#!/usr/bin/env python3
"""Strip non-essential sections from a plan markdown file before /execute-plan.

Removes content that is template boilerplate / process noise but not part of the
actual implementation spec. Goal: feed the executing agent a smaller, focused
plan. The decision-type sections (Decisions Needed / Archived Decisions) are also
stripped — the decision outcomes needed for execution should already have landed
in implementation sections like Implementation Steps / Files to Change (the gate
has verified decisions are cleared), and the execution phase does not need the
decision process itself.

What gets stripped:
- Metadata header (everything before the first `# ` heading: Author / Size / branch
  name / Status / etc.)
- Section-level boilerplate: Rule Priority, Plan Generation Rules, Plan Execution
  Rules, Decisions Needed (resolved items live in Archived Decisions), Archived
  Decisions
- HTML comments (the `<!-- Example -->` placeholders the template ships with)
- Blockquote noise: `> **Size guide**`, `> **Mechanical-change downgrade rule**`,
  `> **Status guide**`, `> **Note**`, `> **Important**`

What is preserved verbatim:
- The title and all `## ` content not in the strip list
- Files to Change, Implementation Steps, Test Plan, Analytics Events, Error
  Tracking, Assertion Checks, Feature Flags / Experiments, etc.

Usage:
    python3 skills/execute-plan/scripts/strip_plan.py <input_plan.md> <output_stripped.md>
    python3 skills/execute-plan/scripts/strip_plan.py <input_plan.md>   # writes to stdout
"""

import re
import sys
from pathlib import Path


SECTIONS_TO_SKIP = frozenset(
    [
        "## Rule Priority",
        "## Plan Generation Rules",
        "## Plan Execution Rules",
        "## Decisions Needed",
        "## Archived Decisions",
    ]
)

BLOCKQUOTE_NOISE_RE = re.compile(
    r"^>\s*\*\*(Size guide|Mechanical-change downgrade rule|Status guide|Important|Note)\*\*"
)


def strip_plan_for_execution(plan_content: str) -> str:
    lines = plan_content.split("\n")
    result: list[str] = []
    skip_section = False
    skip_blockquote = False
    in_header = True

    i = 0
    while i < len(lines):
        line = lines[i]

        if in_header:
            if line.startswith("# "):
                in_header = False
                result.append(line)
                i += 1
                continue
            i += 1
            continue

        if "<!--" in line:
            if "-->" in line:
                i += 1
                continue
            while i < len(lines) and "-->" not in lines[i]:
                i += 1
            i += 1
            continue

        if any(line.startswith(s) for s in SECTIONS_TO_SKIP):
            skip_section = True
            i += 1
            continue

        if skip_section and line.startswith("## "):
            skip_section = False

        if skip_section:
            i += 1
            continue

        if BLOCKQUOTE_NOISE_RE.match(line):
            skip_blockquote = True
            i += 1
            continue

        if skip_blockquote:
            if line.startswith(">"):
                i += 1
                continue
            skip_blockquote = False

        result.append(line)
        i += 1

    cleaned = "\n".join(result)
    cleaned = re.sub(r"\n{3,}", "\n\n", cleaned)
    return cleaned.strip() + "\n"


def main(argv: list[str]) -> int:
    if len(argv) < 2 or len(argv) > 3:
        print(
            "usage: strip_plan.py <input_plan.md> [output_stripped.md]",
            file=sys.stderr,
        )
        return 2

    input_path = Path(argv[1])
    if not input_path.is_file():
        print(f"error: {input_path} not found", file=sys.stderr)
        return 1

    stripped = strip_plan_for_execution(input_path.read_text())

    if len(argv) == 3:
        output_path = Path(argv[2])
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_text(stripped)
    else:
        sys.stdout.write(stripped)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
