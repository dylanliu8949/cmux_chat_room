---
name: lint-and-fix
description: Swift anti-slop lint fix skill: runs swiftlint --fix on changed files, manually fixes Tier R/M violations, performs small in-module refactors (split files/types/helpers), uses xcodebuild test / swift test as the green gate, then invokes commit-and-push to land the changes. Enforces "lint green != done" and "honest fix or escalate, no silencing-to-pass". This is the fix arm of the anti-vibe-coding-slop defense line (strict ruleset detects; this skill fixes honestly). Use when the user asks to "fix lint", "lint and fix", "clean up lint violations", or "get lint green"; /pr reuses this skill. Cross-agent (claude / cursor / codex). Swift only (native Swift/Xcode project).
---

Fix lint violations in Swift files changed on the current branch. The SOT for judgment principles is [guides/fix-lint-guide.md](../../guides/fix-lint-guide.md) (three-tier risk Tier S/R/M, honest fix vs perfume, prohibited fixes, escalate boundaries, autofix gotchas). This skill only governs execution order.

This skill is the **fix arm of the anti-vibe-coding-slop defense line**: the strict lint ruleset causes slop to fail (detection); this skill **honestly** fixes the slop (remediation). The primary goal is therefore not "go green" but the guide's hard line — **lint green does not equal done**, **silencing-to-pass is the thing to eliminate, not the tool to reach for**.

This skill is **rule-agnostic**: it only consumes violations reported by `swiftlint` plus the guide's tier classification, and never hard-codes a rule list — this way it automatically adapts to any evolving ruleset without conflicting with in-flight work.

```
INPUT  $ARGUMENTS = [--base <ref>] [files...]
  --base    change baseline (default origin/main); scope = Swift files changed relative to base
  files     optional; explicitly specify files to fix (targeted fix), omit to use changed-vs-base

========== PRIME DIRECTIVE (guide hard lines, must not be crossed) ==========

-- lint green != done: done = lint + build + tests all green (guide opening hard line)
-- Honest fix, do not perfume the smell: when a rule points to the root (dead field /
--   lying cast / dead branch), delete / migrate / make the type honest rather than adding
--   a layer of indirection or disabling to mask the smell
-- No silencing-to-pass: bare // swiftlint:disable, weakening rules in .swiftlint.yml to
--   dodge a single violation — both are prohibited (guide Prohibited fixes).
--   **Always prefer a proper fix**; any disable is a last resort, and tiered by blast radius:
--   · Line-level disable (// swiftlint:disable:next <rule> // <reason>) only for guide's
--     three sanctioned scenarios, with machine-enforced reason + (for cross-module dup) a
--     tracked task; this skill may apply these autonomously (blast radius = one line)
--   · File-level disable (// swiftlint:disable <rule> at top of file or per-file config
--     override) = most severe — equivalent to locally weakening the rule; this skill
--     **must NOT apply autonomously**, must stop and ask for **developer confirmation** (treat as escalate)
-- Do not change business logic / control flow, do not add/remove parameters / error
--   handling / guards to appease the linter — that is a code change, not a lint fix

========== SCOPE ==========

changed   = Swift files changed relative to base (or explicitly passed files)
targets   = build targets / test targets that own the changed files
IF changed is empty → report "no Swift changes, no lint fixes needed" and EXIT

========== EXECUTION (loop until green or escalate) ==========

-- 1. Tier S (safe autofix)
`swiftlint --fix`    # autofix safe Tier S rules on changed files
# TODO(cmux): substitute for ./run lint fix-changed --base <base>; verify exact swiftlint invocation
`swiftformat <files>`  # reformat; do NOT re-indent manually — use the repo formatter
# TODO(cmux): substitute for ./run format format-changed --base <base>; verify swiftformat config path

-- 2. Tier R/M (review before fixing, no blind --fix)
`swiftlint lint <files>`   # remaining violations
# TODO(cmux): substitute for ./run lint check-changed --base <base>
FOR EACH remaining violation
  Classify per guide tier and fix each site manually using field-tested recipes:
    Tier R → read each site and choose the correct fix (optional binding vs force-unwrap,
             guard vs if-let, proper type vs forced cast ...)
    Tier M → investigate first, then act (no-unnecessary-condition: is the type lying?
             if so fix the type / reasoned-disable, do NOT delete the guard.
             exhaustive switch: add the missing case or assertionFailure, do not leave empty default)
  -- Before deleting dead code, classify and gather evidence per guide "Deleting dead code"
  --   (no callers + not reachable from entry points); if evidence is unavailable → stop and ask
  --   the developer, do not guess

-- 3. Small in-module refactor (sanctioned, only when a graded rule fires)
WHEN file-length / cyclomatic-complexity / function-body-length / sonar dup triggers
  Do behavior-preserving splits **within the same module**: split files / split types /
  extract single-purpose helpers / extract constants
  -- Boundary = Swift module. Moving symbols across modules / reshaping public API /
  --   real deprecated-API migration → do NOT fix here, go to ESCALATE

-- 4. Green gate (run after fixing each rule / each target)
`swiftlint lint <files>`    # swiftlint clean
# TODO(cmux): also run xcodebuild build to catch type-breaking autofixes (equivalent of tsc)
`xcodebuild test` / `swift test`   # behavior preserved?
# TODO(cmux): substitute for ./run test unit -p ios or narrower target-level test
  test turns red = the "fix" broke behavior → revert that site and re-fix (usually Tier M)
  -- Revert with git checkout -p / stash / targeted edit; **never** git checkout -- whole file
  --   (guide Recovery)

LOOP 1-4 until lint + build + tests all green, or blocked by ESCALATE

========== ESCALATE (crossing module boundary = hand back to human) ==========

When an honest fix for a violation requires any of the following, **do NOT** hard-fix in
this pass (guide "When to escalate" / "Scope"):
  - Moving or deduplicating symbols across modules, changing dependency direction
  - Reshaping public API (signature / exported surface)
  - Real API migration (deprecated → replacement with different semantics/calling convention)
  - Code that requires device or simulator to verify (UI, gesture, native bridging)
  - Decisions requiring product / data-contract judgment (is a given field / path truly unused)
Action: reasoned-disable (with machine-enforced reason) + record a tracked refactor task,
and **explicitly list** these in the output —
  do NOT silently disable to sneak past. If dup rules are errors, escalate != leave red;
  it means disable-with-reason + tracked task.

========== LAND ==========

IF lint + build + tests all green (including green achieved via sanctioned reasoned-disables)
  invoke `commit-and-push` skill to land this lint fix as an independent commit and push
  -- If this branch already rebased away from origin in this session (typical: /pr rebases
  --   then lints), push with --force-with-lease (Git safety rule); standalone without rebase
  --   uses a normal push
ELSE (blocking items that cannot be honestly fixed within the module)
  Do not commit. Output the escalation list + tracked tasks and hand back to the developer

========== OUTPUT (defect-report style, no self-congratulation) ==========

  - Fixed: list which rules / files were fixed, grouped by tier
  - In-module refactors: which files / types were split (behavior-preserving)
  - ESCALATED: each reasoned-disable + corresponding tracked task + why it crossed the boundary
  - Final status: lint / build / tests each green or red + whether commit-and-push was invoked
Never claim done when only lint is green (guide hard line).

========== /pr reuse ==========

-- /pr's lint step directly invokes this skill (changed-vs-base): it handles lint + build +
--   affected target tests + landing in one shot, replacing the manual lint-fix + commit-and-push
--   steps in the /pr flow.
```
