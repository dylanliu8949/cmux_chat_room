# Unit Test Debugging Guide

This guide covers Ralph-specific constraints for debugging unit test failures. General debugging skills are assumed.

## Guardrails

These rules exist because Ralph runs unsupervised — without them, the agent may take shortcuts that appear to "fix" the build but actually hide bugs.

1. **Never delete or skip tests** - Do not delete, comment out, or `@Ignore` tests to make the build pass
2. **Never weaken assertions** - Do not change expected values, loosen tolerances, or add `try/catch` around assertions
3. **Partial progress over risky attempts** - If multiple things are broken, fix what you're confident about first. Don't let an uncertain fix introduce new errors that wipe out progress you've already made
4. **Do not run build or test commands** - Never run `./gradlew`, `gradle`, or any build/test commands yourself. The orchestration loop runs tests before and after your fixes automatically. Your only job is to read errors, fix code, and hand control back. Running tests yourself wastes time and can hang the entire loop

## Stable Test Writing

How to design stable Service / ViewModel unit tests is defined in [how_to_write_stable_unit_test.md](/Users/dylanliu/work/vibe-coding-editor/unit-test/docs/how_to_write_stable_unit_test.md).

This debug guide only adds one diagnostic rule on top of that:

- if a newly-added or recently-refactored ViewModel suite starts failing broadly, suspect shared harness / fixture changes before suspecting all the assertions at once

## Test Trust Levels

### Existing tests (on `origin/main`)
- Proven stable (run 100+ times on CI)
- **If failing: the application code has a problem, not the test**

### Newly-written tests (added during this run)
- Never validated on CI, may contain bugs
- **If failing: could be an application code issue or a test implementation issue**

## Test Run Artifacts

Each test run creates a timestamped folder:
```
unit-test/.run/<timestamp>/
├── output.log       ← Full build + test output
└── test-results/    ← XML test reports
    ├── TEST-com.example.ModuleTest.xml
    └── ...
```

XML reports contain assertion error messages, expected vs actual values, and stdout logs. Only read XML files for tests that actually failed.
