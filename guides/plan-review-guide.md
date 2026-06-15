# Plan Document Review Guide

A plan document records **architecture-level decisions**, not implementation-level code specifications. Its purpose is to give the executing agent a clear understanding of: what to do (feature boundary), where to do it (module and layer assignment), and why (decision context and constraints). The how — specific parameter signatures, control-flow implementation details, precise code fragment syntax — is something the executing agent can determine on its own; the plan does not need to specify it.

**A plan is not a literally compilable blueprint.** The executing agent reads the codebase, understands the context, and handles implementation details autonomously. The plan's value is in locking down architectural decisions so the agent does not make a wrong directional choice at a critical fork — not in replacing the agent's engineering judgment.

**The review goal is therefore**: whether architectural decisions are clear, whether module boundaries are explicit, whether the key "what to do" is unambiguous — not whether every code fragment is precise to the parameter type. Code fragments in the plan are illustrations of intent, not templates to copy verbatim. If a pseudocode snippet lets the agent understand the intent, it is sufficient.
Plan review operates only at the **macro level** (architecture, module, boundaries, decisions); it does not address function-level or code-style nitpicks.

**Decision quality review**: the review **must evaluate** whether the design choices in `Archived Decisions` are sound. Decisions are the foundation of the plan — if a decision conflicts with the existing architecture, violates Clean Architecture principles, or has an obviously better alternative, the plan should not pass even if its structure is perfect.

Evaluation dimensions when reviewing decisions:
- **Architectural consistency**: does the decision align with the architectural patterns and module boundaries already in the codebase? Relevant `architecture.md` files must be read to confirm.
- **Clean Architecture compliance**: does the decision meet the requirements in the Clean Architecture Principles section of this guide? (Separation of concerns, dependency direction, single responsibility, etc.)
- **Simplicity**: does a simpler alternative exist? (KISS, YAGNI)
- **Consistency**: how are similar problems solved in the codebase? Does the decision follow established patterns?
- **Duplication**: does the decision introduce an implementation that duplicates an existing mechanism? (DRY)
- **Technology selection**: do frameworks, libraries, or platform APIs introduced by the decision satisfy the three pillars — **Latest & Greatest** (platform-recommended modern approach), **Most Popular** (high community adoption, active maintenance), **Most Documented** (solid official docs, broad community coverage)? The tech stack all three pillars point to is also the most stable foundation for AI agents generating high-quality code.

Evaluation results for `Archived Decisions` map to the new `Status` enum (see the "Status description" table at the top of `templates/plan-template.md`):
- `Archived Decisions` violate architectural principles and cannot be locally repaired → **`abandoned`**
- `Archived Decisions` have a better alternative, or the direction is right but something is vague/missing → revert to **`create-plan-complete`** (present alternatives to the developer; developer updates the plan after deciding)
- `Archived Decisions` are sound → **`review-plan-complete`** (ready for `/execute-plan`)

Note: the review does not judge pure style preferences (naming style, code organization, etc.) — only architectural soundness. If multiple approaches are architecturally equivalent and the difference is minor, do not require changes based on subjective preference.

## The Four Outcomes of a Plan Review

| Outcome | Meaning | Status Written | Next Action |
|---------|---------|----------------|-------------|
| **Prerequisites not met** | The plan does not satisfy the prerequisites for review (template structure incomplete, unresolved decision items remain, etc.) | Do not enter review; keep `create-plan-in-progress` | Developer continues refining the plan, then resubmits for review |
| **Abandon** | Plan has been reviewed; there are fundamental problems that cannot be salvaged by local fixes | `abandoned` | Discard the current plan and start fresh |
| **Needs Refinement** | Plan has been reviewed; the direction is right, but there are ambiguities, omissions, or conflicts | Revert to `create-plan-complete` | Present choices to the developer; developer decides and updates the plan, then re-runs `/review-plan` |
| **Executable** | Plan has been reviewed; no ambiguities, no conflicts, no omissions | `review-plan-complete` | Can proceed directly with `/execute-plan` |

**The distinction between "prerequisites not met" and the other three outcomes**: "prerequisites not met" is a precondition check before entering the review, not a review result. When the plan does not conform to the template structure, or there are unresolved decision items, the review process does not start and the status stays `create-plan-in-progress`.

**Do not treat file review checkboxes as a plan review gate**: the checkboxes in `Files to Change` indicate whether the developer has manually reviewed those file listings; this can be done before or after the agent plan review. The plan review only judges whether the file listing itself is complete, whether paths are real, and whether responsibilities are reasonable. Unchecked boxes must not cause a `Not Ready`, `Needs Refinement`, or any finding. If a separate rule during the execution phase requires checkboxes to be checked, the execution tool enforces that itself — the plan reviewer must not enforce it on the execution gate's behalf.

## Clean Architecture Principles

The following principles are the benchmark for evaluating architectural soundness when reviewing a plan. Module design, responsibility assignment, and API design in the plan should conform to these principles.

The cost of fixing problems at the planning stage is far lower than at the coding stage. One redundant abstraction in the plan becomes an interface, implementation class, and registration code scattered across multiple files in the code — large change surface, hard to revert. Therefore, vigilance against over-engineering and duplication is essential during review.

### Separation of Concerns

Each layer only does what it should:

- **Service layer**: carries all business logic; the core of the code. No dependency on UI frameworks, rendering engines, or platform APIs. Must be independently unit-testable.
- **ViewModel layer**: primarily manages view state, user interaction orchestration, and state transitions; should not be the primary carrier of business logic. Unless a piece of logic is inherently tied to UI/page workflow, it should preferably be pushed down to the Service layer or a dedicated module.
- **View layer**: only responsible for UI rendering and forwarding user interaction events. Controlling show/hide based on state is the View's job, but computing the state itself is not.
- **Renderer / Infrastructure layer**: provides platform capabilities (rendering, networking, storage, etc.). Decoupled from business logic through interface abstractions.

These boundary constraints apply to **production code responsibilities**, not a requirement that tests must also only test "their own layer." For example, ViewModel unit tests may use real Service fixtures for small end-to-end verification; the key is that production code must not stuff reusable business logic into the ViewModel.

Communication between layers happens through explicitly defined interfaces or data flows (e.g., StateFlow), not through direct calls to internal implementations.

During review, proactively ask this question: if this new logic needs to be reused by a second caller in the future (e.g., another UI location, an automation entry point, an agent/MCP interface), should it still live in the ViewModel? If the answer is no, it more likely belongs in the Service layer or a shared module, not the ViewModel.

### Single Responsibility

One function does one thing. One file centers on one theme. One module owns one responsibility.

If a function/file/module's responsibility cannot be described in one sentence, it needs to be split. If a new class in the plan simultaneously handles data persistence and UI state management, that indicates a problem with the responsibility assignment.

### Minimal Public API

A module's external-facing API should be as small as possible. Only methods and types that genuinely need to be called externally are marked `public`; everything else is `internal` or `private`.

A public API is a contract between modules — once published, it is hard to retract. When reviewing a plan, check whether all new public APIs are necessary and whether any could be `internal`.

### Dependency Direction

Dependencies can only flow from higher layers to lower layers, from concrete to abstract:

- UI → Service → Models (valid)
- Service → UI (violation: business logic should not know about the UI)
- Models → Service (violation: data models should not depend on business logic)

Higher-level modules define interfaces; lower-level modules implement them. This is the core of the Dependency Inversion Principle.

### Appropriate Use of Dependency Injection

Not all dependencies need to be injected through a DI framework. DI is appropriate when the same instance needs to be shared across multiple unrelated locations (e.g., AppCoordinator needs to be available in both the home screen and the editor).

If a dependency is only used in one place, create it directly — no need for DI. Over-using DI obscures object ownership and lifetime, increasing cognitive load.

### Interface Segregation

Do not create large, catch-all interfaces. If an interface has 10 methods but most callers only use 2, the interface needs to be split. Each interface should serve a specific use scenario, not try to cover all possibilities.

### Communicate via Data Flows, Don't Expose Internal State

Modules communicate through shared data types and reactive data flows (StateFlow), not by directly calling each other's internal methods. State producers only emit state; consumers decide how to respond.

What is exposed to other modules should be a read-only interface or data snapshot, not a mutable reference. If a consumer only needs to read viewport information, give it a `ViewportProvider` (read-only interface), not a `ViewportManager` (mutable implementation). If the UI layer only needs to know the type of the selected element, give it a `SelectedElementType` enum, not a full `CanvasElement` object.

### Open for Extension, Closed for Modification

New features should be implemented by extending existing structures (adding classes, adding extension functions, implementing existing interfaces), not by modifying stable existing code. If a plan needs to modify a core model's sealed interface definition or change an existing method signature in order to add a new feature, scrutinize whether that modification is truly necessary.

### KISS — Keep It Simple

The simplest solution is the best solution. Every abstraction layer, configuration item, or indirection introduced in a plan should have a clear justification. If the current need only requires a function, do not design an interface + implementation class + factory. If a `when` branch solves the problem, do not introduce the strategy pattern.

During review, ask: if this abstraction/layer of indirection were removed, would the feature still be correct? If yes, that abstraction should not exist.

Be especially strict about over-engineering through "componentization" and "data structure modeling." Do not automatically create `Locator`, `Descriptor`, `Context`, `Result`, sealed wrapper, or new model files just because a concept sounds like a domain noun. First ask what data the caller actually needs:

- If the caller only needs `(elementId, contentId)`, do not design `EmbeddedContentLocator`.
- If a hit-test has only one caller and that caller only needs `contentId`, do not make `getXAt()` return a complex hit structure containing kind, bounds, index, and localPoint.
- If a field only exists to save the caller from doing one scan of existing data, and the scan range is small with sufficient existing invariants, prefer returning the minimal data and letting the caller parse it where needed.
- If a public/shared data class only wraps an existing domain type with 1–2 extra fields (e.g., `FooWithBounds(content, width, height)`), do not introduce it by default. First determine whether those fields are true invariants of that domain type: if yes, consider adding them to the existing type or providing derived functions on the existing type; if not, the caller should compute or pass them at the point of need — do not create an external wrapper layer.
- Exception: private/internal pipeline carriers can legitimately exist — for example, when multiple intermediate values need to be passed together to the next stage in a worker → drain, multi-stage parser, or batch validation flow. The prerequisite is that they express a real stage boundary, do not leak into the module's external API, and are not used as future extension points.
- If a new type has only one producer and one consumer, and has no stable cross-module contract value, prefer using existing types or simple return values.

Plan review should require new abstractions to justify their necessity, rather than requiring simple solutions to prove why they are sufficient. Complex return objects, dedicated locators, component protocols, and helper interfaces should default to "don't add it" unless they genuinely reduce current complexity, protect real invariants, or already have multiple independent callers needing the same contract.

### DRY — Don't Repeat Yourself

The same logic should exist in only one place. If a plan has similar validation logic, similar state checks, or similar data transformations in two files, extract them into a shared function. Duplicated code means remembering to sync all copies when fixing a bug in the future — and people always forget.

But be careful to distinguish genuine duplication from surface similarity. Two pieces of code that look alike now doesn't mean they are the same thing semantically. If their reasons for change differ, forcibly merging them creates coupling.

### YAGNI — You Aren't Gonna Need It

Do not write code for imagined future needs. If the current requirement is "lock elements so they cannot be moved," do not simultaneously design a "configurable locking strategy framework." When a plan contains phrasing like "might be needed in the future," "reserving an extension point," or "paving the way for later features," scrutinize whether those extensions have confirmed requirement backing. Those without backing should be cut.

Pre-designed abstractions are almost always wrong, because before the real need appears, you cannot know what the right abstraction should look like.

YAGNI also applies to new wrapper data types: do not create `ImportedX`, `ResolvedX`, or `XResult` types that only wrap existing types "to make the return value look more complete." If extra fields are necessary and express stable domain facts, they should preferably be merged into existing domain types or become explicit derived APIs; if they are only temporary computation results for the current call site, do not put them in a shared API. Private/internal intermediate result types are not cut-and-dried on this rule, but confirm during review that they only serve the current flow and have not expanded the public contract.

### Minimal Change Surface

A plan should implement requirements with the minimum number of file changes and minimum lines of code. The larger the change surface, the higher the probability of introducing bugs, and the higher the cost of review and testing.

If a feature can be implemented by modifying 2 files but the plan touches 6 files, scrutinize whether the extra 4 files are truly necessary. Common sources of change surface bloat: unnecessary refactoring bundled with the feature change, excessive type abstractions, scattering logic across many locations that could be cohesive in one place.

### Follow Existing Patterns

Patterns already in the codebase are the best reference. New code should maintain consistent style, structure, and conventions with adjacent code. If existing context menu buttons are all implemented via `_tap_context_menu_button`, new buttons should use the same approach. If existing HistoryCommands all follow the execute/undo symmetric structure, new commands should do the same.

The bar for inventing a new pattern should be high: only when the existing pattern genuinely cannot meet the need should a new approach be introduced. When a plan introduces a new pattern, it must explain why the existing pattern is insufficient.

### Factory Pattern Exception

`*Factory.kt` / `*Factory.swift` files are exempt from DRY, YAGNI, KISS, and minimal change surface constraints. See `guides/factory-pattern-guide.md`.

## Guardrails

1. **Must read the code before concluding** — do not judge accuracy based solely on the plan document's description. If the plan says "method A accepts parameter X," Read the source file to confirm.
2. **Don't guess** — if a fact cannot be confirmed (whether a method exists, whether a parameter type is correct), Read the source file to confirm.

## Blocking vs. Auto-Fix

When a problem is found, first ask: **"Would this problem cause the executing agent to make an irreversible architectural error, or would it cause a suboptimal implementation choice that tests could catch?"**

- **Architectural error or poor decision** → Needs Refinement or Abandon
- **Implementation detail** → fix directly in the plan and pass
- **Throughput priority**: given no architectural risk, prefer auto-fixing and passing; avoid turning plan-review into a high-rejection-rate gate

### Examples of Direct Fix and Pass

- An ellipsis obscures a specific formula or condition → fill in a reasonable implementation detail
- A code fragment's control flow is ambiguous (e.g., return semantics inside a lambda are unclear) → rewrite with unambiguous syntax
- The error-handling semantics of a batch operation are unclear → choose a reasonable handling approach and write it into the plan
- A method's described visibility doesn't match its actual use but does not cross module boundaries → correct the visibility

### Examples of Must Block

- UI layer directly references editor-models types, violating an archived module dependency constraint
- Service layer calls ViewModel; dependency direction is reversed
- The plan depends on a non-existent public API, and adding that API requires cross-module changes
- The new feature requires modifying another module's sealed interface, but that module is not in the plan
- `Archived Decisions` chose an approach that violates Clean Architecture principles (e.g., placing business logic in the ViewModel) when an obviously more reasonable alternative exists
- `Archived Decisions` introduce a new abstraction that duplicates an existing mechanism in the codebase

## What Causes "Needs Refinement"

### 1. Ambiguity

A plan is a specification. When the executing agent encounters uncertainty, it has only two options: guess or stop. Both waste resources.

Common forms of ambiguity:

- **Ellipsis in code fragments**: `...` or `// existing logic` is not inherently a problem — code fragments in the plan are illustrations of intent, not templates to copy verbatim. The problem arises when the omitted portion involves an **architecture-level decision** (which layer to insert new logic into, which interface to call, which data flow to follow) and the plan does not explain it elsewhere. If the architectural intent is clearly expressed in other sections and the ellipsis only omits implementation details the agent can infer on its own, it is completely acceptable.
- **Vague Implementation Steps**: a step only describes the goal ("add lock check") without specifying which method, which location, or what condition
- **Undefined components**: a step references a component, but `Files to Change` has no structural definition or code fragment for that component
- **Unspecified interactions**: new component A calls component B, but B's interface is not defined; data originates in module A but there is no description of how it gets to module C

### 2. Omissions

- **Earlier-mentioned features must appear in Files and Steps**: if the plan mentions a feature, behavior, state, component, service, API, test target, or user-visible capability in any section before `Files to Change` and `Implementation Steps`, and it is not explicitly marked as "future work," "this plan won't do it," "out of scope," or equivalent, the reviewer must require it to also appear in:
  - `Files to Change`: listing the new/modified files that carry the capability and describing each file's responsibility
  - `Implementation Steps`: listing the concrete steps to implement the capability, describing which layer the data/control flow lands in
  Otherwise this is treated as an under-specified omission. "The goal section mentioned it; the executing agent will fill it in" is not acceptable; capabilities that are in-scope must be picked up by the execution checklist to prevent only scaffolding or placeholders being delivered.
- A file is referenced in `Implementation Steps` but not listed in `Files to Change`
- A new public API has no corresponding test in `Test Plan`
- The plan assumes a method or class exists but neither lists it in `References` nor confirms it in a code fragment
- The `Size` estimate is obviously inconsistent with the actual file count and change volume

#### Unit Test Coverage

Plan review focuses on **behavior scenario coverage**, not line coverage numbers. `scripts/check_unit_test_coverage.py` checks coverage thresholds; reviewers must not turn plan review into a textual check of "does this say 95%/100% coverage." The test plan must demonstrate that the main use path, alternative paths, boundary conditions, and failure paths of new behavior all have explicit tests.

- Each new public method in the Service layer or ViewModel layer must have at least one corresponding unit test case in the test plan
- Each new user-visible capability or core service capability must list scenario tests based on real use cases, not just a single happy path. For example, hit-testing must cover hitting a target, hitting a blank area, outside the boundary, overlapping/multiple targets, coordinate transforms, aligned/offset, rotated/scaled, and other scenarios that affect the result
- The test plan should cover all branches where Archived Decisions change behavior: if Strict vs Nearest was chosen, if scope-locked vs cross-layer multi-select was chosen, if a hard-cut signature was chosen, if carrier-aware write-back was chosen, there must be corresponding tests proving these decisions land
- Boundary conditions should come from real risks first, not mechanical enumeration. Common high-value boundaries: empty collection, single element, multiple elements of the same type, first/last position, out-of-bounds input, ID mismatch, duplicate IDs, non-existent target, coordinates at the visual edge, pending edit/undo/redo mid state-transition
- If logic depends on geometry, time, ordering, serialization, or cross-module state, the test plan must cover the representative scenarios in those dimensions that change the result; it cannot only test the simplest coordinates, default time, default order, or round-trip happy path
- For state-transition logic (A → B → C), each transition must have an independent test; testing only the final state is insufficient
- Explicit conditional branches in code (e.g., `if (isLocked) return`) must have test cases covering that branch
- If the plan adds interface abstractions for mock injection, the test plan must reflect the use of those mocks
- If the plan adds unit tests for a ViewModel, it must specify:
  - What the default dispatcher / test harness is
  - Whether it reuses patterns from existing stable test files in the same module
  - Whether it uses real Service fixtures or mocks/fakes
  - Which assertions belong to the ViewModel's UI-facing state and which are intentionally kept as cross-layer result validations
- If new ViewModel tests in the plan need `advanceTimeBy()`, animation completion, or delayed state transitions, the plan should explicitly state that these tests will be isolated, rather than casually rewriting the shared harness of an entire existing test file
- For more complete ViewModel / Service unit testing conventions, see `unit-test/docs/how_to_write_stable_unit_test.md`; during review, check whether the plan has added that document to `References`

### 3. Internal Conflicts

Conflicts most often appear when the developer changes requirements or adds constraints during plan iteration:

- `Archived Decisions` chose approach A, but code fragments are still written in approach B
- A file was deleted in `Files to Change`, but `Implementation Steps` still references it
- New requirements are reflected in some sections but other sections were not updated to match
- The operations described in `Implementation Steps` contradict the code fragments in `Files to Change`

### 4. Code Inconsistent with the Actual Codebase

- Class names, method signatures, and parameter types described in the plan do not match the actual source files
- The insertion point for a code fragment does not exist in the source file (context code has changed)
- Dependencies (classes, interfaces, functions) referenced in code fragments do not exist in the codebase

### 5. `Archived Decisions` Quality Issues

When `Archived Decisions` has a better alternative, mark it as "Needs Refinement" and present alternatives to the developer:

- `Archived Decisions` chose an approach that works but has an obviously simpler alternative (KISS)
- `Archived Decisions` introduce abstractions or extension points not currently needed (YAGNI)
- `Archived Decisions`' approach is inconsistent with the existing pattern in the codebase for solving similar problems, without explanation
- `Archived Decisions` place logic in a suboptimal architectural layer (e.g., reusable business logic in ViewModel instead of Service), but not severe enough for Abandon
- The plan contains an implicit decision (an architectural choice was quietly made without appearing in `Archived Decisions`) — require the developer to make it explicit and add it to `Archived Decisions`
- `Archived Decisions` introduce an obscure third-party library when a platform-native solution or mainstream library would suffice (violates the "Most Popular" pillar)
- `Archived Decisions` chose an approach officially superseded by the platform (e.g., CocoaPods instead of SPM, RxSwift instead of Combine/async-await, RxJava instead of Kotlin Coroutines/Flow) — these are immediately judged as Abandon, not "Needs Refinement"
- `Archived Decisions` introduce a technology inconsistent with the codebase's existing tech stack (e.g., project uses Coroutines, plan introduces RxJava), but not in the zero-tolerance category above

When presenting `Archived Decisions` quality issues to the developer, you must:
- Reference the specific decision item and choice from `Archived Decisions`
- Explain why the current choice is problematic (citing specific principles from this guide)
- Propose a specific alternative with a pros/cons analysis
- Read actual code from the codebase to support the argument, rather than relying on speculation alone

## What Causes "Abandon"

Abandon means the plan's foundation is broken and cannot be salvaged by local patches. The following conditions, any one of which is true, warrants Abandon:

### 1. Multi-Purpose Plan

The plan tries to do multiple things simultaneously. For example: first refactor the module structure, then add new features on top of the refactored foundation. That is two plans disguised as one. Refactoring and new features have their own decision spaces, risks, and validation criteria — mixing them means neither can be cleanly reviewed or executed.

### 2. Breaks Existing Module Boundaries or Architectural Decisions

The plan breaks existing module boundaries or violates architectural decisions archived in prior plans in order to implement the new feature. Module responsibilities and boundaries should remain relatively stable unless a dedicated refactoring plan changes them. New features must be implemented within the existing architectural constraints, not by bypassing or breaking those constraints for convenience.

Example: `editor-service` has had its dependency on `editor-renderer` removed through `plans/editor-module-split.md`. If a new feature plan re-introduces the `editor-service → editor-renderer` dependency, that plan should be Abandoned.

### 3. Reinventing the Wheel

A service or mechanism already in the codebase can meet the need, but the plan creates a new parallel mechanism to do the same thing. This results in multiple approaches to the same problem in the codebase, increasing maintenance cost and creating confusion.

Example: `SessionManager` already manages per-session state. If a plan creates an independent `LockStateManager` to manage lock state in parallel (rather than reusing `SessionManager`), that plan should be Abandoned.

### 4. Introduces Circular Dependencies

The plan's module design results in a circular dependency A → B → A. This is not a problem fixable by moving a few methods — it means the entire responsibility decomposition is wrong.

### 5. Business Logic in the Wrong Layer

The plan places business logic in the wrong architectural layer. We follow Clean Architecture: the Service layer carries business logic; the ViewModel layer should primarily hold view state and workflow orchestration; the View layer is responsible only for rendering and event forwarding. The View/ViewModel layer controlling UI visibility based on state (e.g., show/hide a button) is normal, but if the plan stuffs logic that belongs in the Service layer or other dedicated modules into the UI or ViewModel, the architectural design has a fundamental problem.

Example: font measurement logic belongs in `FontManager` inside `editor-renderer`. If a plan writes font measurement logic in a UI component inside `editor-phone-ui`, that plan should be Abandoned.

Another common anti-pattern: the core rules of a feature, bulk data transformations, geometric computations, or reusable query logic that could be exposed as a general Service API for multiple callers are instead written as private methods of a ViewModel, simply because the current button happens to use them. Plans like this are runnable in the short term but cause the ViewModel to continuously bloat and block future reuse.

### 6. Technology Selection Uses a Deprecated Approach

`Archived Decisions` chose a technology that has been officially deprecated by the platform or clearly abandoned by the community — zero tolerance, immediate Abandon:

- **Package managers**: CocoaPods (SPM should be used instead)
- **Reactive frameworks**: RxSwift, ReactiveSwift (iOS should use Combine or async/await); RxJava (Android should use Kotlin Coroutines / Flow)
- Any API or framework officially deprecated by the platform

These problems should not wait until the code review to be discovered — intercepting them at the planning stage has the lowest cost.

### 7. `Archived Decisions` Cause Architectural Damage

`Archived Decisions` themselves violate architectural principles, and the scope of impact is too large to fix with local adjustments. Unlike conditions 1–5 above, the problem here is not how the plan is implemented, but the direction the developer chose in `Archived Decisions` itself is wrong.

Examples:
- `Archived Decisions` chose an approach that requires breaking existing module boundaries to implement, while alternatives exist that don't break boundaries
- `Archived Decisions` chose "create a new state management mechanism" instead of reusing the existing `SessionManager`, resulting in dual-track state management
- `Archived Decisions` chose to implement complex business rules in the View layer, while those rules clearly belong in the Service layer

## Output Specification for "Needs Refinement"

For each issue found, present to the developer:

1. **What the problem is** — where in the plan it is, what specifically is wrong
2. **What the impact is** — what will happen when the agent executes if this is not resolved
3. **Options** — provide specific fix options for the developer to choose from

After the developer makes a choice:
1. Record the choice in the plan's `Archived Decisions`
2. Update all affected parts of the plan (code fragments, Implementation Steps, Test Plan, etc.) to ensure consistency throughout
3. Re-check consistency to confirm that the updates introduce no new contradictions
