# Plan Execution Guide

This document provides execution-specific operational constraints for max_full_send Phase 1 (code generation). Code quality, style, and architectural standards are already codified in the codebase (`guides/encyclopedia.md` → each module's `architecture.md`) and do not need to be repeated here.

## References

- `guides/code-review-guide.md` — code review standards (architecture, correctness, security, test coverage, and 13 other review dimensions)
- `guides/naming-guide.md` — naming conventions (module/file/class/function/test naming conventions)

## File Navigation

File paths listed in the plan document and references can be read directly with the Read tool; prefer reading by path directly rather than searching.

- To find files not listed in the plan, use `guides/encyclopedia.md` → the corresponding module's `architecture.md` → navigate directly to the target file
- Glob/Grep should be a last resort — every search consumes one turn; turns should be prioritized for writing code

## Context Management

The plan document is already passed in as part of the prompt and does not need to be re-read from disk.

- Read reference files on demand — when implementing each step, only read the reference files needed for that step; avoid reading all reference files at once, which causes context bloat
- Do not re-read a file that has already been read unless you need to verify a just-made edit
- After context compression, files that need to be re-read should be limited to those required for the current step

## Logging

Logs are the key infrastructure for autonomous debugging. There is no human present during runtime; when problems occur, logs are the only diagnostic tool. Generated code should include sufficient logs to allow execution paths to be traced through logs alone.

Reference the logging patterns in existing code (Kotlin: `Logger.logDebug(TAG, msg)`, Swift: `logger.logDebug(tag:message:)`, Python: `print()`).

## Comment Quality

Code comments must be self-explanatory, independent of the plan document. Plans may be archived, deleted, or rewritten after execution, so generated code must not contain comments that only reference plan context — for example: `// Decision 11/14: ...`, `// plan Q2=B ...`, `// Decision #3 ...`, `// Phase 3 ...`, `// Phase 2 ...`, `// Step 3 ...`.

If a comment is truly needed, write the reason directly alongside the code: why this is done here, what non-obvious constraint applies, which runtime behavior would break otherwise. Do not compress the explanation into a plan decision number, phase number, or option code.

## View / ViewModel / Service Boundaries

Strict adherence to three-layer responsibilities is required during plan execution; avoid stuffing logic into the wrong layer just to "make the button work." The complete specification for boundaries and testing strategy is in [how_to_write_stable_unit_test.md](/Users/dylanliu/work/vibe-coding-editor/unit-test/docs/how_to_write_stable_unit_test.md).

- **Service layer**: carries reusable business logic, rules, bulk data transformations, geometric computations, selection semantics, and workflows
- **ViewModel layer**: responsible for view state, interaction orchestration, menu/button state, and call delegation to Service APIs
- **View layer**: responsible for rendering and event forwarding

When executing a plan, if there is uncertainty about which layer logic belongs in, first determine whether it remains valid without the current UI and whether it might be reused by multiple callers; if yes, push it down to the Service layer.

## ViewModel Unit Test Rules

For the complete specification on fixtures, dispatchers, timed-case isolation, shared helpers, and assertion targets, follow [how_to_write_stable_unit_test.md](/Users/dylanliu/work/vibe-coding-editor/unit-test/docs/how_to_write_stable_unit_test.md).

Only hard execution-phase constraints are kept here:

- When adding new ViewModel tests, prefer reusing the patterns from existing stable test files in the same module
- Do not rewrite the shared harness of an entire stable test file for a single timed case
- If the plan includes unit tests, the references should include that guide

## Plan Execution Verification Boundary

The plan execution phase is only responsible for completing the implementation, tests, and local verification explicitly required by the plan. Global PR wrap-up checks (coverage, unit tests, lint, architecture doc sync, commit/push, PR description) are handled uniformly by `/pr`, to avoid every plan template redundantly binding the same set of PR gates.

## Git Operations Prohibited

AI agents must not perform any git operations (`git add`, `git commit`, `git push`, `git checkout`, etc.). All git operations are the responsibility of the Python orchestration layer in ralph_full_send.
