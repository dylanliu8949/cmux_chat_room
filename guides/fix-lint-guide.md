# Lint Loop Scope Guide

The lint loop is a **lightweight cleanup step**, not a code transformation tool. Its job is to fix issues that are slightly beyond what deterministic auto-fix tools (`ktlint -F`, `swiftlint --fix`) can handle, but still trivial in nature.

## Allowed Fixes (agent CAN do)

- Formatting issues that auto-fix missed
- Missing or incorrect import statements
- Unused variable removal
- Simple type annotation fixes
- Reordering parameters to match expected signatures
- Adding explicit type casts where the linter requires them
- Removing trailing whitespace, fixing indentation
- Renaming to match naming conventions (e.g. `myVar` -> `myVar_` for unused params)
- **MagicNumber fixes**: Extract numeric literals to named constants (e.g. `private const val CORNER_RADIUS = 8f`). This is the standard strategy for detekt MagicNumber violations in source code.
- **ClassOrdering fixes**: Reorder class members to match detekt's expected order: properties → init blocks → constructors → methods → companion object. Move `companion object` to the bottom of the class body; move methods that appear between property declarations to after all properties.
- **CyclomaticComplexMethod fixes**: Use these strategies:
  - Early return on failure cases, like Swift `guard` statements. Replace nested validation / error branches with guard clauses (`if (invalid) return`).
  - Extract cohesive conditional blocks or `when` branches into single-purpose private helper functions.
  - Replace simple loops with collection pipelines (`filter`, `map`, `flatMap`, `any`, `none`, `firstOrNull`) only when the loop is a pure selection / projection / flattening / predicate query. Do not convert stateful loops, logging, mutation, early-exit workflows, or error-handling code into chained higher-order calls just to satisfy detekt.
  Do NOT change business logic — only restructure control flow to reduce cyclomatic complexity.
- **RawFloat fixes** (`lint_float_in_editor`): Replace raw `Float` or `Double` in function parameters and data class fields with type-safe wrappers. Reference `canvas-editor/editor-models/docs/type-safety.md` for the full type mapping. Common replacements:
  - `centerX: Float, centerY: Float` → `center: CanvasPoint`
  - `rotation: Float` → `rotation: Degrees`
  - `scale: Float` / `zoomScale: Float` → `Scale`
  - `fontSize: Float` → `FontSize`
  - `width: Float` / `height: Float` → `CanvasDistance` or `ViewportDistance` (match the coordinate system)
  - Matrix internals, animation interpolation, or other internal math → `@Suppress("RawFloat")`
  - Callers must be updated to pass the wrapped type (e.g. `Degrees(45f)` instead of `45f`)

## Prohibited Fixes (agent MUST NOT do)

- Modifying business logic
- Adding new public API without a lint-driven reason
- Broad refactoring that changes ownership, module boundaries, or behavior
- Adding error handling or validation
- Changing control flow (if/else, loops, etc.)
- Adding or removing function parameters
- Suppressing warnings with lint-disable comments or `@Suppress` annotations
- **Modifying `build.gradle.kts` or any Gradle config files** — these are build configuration, not source code. Extracting constants (e.g. SDK versions) to "fix" MagicNumber violations will cause type mismatches and break compilation. If a linter reports issues in Gradle files, the fix belongs in the lint config (exclude pattern), not in the Gradle file itself.

## Structural Lint Fixes

Some detekt violations are structural, but they are still fixable by the lint loop when the repair is local, mechanical, and preserves behavior. Prefer the smallest split that gives each new function/file a clear purpose. Escalate to the code loop only when the required change crosses module boundaries, changes public API shape, or requires product/architecture judgment.

- **`TooManyFunctions`** — class has too many methods. Fix: extract cohesive groups of functions into Kotlin extension files (e.g. `MyService.kt` + `MyService.Locking.kt` + `MyService.Gesture.kt`). This pattern keeps the class as a single API entry point while splitting code across files by responsibility domain. The extension functions have full access to the class's public/internal API. See `LocalSessionManager` + `LocalSessionManager.Gesture.kt` + `LocalSessionManager.TextEditing.kt` + `LocalSessionManager.Locking.kt` for the canonical example.
- **`LargeClass` / file line-count limit** — class or file exceeds the threshold. Use one of two strategies:
  - Split into purpose-specific extension files when the existing type should remain the API entry point. This is the established editor-service pattern: keep the service class, move cohesive operations into files such as `EditorService.Table.kt`, `EditorService.TextEditMode.kt`, or `LocalSessionManager.TextEditing.kt`.
  - Split into purpose-specific files/classes when the code already represents separate concerns. Each new file should own one clear responsibility, not become another generic bucket.
- **`lint_folder_size` / folder size violations** — too many source files live directly in one production directory. This is an architecture signal, not a request to shuffle files until the count drops. Start by reading the module's `docs/architecture.md`, then inspect the whole package and its tests before moving anything.
  - Split by meaningful domain boundaries that match the module architecture. For example, a flat CLI package can become `app/`, `protocol/`, `commands/`, `serialization/`, `sync/`, and `assets/`; an editor-service text area might need domains like `editing/`, `style/`, `markdown/`, `links/`, `hitTest/`, and `embedded/`.
  - Prefer package-aware moves when the new folders represent real ownership boundaries. Update `package` declarations, imports, DI wiring, generated start-script main classes, docs, and mirrored test packages in the same change.
  - Do not create generic buckets such as `core/`, `misc/`, `helpers/`, or `utils/` just to satisfy the numeric threshold.
  - Do not move only the minimum number of files when the surrounding module clearly has a broader organization problem. The lint rule is pointing at accumulated drift; fix the package shape, not only the warning.
  - Preserve public API deliberately. If external modules import extension functions from the old package, decide whether the move should update those imports across the repo or whether the package should stay stable and only the file layout changes. Avoid compatibility wrapper files unless there is a real API-stability requirement.
  - Update the architecture document after the move. A folder-size fix that leaves `docs/architecture.md` describing the old package tree is incomplete.
  - Verify with the focused module tests, compile targets that consume the moved APIs, and `bash lint/lint_folder_size.sh <module-or-path>`.
  - Escalate to the code loop when the right split requires product or architecture judgment, crosses many modules, changes public API packages, or exposes a large file that needs behavioral decomposition. The lint loop may report this as a required refactor instead of attempting a risky move.
- **`LongMethod`** — function body exceeds line count threshold. Fix: decompose into smaller private helper functions with clear responsibilities. Use early returns to flatten nested conditionals.
- **`LongParameterList`** — function has too many parameters. Fix: introduce parameter objects, builder patterns, or restructure the API.
- **`RawFloat` (bulk)** — if `lint_float_in_editor` reports many `Float`/`Double` violations in a single file, it likely needs a coordinated refactor (new type-safe wrapper + all callers updated together). Individual fixes are fine for the lint loop; bulk migrations belong in the code loop.

If the lint loop can apply one of the local strategies above without changing behavior, it should do so. If the fix would require deciding new ownership boundaries, redesigning APIs, or moving logic across layers, skip it and leave it for the code loop or a dedicated refactoring task.

## Fix Warnings Proactively

Treat warnings as work to do now, not noise to defer. Many lint rules (folder size, file/class line counts, function counts, complexity scores) emit a **warning** below a threshold and an **error** above it. If warnings accumulate, the next unrelated change in the same area trips the error threshold and blocks an unrelated PR — the person who pays the cost is not the person who created the debt.

- When the lint loop reports warnings on files you touched, fix them in the same PR rather than leaving them for "later".
- When you add a new file to a directory that is already near its folder-size warning, split the package now — don't wait for the error.
- Don't silence warnings with `@Suppress` to keep the diff small. That converts a visible warning into invisible debt.
- The same applies to structural warnings (`LargeClass`, `LongMethod`, `TooManyFunctions`, etc.) — apply the local fixes listed above as soon as the warning appears, while the surrounding code is still fresh in mind.

Warnings exist as an early signal. Ignoring them defeats the purpose of having a two-level threshold.

## Fail-Fast Principle

If lint errors persist after auto-fix + agent attempts, the lint loop should **fail and exit both loops**:

1. **Inner loop**: After `max_iterations` agent attempts, return `LoopResult(passed=False)`
2. **Outer loop**: When lint fails, the debug loop exits immediately (`return 1`)

This is intentional. Persistent lint errors after multiple focused attempts indicate the underlying code needs a larger refactor, which is the **code loop's** responsibility, not the lint loop's.

## Execution Order

```
1. Deterministic auto-fix (ktlint -F, swiftlint --fix)
   - Handles ~90% of formatting issues automatically
   - Commits and pushes if changes were made

2. Lint check (ktlint, detekt, swiftlint lint)
   - If all pass -> done
   - If failures remain -> invoke agent

3. Agent fix (up to max_iterations attempts)
   - Agent sees lint errors and applies simple fixes
   - Each attempt: agent fix -> auto-fix again -> re-check
   - If still failing after max_iterations -> FAIL
```

## Why This Scope Matters

The lint loop runs Sonnet (not Opus) with only 15 turns per iteration. It's deliberately constrained because:

- Lint fixes should be mechanical, not creative
- If the code needs broad restructuring to pass lint, that's a code quality issue for the code loop
- Wasting agent turns on impossible lint fixes delays the entire pipeline
