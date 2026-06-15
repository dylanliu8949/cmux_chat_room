# Code Review Guide

The review agent receives `git diff <base>...HEAD` and an optional associated plan document, then decides whether the code change is ready to merge into main. `<base>` is an optional input parameter (commit hash); when not specified, it defaults to `origin/main`.

This is not lint, not code polish, and not a plan review. Code review focuses on: whether the plan was fully implemented, whether design decisions remain sound after implementation, whether module boundaries are intact, and the long-term health impact of the change on the codebase.
Code review is the CI quality gate, covering the full range from **macro (architecture/module) to micro (class/function)**; it is especially used to block low-quality PRs that were not produced by a `max_full_send` workflow.

## Review Scope

The review is not limited to the changed lines in the diff. If the diff touches a file or module, the review agent should assess the overall state of that file and module. Do not assess modules not touched by the diff.

Examples:
- The diff adds a new method to `PhotoService`, but `PhotoService` already has 30 public methods with responsibilities spanning three domains → suggest splitting
- The diff modifies state management in `ContextMenuViewModel`, but the ViewModel carries business computations that belong in the Service layer → suggest pushing down
- The diff adds `LockStateManager`, but `SessionManager` already has a similar mechanism → reinventing the wheel

Findings outside the diff scope are raised as Suggested (needs-refinement) findings.

## Three Conclusions

| Conclusion | Meaning |
|------------|---------|
| **Ready** | Code is ready to merge |
| **Needs Refinement** | Code may merge; improvement suggestions provided |
| **Abandon** | Code must not merge |

Only Abandon blocks a PR. Needs Refinement is non-blocking feedback.

## Clean Architecture Principles

### Separation of Concerns

- **Service layer**: business logic. No dependency on UI frameworks, rendering engines, or platform APIs.
- **ViewModel layer**: view state and interaction orchestration. Reusable logic should be pushed down to the Service.
- **View layer**: rendering and event forwarding. Controlling show/hide is the View's job; computing state is not.

Decision test: if this logic were needed by a second caller, should it still live where it currently is?

### Single Responsibility

One function does one thing. One file centers on one theme. One module owns one responsibility.

### Minimal Public API (visibility)

Kotlin classes and functions default to `public`. This means **omitting a visibility modifier = exposing a public API**. Code-generation agents are especially prone to this mistake — generating `class Foo` instead of `internal class Foo`.

**Rule**: new classes, functions, and properties must use the minimum visibility:
- **`private`** — used only within the current file
- **`internal`** — used only within the current module (same Gradle module)
- **`public`** — actually called by external modules

**Common violations**:
- ViewModel class missing `internal` (ViewModels are only created in the same module's Screen/Composable; they should not be exposed to other modules)
- Data objects (e.g., preset colors, constant collections) missing `internal`
- Composable functions marked `internal` whose parameter types are `public` (parameter type visibility should not be wider than the function)

**How to check**: Grep the class/function name and confirm whether there are cross-module references. If there are none, visibility must be tightened.

### Dependency Direction

**Module dependencies** (between Gradle/KMP modules):

- editor-phone-ui → editor-service (valid)
- editor-phone-ui → editor-models (valid)
- editor-service → editor-models (valid)
- editor-service → editor-phone-ui (violation)
- editor-models → editor-service (violation)
- editor-models → editor-phone-ui (violation)

Module dependencies should be confirmed against each module's `architecture.md` file.

**Layer dependencies** (between classes within the same or across modules):

- View → ViewModel (valid)
- ViewModel → Service (valid)
- Service → Models (valid)
- View → Service (usually a violation, but legal for simple Views that don't need a ViewModel — see `guides/mvvm-guide.md` "Not every View needs a ViewModel")
- ViewModel → View (violation)
- Service → ViewModel (violation)
- Service → View (violation)

### shared-services Platform Source Sets Are Thin Bridge Forwarders Only

The `iosMain` / `androidMain` source sets inside `shared-services/*` **must not directly call platform-native APIs** (e.g., `platform.Photos.*`, `platform.UIKit.*`, `platform.CoreGraphics.*`, `android.graphics.*`, `android.net.Uri`, `android.provider.MediaStore`, etc.). Platform-native code belongs in the **bridge layer** on the app side (`apps/phone/ios/**/services/*Bridge.swift` and `apps/phone/android/app/src/main/java/**/services/*Bridge.kt`); `iosMain` / `androidMain` should only do **thin forwarding** (type translation, coroutine suspension wrapping, callback conversion) via `expect`/`actual` or injected interfaces.

**Why**:
1. The lifecycle, threading constraints, and memory rules of native APIs (PHImageManager callbacks may fire multiple times, UIKit main-thread requirement, Android Activity/ContentResolver lifecycle, etc.) are easiest to reason about and debug in native languages
2. Native code has access to Xcode / Android Studio's full debugger, profiler, and crash symbolication; the KMP cinterop layer swallows these toolchains
3. Native crashes reflected back through the KMP interop layer result in truncated stack traces that are hard to diagnose on-site
4. The bridge layer is inherently app-surface-specific (phone/tablet/desktop) and should not be mixed with the cross-surface `shared-services` logic in the same source set

**Violation examples**:

```kotlin
// shared-services/photo-library/src/iosMain/.../IosPhotoLibraryAssetSource.kt
import platform.Photos.PHAsset                 // ❌
import platform.UIKit.UIImage                  // ❌
import platform.CoreGraphics.CGImageCreate...  // ❌

internal class IosPhotoLibraryAssetSource : PhotoLibraryAssetSource {
    override suspend fun loadAssetBytes(...) {
        val asset = PHAsset.fetchAssetsWithLocalIdentifiers(...)  // direct platform API call
        // PHImageManager + CGImageCreateWithImageInRect + UIImagePNGRepresentation chain
        // → all of this should be pushed down to PhotoLibraryBridge.swift
    }
}
```

```kotlin
// shared-services/photo-library/src/androidMain/.../AndroidPhotoLibraryAssetSource.kt
import android.graphics.BitmapFactory          // ❌
import android.net.Uri                         // ❌
import android.provider.MediaStore             // ❌

internal class AndroidPhotoLibraryAssetSource(private val context: Context) {
    override suspend fun loadAssetBytes(...) {
        // Full chain of BitmapFactory probe + decodeStream + region crop + scale
        // → should be pushed down to PhotoLibraryBridge.kt (app side)
    }
}
```

**Correct form**:

```kotlin
// shared-services/photo-library/src/iosMain/...
internal class IosPhotoLibraryAssetSource(
    private val bridge: PhotoLibraryBridgeProtocol,   // injected from app side, protocol + impl defined in Swift
) : PhotoLibraryAssetSource {
    override suspend fun loadAssetBytes(...): ImageData? =
        suspendCancellableCoroutine { cont ->
            bridge.loadAssetBytes(localMediaId, region, target) { result ->
                cont.resume(result)            // only type translation and callback bridging
            }
        }
}
```

```swift
// apps/phone/ios/.../services/PhotoLibraryBridge.swift
@objc class PhotoLibraryBridge: NSObject, PhotoLibraryBridgeProtocol {
    @objc func loadAssetBytes(...) {
        // PHAsset / PHImageManager / CGImageCreateWithImageInRect /
        // UIImagePNGRepresentation — all platform-native logic stays in Swift
    }
}
```

**Exemptions**:
- Official KMP libraries (e.g., `kotlinx-io.SystemFileSystem`, `kotlinx-datetime`, ktor engines) do not count as "platform-native APIs" — they are KMP abstractions and may be used directly in `*Main` source sets
- `actual` implementations of `expect` functions that only use JVM stdlib (`java.io.*`, `java.util.*`) or Kotlin native stdlib (not `cinterop platform.*` packages) are exempt
- Simple constants / enums / static config (no behavior, no lifecycle) may remain in `*Main`

**What to check during review**:
- Grep `shared-services/*/src/{ios,android}Main/**/*.kt` for `^import platform\.` and `^import android\.(graphics|net|content|provider|media|hardware|util|os)\.` — any match is a violation
- `@OptIn(kotlinx.cinterop.ExperimentalForeignApi::class)` in shared-services iosMain — a strong signal that CoreGraphics / CoreFoundation is being called directly; this should be pushed down to a Swift bridge
- iosMain/androidMain classes with function bodies longer than ~20 lines that reference platform APIs — these almost certainly belong in a bridge

**Severity**: see dimension 3 "Architecture & Design".

### Appropriate Use of Dependency Injection

DI is appropriate when the same instance needs to be shared across multiple unrelated locations. For example, `PhotoService` being used by multiple screens for photo upload/download is a valid DI use case.

DI is also appropriate for cross-platform compatibility. Define an interface (e.g., `PaymentService`), with iOS/Android/macOS each providing its own implementation injected via DI. The injection can happen at compile time (smaller binary) or at runtime (e.g., switching between pre/production environments on the server side).

If a dependency is only used in one place and has no platform variants, pass it directly through the constructor. For example, `RenderEngine` is only used by `CanvasView` and `PlatformCanvasView` — pass it as a parameter directly, don't use DI.

Over-using DI obscures object ownership and lifetime.

### Interface Segregation

Do not create large, catch-all interfaces. Each interface should serve one use scenario.

### Inter-Module Communication

Modules should communicate through explicitly defined interfaces (function calls, data flows, callbacks), exposing read-only interfaces rather than mutable references.

### Defensive Checks Belong in the Service Layer

Input validation and boundary checks belong in the public APIs of the Service layer, not in the callers. The Service is the sole entry point for business logic and is responsible for ensuring parameters are valid (clamping out-of-range values, intercepting nulls, rejecting illegal states). Callers (ViewModels, gesture handlers, UI layer) should not repeat these checks — they trust the Service contract.

Benefits: validation logic is written once; new callers won't introduce bugs by forgetting to validate; the Service behaves consistently for all consumers.

### Assert.that / Assert.notNull / Assert.unreachable

For **state violations that should never happen** (not expected runtime errors, but code bugs), use `Assert.*` (from `com.vibe.assertion`) rather than `Logger.logError`. Semantically aligned with iOS Swift `assert(_:_:)` and Kotlin `assert(-ea)`: **in debug builds, throws `AssertionError` and terminates the process**; in release builds, degrades to `Logger.logError` and the caller handles the return value. See `shared-services/assertion/docs/how_to.md`.

- `Assert.that(condition, tag) { message }` — returns `Boolean`; when the condition is false, throws `AssertionError` in debug / writes `[ASSERT_FAILED]` ERROR log in release
- `Assert.notNull(value, tag) { message }` — returns `T?`; when the value is null, throws `AssertionError` in debug / writes a log in release
- `Assert.unreachable(tag) { message }` — returns `Nothing`; **terminates in both builds** (log + throw); use in `when` exhaustiveness fallbacks and other control-flow positions requiring `Nothing`

One-liner usage (preferred):
```kotlin
if (!Assert.that(isInCropMode(), LOG_TAG) { "applyCrop: not in crop mode" }) return
val element = Assert.notNull(getElementById(id), LOG_TAG) { "element $id not found" } ?: return
```

**Do not manually write `[ASSERT_FAILED]` prefix in the callsite message** — `Assert.*` adds the prefix internally; writing it manually produces a doubled prefix.

**When to use assert vs logError**:
- `Logger.logError`: expected errors that may occur at runtime (network timeout, file not found, invalid user input)
- `Assert.that` / `notNull` / `unreachable`: state that should never occur — if it does, it indicates a code bug

On the unit-test side: the debug path naturally throws `AssertionError` → test fails. The `UnitTest` base class calls `BuildInfo.initialize(BuildType.DEBUG, ...)` in `@BeforeTest` to ensure derived tests take the throw path. Tests that intentionally trigger an assertion should use `assertFailsWith<AssertionError> { ... }` to catch and check `ex.message`.

**What to check during review**:
- New `if (x == null) return` or `if (x !is Type) return` — if that condition should never happen, use `Assert.that` / `Assert.notNull`
- All Service-layer public methods that accept an `elementId` parameter should assert element existence at the entry point
- During migration, watch for the literal `[ASSERT_FAILED]` prefix appearing twice — all manually written prefixes should be stripped

### KISS

If a feature still works correctly after removing an abstraction, that abstraction should not exist.

Code review must actively suppress redundant components and data structures that "look more engineered." Don't automatically accept a new `Locator`, `Descriptor`, `Context`, `Result`, sealed wrapper, protocol/interface, or component class just because a new noun appeared in the implementation. First look at what the real callers actually need:

- A result object with only one caller consuming only one field should revert to a simple return value.
- A locator wrapping only two existing IDs with no additional invariants should use the existing parameters or existing domain types directly.
- A public/shared data class that only wraps an existing domain type plus a few fields should be treated as YAGNI by default. If the extra fields are stable domain facts, consider adding them to the existing type or exposing them as derived APIs; if they are only needed temporarily by the current caller, compute them in the caller — do not introduce a shared wrapper.
- Private/internal pipeline carriers are different: using a local `Result` / sealed carrier to carry intermediate state through async worker → drain, multi-stage parser, or batch validation workflows is legitimate. The review focus is whether it expresses a real stage boundary, stays within the minimal scope, and does not leak into module-external APIs.
- Hit-test / lookup / resolve APIs should not return "possibly useful later" fields like kind, bounds, index, localPoint if the current caller doesn't use them.
- A new component that only splits a function into interface + implementation + registration with no reuse benefit or isolation gain is over-engineering.

Ask concrete questions during review: if this wrapper were removed, could the caller still complete its work with existing data? Is every field in this complex return value actually used by the current feature? If the answer is no, require simplification. Do not accept "might be needed in the future" as justification; introduce the right abstraction when the future need actually arrives.

If the implementation ends up significantly more complex than the original plan, it should also trigger a KISS/YAGNI review. The plan stage already defined the expected change surface, file count, number of abstractions, and module boundaries; if the implementation adds wrappers, interfaces, managers, factories, state machines, config items, or cross-module APIs not in the plan, the reviewer must require justification. A valid exception is when the implementation uncovered real constraints the plan missed and the added complexity directly solves the current requirement; otherwise, default to reverting to the simpler form in the plan, or updating the plan first before proceeding.

### DRY

The same logic exists in only one place. Distinguish genuine duplication from surface similarity.

### YAGNI

Extension points without confirmed requirements should be questioned.

Especially intercept publicly exposed wrapper types added "just to return a few fields": if `FooWrapper(foo, a, b)` has `a` and `b` as real properties or invariants of `foo`, evaluate whether they belong in `Foo` itself; if they can be derived from `foo` or only serve a single call site, do not introduce a wrapper. The more types a shared API returns, the more contracts there are to maintain later — "might be useful someday" is not a valid justification. Local intermediate result types are only valid when they reduce complexity in multi-stage flows, isolate thread/stage boundaries, and do not expand the public API contract.

### Follow Existing Patterns

Patterns already in the codebase take priority. Introducing a new pattern requires explaining why the existing pattern is insufficient.

### Factory Pattern Exception

`*Factory.kt` / `*Factory.swift` files are exempt from DRY, YAGNI, KISS, and minimal change surface constraints. See `guides/factory-pattern-guide.md`.

### Refactoring Should Be Done in One Pass

Refactoring and module re-architecture should be completed in a single PR. Splitting across multiple PRs leaves the codebase in a long-lived mixed state that is hard to test and hard to reason about. If the scope is too large to complete in one pass, narrow the refactoring scope rather than executing it in batches.

### No Meaningless @Deprecated Transition Periods

This is a mobile app; every release is compiled from the latest code at that moment. There is no "older client" to maintain compatibility for — every user runs the same build.

- Do not "mark as `@Deprecated` now, delete in the next PR" — delete directly
- Do not "keep old and new in parallel, migrate later" — complete the migration in one pass

## Review Dimensions

### 1. Plan-to-Code Change Completeness Check

If a plan document is provided, **first** check whether the code changes fully cover all the work in the plan. Large tasks under limited context windows may result in the code-generation agent losing context and omitting some work.

How to check:
- Go through `Files to Change` item by item and verify each file has a corresponding change
- Check whether the approach in `Archived Decisions` was correctly implemented
- If a UI test plan is provided, check whether AccessibilityIds and UI components have been implemented

Common omission patterns:
- **File omission**: the plan lists 10 files, the diff only covers 7
- **Step omission**: the plan has 8 steps, the last 2 are completely missing
- **Partial implementation**: files were created but only have a skeleton (empty function bodies, TODOs, placeholders)
- **Test omission**: tests required by the plan were not written

Severity:
- Core feature not implemented (multiple files or key steps missing) → **Abandon**
- Implementation differs from the `Archived Decisions` approach → **Needs Refinement** (note the deviation, but don't block if the result is reasonable)
- Minor omission (one or two non-critical files) → **Needs Refinement**
- Implementation differs slightly from the plan but the architecture is sound → **Needs Refinement** or ignore

### 2. MVVM Architecture Compliance

When the diff touches ViewModel, View, or Service layer code, it must be checked against `guides/mvvm-guide.md` for compliance.

Checkpoints:
- **ViewModel must inherit `androidx.lifecycle.ViewModel`**, manage state with `StateFlow<UiState>`, and not use `mutableStateOf`
- **ViewModel has zero platform dependencies** — no references to Compose, Context, or Android/iOS frameworks
- **Business logic belongs in the Service** — ViewModel only does state mapping and event forwarding; it does not contain reusable business computations
- **View layer is ultra-thin** — View only renders and forwards events; it does not call the Service and does not compute state
- **Composition root pattern** — ViewModel is created at the Screen level via `viewModel { }` and passed down as state + lambdas to child components
- **Not every View needs a ViewModel** — pure UI state (expand/collapse, animation) can use `remember` / `mutableStateOf`
- **Constructor injection** — ViewModel dependencies are passed via the constructor; Service Locator patterns (e.g., `Koin.get()`) are not used
- **Unit tests** — ViewModel must be testable on a pure JVM using `Dispatchers.setMain(UnconfinedTestDispatcher())`

Severity:
- ViewModel directly depends on platform framework (Context, Compose API) → **Abandon**
- Business logic in ViewModel that cannot be easily pushed down → **Abandon**
- View calls Service directly, bypassing ViewModel → **Abandon**
- ViewModel uses `mutableStateOf` instead of `StateFlow` → **Needs Refinement**
- ViewModel obtains dependencies via Service Locator → **Needs Refinement**
- ViewModel unit tests missing → **Needs Refinement**

### 3. Architecture & Design (General)

Code review is also an opportunity to re-examine design decisions. Some choices that seemed reasonable at the planning stage may expose problems after implementation (interfaces more complex than anticipated, wrong abstraction granularity, unnatural responsibility division).

Checkpoints:
- Are new classes/functions in the correct architectural layer?
- Are module boundaries intact?
- Does the diff introduce a new abstraction that duplicates an existing mechanism?
- **Is visibility minimized** — do new classes/functions/properties use `internal` or `private`? (Kotlin defaults to `public`, must be explicitly tightened; see the "Minimal Public API" section under Clean Architecture)
- Is the dependency direction correct?
- Are new abstractions necessary?
- **Are shared-services platform source sets only thin bridge forwarders** — does `shared-services/*/src/{ios,android}Main/` directly `import platform.*` / `import android.{graphics,net,provider,...}`? Platform-native logic should be pushed down to `apps/phone/*/services/*Bridge.{swift,kt}`. See the "shared-services platform source sets" section under Clean Architecture.

Severity:
- Business logic in View/ViewModel layer that cannot be easily moved → **Abandon**
- Circular dependency → **Abandon**
- Breaks existing module boundaries → **Abandon**
- Reinvents the wheel → **Abandon**
- Over-abstraction that doesn't break the architecture → **Needs Refinement**
- `public` that could be `internal` → **Needs Refinement**
- Module responsibility bloat trend → **Needs Refinement**
- shared-services iosMain / androidMain calling platform-native APIs directly (not through bridge) → **Needs Refinement**

### 4. Technology Selection

When the diff introduces a new framework, library, or platform API, review whether the choice is sound. Evaluation is based on three pillars:

- **Latest & Greatest**: is the platform-recommended modern solution being used, rather than a superseded old approach (e.g., SwiftUI vs UIKit, Compose vs View-based XML, Kotlin Coroutines vs RxJava)?
- **Most Popular**: community adoption rate, maintenance activity, ecosystem support. Obscure choices mean fewer references and harder hiring.
- **Most Documented**: quality of official docs, StackOverflow coverage, richness of tutorials and examples.

The technology stack that all three pillars point to is also the one where AI agents generate the highest quality code — the technology with the most training data coverage produces fewer errors and better output.

Checkpoints:
- Is a deprecated platform API being used that has been officially superseded (e.g., building new screens with UIKit instead of SwiftUI)?
- Is an obscure third-party library being introduced when a platform-native solution or mainstream library would suffice?
- If the codebase already uses a particular tech stack, is new code introducing a different stack without justification (e.g., project uses Kotlin Coroutines, new code uses RxJava)?

Technology choices that must be Abandoned (zero tolerance):
- **Deprecated package managers**: CocoaPods (SPM should be used instead)
- **Reactive frameworks superseded by platform-native alternatives**: RxSwift, ReactiveSwift, RxJava (iOS should use Combine/async-await, Android should use Kotlin Coroutines/Flow)
- **Any platform API officially deprecated**

Severity:
- Any item on the zero-tolerance list above → **Abandon**
- Obscure third-party library replacing a platform-native solution without sufficient justification → **Needs Refinement**
- Inconsistent tech stack within the codebase that doesn't affect architecture → **Needs Refinement**

### 5. Correctness

Checkpoints:
- Null handling: null/Optional/empty collections
- Boundary conditions: off-by-one, empty input, very large input, concurrency
- State management: are transitions complete? Are illegal states possible?
- Resource management: are streams, connections, and subscriptions properly closed?
- Error handling: are exceptions silently swallowed?
- Concurrency safety: race conditions, coroutine/thread safety

Severity:
- Guaranteed crash or data loss → **Abandon**
- Race condition that may cause intermittent crashes → **Abandon**
- Incomplete boundary conditions that don't affect the main flow → **Needs Refinement**
- Error handling could be more precise → **Needs Refinement**

### 6. Security

Checkpoints:
- Hardcoded keys, tokens, passwords
- SQL/command injection, XSS
- Sensitive information stored in plaintext
- Unnecessary permission requests
- Sensitive information emitted in logs

Severity:
- Any security vulnerability → **Abandon**

### 7. Test Coverage

Code review focuses on **whether behavior scenarios are protected by tests**, not on coverage numbers. Coverage scripts handle percentage thresholds; reviewers check whether new code's real use cases, alternative paths, boundary conditions, and failure paths have tests that prove the behavior is correct.

Checkpoints:
- Do new public methods in the Service layer have unit tests?
- Do new user-visible capabilities or core service capabilities cover the main use scenarios, not just the happy path?
- Are real risk boundaries covered: empty collections, single element, multiple elements, first/last position, out-of-bounds input, ID mismatch, duplicate IDs, non-existent targets, coordinates at visual edges, pending edit/undo/redo, etc.?
- For logic whose results are easily affected by context — geometry, hit-testing, sorting, time, serialization, cross-module state — are representative scenarios that change the result covered? For example, hit-testing cannot only test default coordinates; it must also test blank areas, outside the boundary, aligned/offset, rotated/scaled, multiple targets, etc.
- Do the behavior branches changed by Archived Decisions have tests proving they land correctly — e.g., Strict vs Nearest, scope-locked vs cross-layer multi-select, hard-cut signature, carrier-aware write-back?
- Are critical state transitions tested?
- Are conditional branches covered (especially error paths and edge cases)?
- Do tests actually verify behavior (non-null assertions, not overly broad assertions)?

Severity:
- Core business logic with no tests at all → **Needs Refinement**
- Only happy path covered, missing real boundaries / alternative paths → **Needs Refinement**
- Boundary condition tests missing → **Needs Refinement**
- Assertions too broad → **Needs Refinement**

### 8. UI Test Readiness

If a UI test plan is provided, check whether the app code and test code are ready for UI automation testing.

**AccessibilityId consistency**:
- Is every AccessibilityId referenced in the UI test plan already set in the app code (Kotlin: `Modifier.semantics { contentDescription = "id" }`)?
- Do the spelling and casing of AccessibilityIds match the UI test plan?
- Do newly added interactive UI components (buttons, menu items, etc.) all have AccessibilityIds?

**UI Test Framework API**:
- Do the framework functions called in the test steps (under `ui-test/framework/`) exist, or have they been implemented in the diff?
- If new framework functions were added, do the underlying APIs they call (AppiumClient, DebugApiClient) exist?

**Pages directory structure** (see `ui-test/docs/architecture.md` for Pages directory structure conventions):
- Do new pages have a corresponding `pages/{page_name}/` folder?
- Does each page folder contain `cache.py` (element position cache)?
- Are UI component operations split into separate files by component group (e.g., `nav_bar.py`, `context_menu.py`)?
- Do new pages have a corresponding `verify_app_entered_{page}()` function in `verification/app_state.py`?

**State verification support**:
- Do internal states that need to be verified via debug_client (zIndex, element count, lock state, etc.) have corresponding debug server endpoints?
- Do tests involving transforms (move/rotate/scale) have the data interfaces needed for before/after comparison?

**Platform consistency**:
- Are test scripts platform-agnostic (no `if platform == "ios"` branches)?
- Are platform differences handled at lower levels (AppiumClient, platform-aware positioning in cache.py)?

Severity:
- AccessibilityId missing or spelling mismatch → **Needs Refinement**
- Framework functions required by tests don't exist → **Needs Refinement**
- Pages directory structure doesn't meet conventions → **Needs Refinement**
- Debug server endpoint missing → **Needs Refinement**

### 9. Log Coverage

Logs are the primary means for automated debug loops to locate problems at runtime. Without sufficient log coverage, automated debugging cannot work.

**Logs belong in the Service layer and ViewModel layer, not in the View layer.** The View (SwiftUI views, bottom sheets, Composables) is pure UI rendering; every user event flows through callbacks to the ViewModel or Service, so logs belong in the receiving end. Adding logs in the View causes the same event to be recorded multiple times (View once, ViewModel once, Service once), adding noise rather than information.

**Debug logs**: each function in the Service and ViewModel should have one log on each return path, so no matter which branch was taken, the log can confirm where execution reached. Key coverage areas:
- ViewModel user action entry points (open/close panel, confirm/cancel, preview, etc.)
- Service entry points (calls and exits of business logic)
- State transition nodes

**Error logs**: all catch blocks, error paths, and failure fallbacks must log at error level. Error logs are collected by the error reporting system for trend monitoring. Silently swallowing exceptions (empty catch block, catch then just return null) is a clear problem.

Pure functions, simple getters, and View-layer Composables do not need logs.

**Assert coverage**: for states that should never happen (not expected runtime errors), use `Assert.that` / `Assert.notNull` / `Assert.unreachable` (`com.vibe.assertion`) rather than `Logger.logError`. Key checks:
- Do public methods accepting `elementId` assert element existence at the entry point?
- `if (x == null) return` pattern — if null should not happen, change to `Assert.notNull(x) ?: return`
- `if (x !is ExpectedType) return` pattern — if a type mismatch should not happen, add `Assert.that`
- `error()` or `throw` used for impossible branches — change to `Assert.unreachable` (where control flow needs `Nothing`) or `Assert.that(false) ... return` (where release should continue)
- Callsite messages should not manually write `[ASSERT_FAILED]` prefix (`Assert.*` adds it automatically); report doubled prefix where found

Severity:
- Core business paths with no logs at all → **Needs Refinement**
- Catch blocks silently swallowing exceptions without an error log → **Needs Refinement**
- Impossible states using `logError` instead of `Assert.*` → **Needs Refinement**
- Impossible states using `error()` / `throw IllegalStateException` to crash directly (no release fallback) → **Needs Refinement**
- Callsite with literal `[ASSERT_FAILED]` prefix (doubled) → **Needs Refinement**

### 10. Dead Code

Linters catch unused imports, but cannot detect more complex dead code. Check files touched by the diff for:

- **Unused parameters** — parameters in a function signature that are never referenced in the function body
- **Unused functions** — defined but with no callers (confirm with Grep)
- **Unreferenced classes/interfaces** — defined but never instantiated, inherited, or referenced
- **Write-only variables** — `val x = compute()` where `x` is never used by subsequent code
- **Commented-out code** — `// val oldValue = ...` whole lines; version control is the history record
- **Unreachable code** — statements after return/throw

Severity:
- Dead code → **Needs Refinement**

### 11. Naming and Comment Quality

Function names, class names, and property names are documentation in themselves. Names should be descriptive enough that a reader can understand what it is, what it does, what it accepts, and what it returns without reading comments. Any comment that only describes "what this is", "what it does", "what the parameters are", or "what it returns" — while the name already expresses those things — is redundant and should be deleted. This rule applies to functions, class definitions, property definitions, and KDoc/docstring `@param` and `@return` tags.

**Examples of redundant comments (from the codebase):**

Functions:
```kotlin
/**
 * Checks if an element is selected.
 * @param elementId The element to check
 * @param sessionId The session to check in
 * @return true if selected, false otherwise
 */
fun isElementSelected(elementId: String, sessionId: String): Boolean
```
```swift
// Dismisses the photo picker and invokes the completion handler
func dismissPickerAndInvokeCallback(picker: PHPickerViewController, completion: () -> Void)
```
```python
def _build_update_docs_prompt(...) -> str:
    """Builds the documentation update prompt."""
```

Classes:
```kotlin
// Manages viewport state
class ViewportManager : ViewportProvider
```
```swift
// The canvas view controller
class EditorViewController: UIViewController
```
```python
# Executes the check_docs_update skill
class CheckDocsUpdate:
```

Properties:
```kotlin
// The set of currently selected element IDs
val selectedElementIds: StateFlow<Set<String>>
```
```swift
// Current viewport state
var viewport: Viewport
```
```python
# The base branch to diff against
self.base_branch: str
```

**There are only three valid reasons for a comment to exist:**
1. **Design decisions** — explaining why this approach was chosen over the more obvious alternative; the comment must be self-explanatory and cannot merely reference a decision number in the plan
2. **Domain knowledge** — business rules or industry conventions that a reader without domain background cannot infer from the code
3. **Traps and warnings** — non-obvious side effects, timing dependencies, or platform behavior differences that you'd only know from having been bitten

Code comments must not rely on plan file context. Plans may be archived, deleted, or rewritten after execution; code lives on. Comments like `// Decision 11/14: ...` or `// per plan Q2=B ...` transfer the understanding burden to an external document. During review, require such comments to be rewritten as complete explanations. For example, instead of "Decision 11: lossy restore of interactionMode", write directly: "state sync pull only restores Idle or ElementSelection; cursor, cell range, and embedded contentId are all local ephemeral UI state, so only the mode label is intentionally sent here."

```kotlin
// On iOS, PHPickerViewController triggers KLKeyboardObserver constraint conflicts
// during the modal dismiss animation; the Kotlin callback must be deferred
// to the dismiss completion handler                        ← trap & warning
fun dismissPickerSafely(...)
```

Decision test: after reading the comment and then the name, if the comment provides no information beyond what the name already conveys, it is redundant.

**Spelling must be correct**: English words in function names, parameter names, class names, and variable names must be spelled correctly. Common errors: `recieve` → `receive`, `seperate` → `separate`, `occured` → `occurred`, `lenght` → `length`.

Severity:
- Redundant comments (including `@param`/`@return` KDoc tags) → **Needs Refinement**
- Comments that only reference a plan decision number, issue number, or option code without self-explaining the reason inline → **Needs Refinement**
- Spelling errors → **Needs Refinement**

### 12. TODO / FIXME

Committed code must not contain `TODO` or `FIXME` comments. These markers indicate unfinished code. Unfinished code should not enter the codebase; known issues should be tracked via issues/tickets, not left in code comments.

Severity:
- `TODO` or `FIXME` present → **Needs Refinement**

### 13. Empty Function / Class Bodies

Empty function or class bodies are unfinished code. Empty implementations should be treated as skeleton code and must not be committed.

```kotlin
fun onElementSelected(elementId: String) {
    // TODO: implement
}
```

Severity:
- Empty function body or empty class body → **Needs Refinement**

### 14. Single-Purpose PR

A PR should do only one thing. If the diff contains multiple independent purposes (e.g., new feature + unrelated refactor, two unrelated bug fixes, new feature + documentation restructuring), they should be split into separate PRs rather than merged into one.

**Acceptable incidental changes** (not considered multiple purposes):
- Fixing a few lines of typos/formatting in passing
- Extracting a small utility function as part of the current feature
- Minor code style polishing scattered across a few files

**Cases that must be split**:
- A PR contains both a complete independent feature (S-size or larger) and other work — i.e., "hiding an S PR inside an XL/XXL/XXXL PR"
- Two unrelated bug fixes combined in the same PR, each of which could be released independently
- A PR simultaneously contains a breaking API change and the feature implementation that depends on that change

Decision test: if you split the diff by purpose, can each part be independently reviewed, independently merged, and independently reverted? If yes → should be split.

Severity:
- Contains multiple independent purposes with non-trivial work on each side → **Abandon**

### 15. Bugs (Unforeseen Edge Cases)

Bugs are not correctness issues (those are covered by unit tests), but **unhandled, unforeseen edge cases that cause partial or complete system failure**. These typically occur at the user interaction layer — the code logic is correct on the normal path, but under specific conditions users end up in an unrecoverable state.

Typical patterns:
- **Dead-end navigation** — a button navigates to a page with no back button, no back gesture, and no exit mechanism; the user is trapped
- **Non-dismissible popups/modals** — a dialog or bottom sheet is presented with no close button, tapping outside has no effect, and the back gesture doesn't work
- **Deadlock state** — the state machine reaches a state with no outgoing transitions; the user cannot trigger any operation to return to a normal flow
- **Irreversible destructive operation** — the user triggers an action (e.g., delete, reset) with no confirmation prompt and no undo mechanism
- **Input loss** — the user fills in a form or edits content, then screen rotation, backgrounding, or accidental navigation causes all input to be lost with no way to recover

How to check:
- Mentally walk through new or modified navigation, popups, and state transitions added in the diff
- Ask: "What can the user do in this state? If the answer is 'nothing', that's a bug"
- Check whether all new pages/popups have an exit path
- Check whether every state in the state machine has at least one outgoing transition

Reporting requirements (TDD principle):

When a bug is found, the review agent must provide three items simultaneously:
1. **Reproduction test** — describe a unit test or UI test case that can reproduce the bug (inputs, action steps, expected failing assertion), so the fixer can write the test first, confirm it is red, then fix
2. **Fix suggestion** — a specific fix (which file to change, how to change it, why)
3. **Regression test** — how the test should turn green after the fix (expected passing assertion)

If the bug involves a user interaction flow (navigation, popups, state transitions), suggest both a unit test (validating state machine/logic layer) and a UI test (validating the end-to-end user flow).

Severity:
- User trapped, must force-quit the app → **Abandon**
- Destructive operation with no confirmation and no undo → **Abandon**
- Edge case causes feature degradation but there is an alternative path → **Needs Refinement**

## Guardrails

1. **Read the code before concluding** — if the diff says function A calls function B, Read function B to confirm its signature and behavior.
2. **Don't guess** — when uncertain, Read the source file.
3. **Don't modify any files** — this is a read-only operation.
4. **Distinguish facts from preferences** — an architecture violation is a fact; a naming style is a preference. Only Abandon on facts.
5. **Give specific suggestions** — cite file paths and line numbers, and describe what the change should be.

## Running Tests

The review agent may run unit tests during the review to verify correctness, but should do so selectively — only running tests directly related to the changes in the diff, not the entire test suite. CI runs all unit tests and UI tests, and those results are the gate that blocks merging.

Running tests during code review is intended to help the agent quickly verify suspected correctness issues, not to replace CI.

## Nitpicking vs. Real Findings

The review agent must distinguish between nitpicking and real findings. The severity mapping is defined by this guide; the review agent must not independently escalate or downgrade severity.

**The following are nitpicking (should be ignored or omitted):**
- Suggesting renaming when the current name is already sufficiently descriptive
- Suggesting optional logs, comments, or docstrings
- Proposing minor refactors that don't affect correctness if not done
- Suggesting error handling for scenarios that cannot happen
- Commenting on code not touched by the diff that doesn't involve architectural issues

**The following are NOT nitpicking (must be enforced):**
- Any item in the 15 review dimensions whose severity mapping is Abandon
- Broken tests or API mismatches
- Correctness bugs
- Security vulnerabilities
- Severity mappings explicitly defined in the 15 review dimensions of this guide

**Key principles:**
- The severity mappings in this guide are final — do not escalate style preferences to Abandon; do not downgrade Abandon standards to Needs Refinement
- If a finding cannot be mapped to any of the 15 review dimensions in this guide, it is most likely nitpicking
- Early return is always preferable to nested conditionals — this is not a style preference

## Output Format

### Detailed Analysis

Organized by dimension. Each issue includes:
- **File path and line number**
- **Description of the issue**
- **Severity** (critical🔥 / high / medium / low🧘)
- **Specific suggestion**

### Final Conclusion

The last line must be one of:

- `Ready` — may merge
- `Needs Refinement` — may merge; all suggestions listed before the final line
- `Abandon` — must not merge; all blocking reasons listed before the final line

The output ends with the conclusion line; nothing is appended after it.

## Additional Resources

Project-internal guides:

- **Naming conventions**: `guides/naming-guide.md` — module/file/class/function/test naming conventions
- **Terminology dictionary**: `guides/dictionary.md` — project term definitions

The review agent may use WebSearch/WebFetch to consult the following official documentation as needed:

- **Kotlin**: https://kotlinlang.org/docs/coding-conventions.html
- **Swift**: https://www.swift.org/documentation/api-design-guidelines/
- **Jetpack Compose**: https://developer.android.com/develop/ui/compose/documentation
- **SwiftUI**: https://developer.apple.com/documentation/swiftui
