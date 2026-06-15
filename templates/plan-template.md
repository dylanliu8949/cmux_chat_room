**Author**: [GitHub username]
**Size**: [XS|S|M|L|XL|XXL|XXXL]
**base commit hash**: [***********]  
**branch name**: [branch name]  
**Created**: [YYYY-MM-DD]
**Status**: [create-plan-in-progress|create-plan-complete|review-plan-in-progress|review-plan-complete|plan-execution-in-progress|plan-execution-complete|manual-test-in-progress|manual-test-complete|automated-ui-test-in-progress|automated-ui-test-complete|code-review-in-progress|code-review-complete|merge-complete|abandoned]
**Prerequisite tasks (if applicable)**: [tasks that must be completed first]
**Follow-up tasks (if applicable)**: [work that depends on this task]

> **Size guide**:
> - `XS`: extra-small task (lines of code changed < 50, files involved < 3, new abstractions 0)
> - `S`: small task (lines of code changed 50-200, files involved 3-5, new abstractions 0-1)
> - `M`: medium task (lines of code changed 200-500, files involved 5-10, new abstractions 1-3)
> - `L`: large task (lines of code changed 500-1000, files involved 10-20, new abstractions 3-5)
> - `XL`: extra-large task (lines of code changed > 1000, files involved > 20, new abstractions > 5)
> - `XXL`: very-large task (lines of code changed > 3000, files involved > 50, architectural changes spanning multiple modules) — suited to scenarios driven by an AI Agent with full unit-test and UI-test coverage
> - `XXXL`: gigantic task (lines of code changed > 5000, files involved > 100, system-level architectural refactor) — only for yolo scenarios executed end-to-end by an AI Agent with a full automated test suite as a backstop
>
> **Mechanical-change downgrade rule**:
> The size thresholds above measure **design/review complexity**, not diff lines or file count. If the vast majority of changes are purely mechanical — each one following the same mechanically verifiable rule, involving no business logic or design judgment — the size should be **downgraded by at least one grade, and substantially more when warranted** (e.g. a method rename across 100 files may actually be only XS/S complexity, because the reviewer only needs to sample 3-5 spots to confirm the replacement rule is consistent, without thinking through each file).
>
> Typical mechanical changes:
> - Renaming a public method / class / field, causing N call sites across the repo to follow
> - Changing the signature of a widely used function (adding/removing parameters, changing return type), with all call sites following mechanically
> - Module split / reorganization, with many file moves + import path adjustments
> - Bulk-fixing repo-wide violations triggered by a new lint rule (see PR #332)
> - Bulk API replacement per codemod rule (old API → new API migration)
> - Unifying import order / paths / aliases
> - Directory reorganization, bulk file renaming per convention
> - Bulk-adding type annotations to existing unannotated code
>
> Judgment criteria:
> - Does the reviewer need to think through each file? If they only need to spot-check "whether everything follows the same rule", it is a mechanical change
> - Parts that still count at their original complexity: the "source" that triggers the mechanical change itself (the new lint rule, the codemod script, the new API interface, the method declaration with the new signature) does not participate in the downgrade

> **Status guide**:
> The status value is a `<phase>-<phase-state>` combination: the 7 phases advance linearly in the order of the table below; the first 6 phases each have an `in-progress` and a `complete` phase-state, and the 7th phase `merge` has only `merge-complete` (merging is an instantaneous operation with no "in-progress" intermediate state — the next state after `code-review-complete` is `merge-complete`). The full enumeration is 14 values: `<phase>-in-progress` / `<phase>-complete` × 6 + `merge-complete` + the special terminal state `abandoned` (can be written manually at any phase, indicating the plan is abandoned). This field is a machine-readable workflow gate; do not introduce values outside this list.
>
> | # | phase | meaning | when `in-progress` is written | when `complete` is written |
> |---|-------|---------|-------------------------------|----------------------------|
> | 1 | `create-plan` | plan document authoring | `/create-plan` starts | saved to disk awaiting review |
> | 2 | `review-plan` | plan review | `/review-plan` starts | review passes (the minimum bar for `/execute-plan`) |
> | 3 | `plan-execution` | code generation | `/execute-plan` starts | all steps complete |
> | 4 | `manual-test` | human manual testing | developer manually | developer manually |
> | 5 | `automated-ui-test` | automated UI testing | developer / script | developer / script |
> | 6 | `code-review` | PR code review | PR opened | review passes |
> | 7 | `merge` | merge to main | — (no in-progress) | merge complete; usually written by the next `/pr` after the agent confirms the PR is merged (terminal) |
>
> **Gate rules**:
> - `/execute-plan` is allowed only when the status is `review-plan-complete` or `plan-execution-in-progress`; all other states are rejected
> - `pr-checklist.yml` validation: the plan document referenced by the PR must be a file newly added in this PR's diff, or a file that already exists on main with a status ≤ `plan-execution-in-progress`; any main-side status at or after `plan-execution-complete` is considered used and must not be reused

# [Task title]

## Current State Analysis
Briefly summarize the existing implementation and constraints relevant to the task.

> **Important**:
> - Include only content directly relevant to the task
> - Explain the key points of the current implementation
> - List the technical constraints that may affect the implementation
> - Use the mindpilot MCP to draw a diagram describing how the relevant components fit together

## References
List all documents, references, and integration guides needed to implement the task, including library documentation, README files of existing services, and integration docs for third-party SDKs.

> **Important**:
> - Use **context7** to fetch documentation and references
> - If **context7** has no relevant documentation, you must provide documentation links in this section
> - If the task requires using an existing service, include the path to that service's README file
> - If the task involves a third-party SDK, include the following links:
>   - SDK integration documentation
>   - documentation on how to enable XX feature
> - Must include `guides/encyclopedia.md`, and use it first when creating a plan to find relevant guides and documentation
> - Must include `guides/naming-guide.md` to ensure newly added modules, files, classes, and functions follow project naming conventions
> - If the plan includes unit tests, must include `unit-test/docs/how_to_write_stable_unit_test.md`
> - If the plan involves log output or runtime assertion checks, must include `shared-services/logger-service/docs/how_to.md`
> - If this task is based on another task, or future tasks depend on this task, include the paths to the relevant task plan documents
> - If not all relevant documents can be found or provided, the AI should stop plan generation and notify the developer

## Decisions Needed
List all unresolved choices and questions, providing recommended options. Do not execute the plan until the developer resolves these items.

**Current Plan Completeness**: [leave blank, update after the developer decides]

> **Note**: When initially generating the plan, this completeness should be left blank. As the developer makes more decisions, the AI should update this percentage.

> **Important**:
> - The developer may execute the plan only when plan completeness reaches or exceeds 95% (the AI is 95%+ confident it can complete the task)
> - Any item that is unclear, missing, or could be implemented with a different solution should be listed in this section
> - The AI should not guess; it should always ask for relevant information before executing the plan
> - If the AI cannot infer the available options, it may ask an open-ended question
> - Each decision item can have multiple options (not limited to two); list all viable choices as appropriate
> - Each option's description should list its pros and cons
> - After making major directional decisions, the AI should continue asking follow-up questions and update this section
> - After the developer makes a decision, this completeness percentage should be updated.

<!-- Example: BEGIN -->
1. **Decision item 1**
   - Option A: [short description]
     - Pros: [list of pros]
     - Cons: [list of cons]
   - Option B: [short description]
     - Pros: [list of pros]
     - Cons: [list of cons]
   - Option C: [short description]
     - Pros: [list of pros]
     - Cons: [list of cons]
   - **Recommendation**: Option A (reason for recommendation)

2. **Decision item 2**
   - Option A: [short description]
     - Pros: [list of pros]
     - Cons: [list of cons]
   - Option B: [short description]
     - Pros: [list of pros]
     - Cons: [list of cons]
   - **Recommendation**: Option B (reason for recommendation)

3. **Decision item 3**
   - Option A: [short description]
     - Pros: [list of pros]
     - Cons: [list of cons]
   - Option B: [short description]
     - Pros: [list of pros]
     - Cons: [list of cons]
   - Option C: [short description]
     - Pros: [list of pros]
     - Cons: [list of cons]
   - Option D: [short description]
     - Pros: [list of pros]
     - Cons: [list of cons]
   - **Recommendation**: Option C (reason for recommendation)

4. **Decision item 4 (open-ended question example)**
   - **Question**: [if available options cannot be inferred, ask an open-ended question, e.g.: what data structure should be used to store this data?]
<!-- Example: END -->

## Archived Decisions
Record decisions made during implementation, including the options offered to the user (short descriptions) and the user's choice.

<!-- Example: BEGIN -->
1. **Decision item 1**
   - **Options**: Option A (short description), Option B (short description), Option C (short description)
   - **Chosen**: Option A

2. **Decision item 2**
   - **Options**: Option A (short description), Option B (short description)
   - **Chosen**: Option B

3. **Decision item 4 (open-ended question example)**
   - **Question**: What data structure should be used to store this data?
   - **Chosen**: Use a HashMap (full description: fast lookup and update operations are needed, and a HashMap provides O(1) average time complexity)
<!-- Example: END -->

## Feature Flags / Experiments (if applicable)

If the task involves UI changes or experiments, define the feature flags and experiment configuration in this section.

> **Important**:
> - It is recommended that all UI changes use feature flags for A/B testing
> - Must define the experiment name and all flag names
> - Must explain what each flag toggles/changes
> - One experiment per plan document only

<!-- Example: BEGIN -->
**Experiment name**: [experiment name]

- **flag name**: [flag name]
  - **What it toggles**: [what changes when this flag is enabled/disabled]

- **flag name**: [flag name]
  - **What it toggles**: [what changes when this flag is enabled/disabled]
<!-- Example: END -->

## Files to Change
List all files that will be added or modified, providing high-level conceptual code snippets and key implementation details.

> **Important**:
> - The developer must review all newly added and modified files
> - When introducing a new class, file, function, or structure, include a concise **high-level conceptual code snippet**:
> - Show the high-level concept, including public types, method signatures, and structural information
> - **Do not include import statements in the code snippets** — imports are implementation details and do not convey design intent
> - For key implementation details, you may add code snippets, but a full implementation is not needed
> - In addition to code snippets, you may also use comments in the code to explain what needs to be added or modified and where
> - Use the mindpilot MCP to draw a diagram describing how the new components and services fit into the existing architecture
> - This section should be exhaustive and include all files that will be added or modified.
> - Should include file paths
> - **Note**: The developer should check the corresponding checkbox as they review each file
> - **Exception**: The following types of files do not need to be listed in this section and may be modified directly:
>   - Gradle configuration files (e.g. `build.gradle.kts`, `settings.gradle.kts`, `gradle.properties`, etc.)
>   - Swift package management files (e.g. `Package.swift`)
>   - Project configuration files (e.g. `.xcodeproj`, `.xcworkspace`, `Info.plist`, `.idea` config, etc.)
>   - Documentation files (e.g. `.md`, `.txt`, `.rst`, etc.)
>   - Python package marker files (`__init__.py`)
>   - Files involving only import statement changes (e.g. adding/modifying import lines)

<!-- Example: BEGIN -->
- [ ] **New File**: [file path]
  ```swift
  class NewClass {
      func publicMethod(param: Type) -> ReturnType
  }
  ```

- [ ] **Changed File**: [file path]
  ```swift
  class ExistingClass {
      func newMethod(param: Type) -> ReturnType
  }
  ```
<!-- Example: END -->

## Analytics Events (if applicable)
If the task involves analytics events, define all analytics event names/event codes and event properties in this section.

> **Important**:
> - Must track all user actions, e.g. button clicks
> - For tasks (such as login, download, page load, save to album, etc.), must track both the action that starts the task and the task-completion event
> - Must define the names or event codes of all analytics events
> - Must define all properties of each event and their types
> - Must specify the file path where each event should be added

<!-- Example: BEGIN -->
- **Event name/code**: [event name or code]
  - **File path**: [file path where this event should be added]
  - **Trigger condition**: [when this event is triggered]
  - **Event properties**:
    - `property1` (String): [property description]
    - `property2` (Int): [property description]
    - `property3` (Boolean): [property description]

- **Event name/code**: [event name or code]
  - **File path**: [file path where this event should be added]
  - **Trigger condition**: [when this event is triggered]
  - **Event properties**:
    - `property1` (String): [property description]
<!-- Example: END -->

## Error Tracking (if applicable)

If the task involves runtime operations that may fail (network, IO, permissions, user input validation, etc.), define the error logging configuration in this section. **Errors that may be expected to occur** (not bugs); the goal is observation and reporting, not terminating the process. **Invariant violations that should never occur** go in the "Assertion Checks" section below, not here.

> **Important**:
> - Output all errors using `Logger.logError(tag, message)`, see `shared-services/logger-service/docs/how_to.md`
> - Severity levels map to Logger's `LogLevel`: `ERROR` (failure, needs attention) or `WARNING` (recoverable abnormal situation)
> - For operations that may fail for multiple reasons (e.g. a download may fail due to network, permissions, insufficient storage, etc.), an error code must be defined to distinguish error types
> - Each error must include an error description

<!-- Example: BEGIN -->
### Error logs (Logger.logError)

Errors that may be expected to occur — network timeout, file not found, insufficient permissions, etc.

- **Error name**: [error name]
  - **Level**: `ERROR` or `WARNING`
  - **tag**: [Logger tag, e.g. "ImageLoader", "PhotoService"]
  - **Error properties**:
    - `errorDescription` (String): [error description]
    - `property1` (String): [other property description]

- **Error name**: [error name] (may fail for multiple reasons)
  - **Level**: `ERROR`
  - **tag**: [Logger tag]
  - **Error codes**:
    - `ERROR_CODE_1`: [error type 1 description, e.g.: network connection failed]
    - `ERROR_CODE_2`: [error type 2 description, e.g.: insufficient permissions]
  - **Error properties**:
    - `errorCode` (String): [error code]
    - `errorDescription` (String): [error description]
<!-- Example: END -->

## Assertion Checks (if applicable)

If the task involves state violations that **should never occur** (illegal state transitions, broken invariants, unreachable branches), declare assertions in this section. An assertion is not error handling — it is an "early catcher for code bugs". Failures that may be expected to occur go in the "Error Tracking" section above.

> **Important**:
> - Use `Assert.that(condition) { message }` / `Assert.notNull(value) { message }` / `Assert.unreachable() { message }`, see `shared-services/assertion/docs/how_to.md`
> - **debug build**: throws `AssertionError` to terminate the process (aligned with iOS Swift `assert(_:_:)` / Kotlin `assert(-ea)`)
> - **release build**: degrades to `Logger.logError` outputting a log with the `[ASSERT_FAILED]` prefix, then returns the original value and continues
> - Both paths first call `Logger.logError`, ensuring the message text is searchable in iOS oslog / Android logcat
> - Unit tests use `assertFailsWith<AssertionError>` to verify invariants
> - When to use an assertion: "if this fails here, it means upstream code has a bug". When to use an error log: "this may fail here, but it is not a bug; it needs reporting or recovery"

<!-- Example: BEGIN -->
### Assertions (Assert.that / Assert.notNull / Assert.unreachable)

- `Assert.that(condition, tag) { message }` — returns `Boolean`, triggers when the condition is false
- `Assert.notNull(value, tag) { message }` — returns `T?`, triggers when value is null
- `Assert.unreachable(tag) { message }: Nothing` — for scenarios where a branch is never reachable, throws in both debug/release

```kotlin
// Boolean condition assertion: the return value can be used directly for early return
if (!Assert.that(elements.isNotEmpty(), "EditorService") { "duplicateSelectedElements: empty selection" }) return

// Non-null assertion: the return value can be used in a ?: chain
val element = Assert.notNull(canvasState.getElementById(elementId), "EditorService") {
    "enterTextEditMode: elementId=$elementId not found"
} ?: return

// Unreachable branch
when (mode) {
    Mode.A -> handleA()
    Mode.B -> handleB()
    // If a new Mode.C is added but forgotten here, the debug build crashes immediately
    else -> Assert.unreachable("EditorService") { "unhandled mode=$mode" }
}
```

- **Assertion**: [assertion description]
  - **Condition**: [which invariant being violated triggers it]
  - **Message**: `[specific message, no need to include the [ASSERT_FAILED] prefix, Assert.* adds it automatically]`
  - **Location**: [in which file/function it is checked]
<!-- Example: END -->

## Implementation Steps
Break the plan down into clear, ordered, reviewable steps so the developer can approve and commit incrementally.

> **Important**:
> - When the plan size is L or XL, phases must be used; when the plan size is XS, S, or M, only steps are used; XXL and XXXL must use multiple phases, each phase corresponding to a separate PR, and the full test suite must be run at the end of each phase
> - A phase should be its own PR
> - A step can be a single commit within a PR
> - **Automation first**: AI agents can execute shell scripts and command-line tools (such as `ui-test/scripts/run_test.sh`, `pytest`, `gradle test`, etc.), so running scripts, executing tests, compiling code, etc. **should never be marked as manual steps**. Only steps that genuinely require physical human action should be marked as **(manual action required)**, for example: logging into a third-party service in a browser, configuring settings in a web console or verifying data arrival, manually importing a package in Xcode, real physical device interaction, UI acceptance requiring human visual judgment, etc.
> - Manual action steps must be clear and detailed, e.g.: which website to visit, which button to click, what to add, what option to find in which menu, etc.
> - It is recommended (not required) that the developer fix all compile errors, run unit tests, and commit and push (git commit, git push) after each step is complete.
> - **Note**: The AI agent should check the corresponding checkbox as it completes each step (except for steps marked **(manual action required)**, which are completed and checked by the developer)
> - Plan execution is only responsible for the implementation, testing, and local verification required by the plan; the global PR wrap-up checks (coverage, unit tests, lint, architecture doc sync, commit/push, PR description) are handled uniformly by `/pr`.

<!-- Example: BEGIN -->
**Phase 1**: [phase name] (only applicable to L or XL size plans)
- [ ] **Step 1**: [step name]
  - Describe the operation to perform
  - Expected result

- [ ] **Step 2**: [step name]
  - Describe the operation to perform
  - Expected result

- [ ] **Step 3**: [step name] **(manual action required)**
  - Describe the content that requires manual action (e.g.: configure in a browser, import a package in Xcode, real device interaction, etc.)
  - Expected result

- [ ] **Step N**: [step name]
  - Describe the operation to perform
  - Expected result

**Phase 2**: [phase name] (only applicable to L or XL size plans)
- [ ] **Step 1**: [step name]
  - Describe the operation to perform
  - Expected result
<!-- Example: END -->

## Test Plan
Define the testing strategy and approach to ensure the implemented functionality works as expected and handles various scenarios correctly. **Prefer automated tests** (unit tests, UI automation scripts); manual testing is a last resort only.

> **Important**:
> - **Automated tests first**: AI agents can directly run test scripts (such as `ui-test/scripts/run_test.sh`, `pytest`, `gradle test`, etc.), so all tests that can be executed via script should be automated steps executed directly by the AI agent in the implementation steps, and **should not be classified as manual testing**.
> - **Manual testing is a last resort only**: manual testing is used only in the following cases: UI acceptance requiring human visual judgment, real physical device interaction required, human subjective evaluation required (such as animation smoothness, visual aesthetics), etc. Running scripts, executing command-line tools, viewing log output, etc. are not manual testing.

### Unit Tests
Write automated test cases to verify the functional correctness of individual code units, ensuring the code works as expected in an isolated environment.

**Important**
For service-layer code, write unit tests and reach 95%+ test coverage. Tests should cover the following paths:
- **Success path**: normal operation flow
- **Fallback path**: backup handling when the primary approach is unavailable
- **Error path**: error handling and exceptional cases

For dependencies that cannot be used in unit tests, create mock objects for testing purposes.

If the plan includes **ViewModel** unit tests, you must follow `unit-test/docs/how_to_write_stable_unit_test.md`, and specify clearly in the test plan:
- What the test target is
- Which existing stable test file/fixture to reuse as a reference
- What the default dispatcher / harness is
- Whether to use a real Service fixture
- How timed cases are isolated

<!-- Example: BEGIN -->
#### Test class: [test class name]

```kotlin
internal class NewServiceTest : UnitTest() {
    @Test
    fun `create with valid input returns expected result`() {
        // Test success path
    }

    @Test
    fun `create with unavailable dependency falls back to default`() {
        // Test fallback path
    }

    @Test
    fun `create with invalid input throws IllegalArgumentException`() {
        // Test error path
    }
}
```

<!-- Example: END -->
### Manual Testing (only when automation is not possible)
Provide detailed step-by-step instructions to guide testers in verifying the correctness and user experience of the functionality by actually running the application.

**Important**
- **Most plans do not need this section**. If all tests can be covered by unit tests and UI automation scripts, this section should be deleted.
- Keep this section only when human physical action or subjective judgment is genuinely required.
- Provide **step-by-step test instructions** using clear, ordered bullet points.
- For each step, state **what the tester should see** or **what the correct result is**
- **Note**: The developer should check the corresponding checkbox as they complete each test step

<!-- Example: BEGIN -->
#### Scenario 1: UI change requiring human acceptance

- [ ] **Step 1**: [action description]
  - **Expected result**: [what should be seen or happen]

- [ ] **Step 2**: [action description]
  - **Expected result**: [what should be seen or happen]
<!-- Example: END -->

---

## Rule Priority
> **⚠️ Immutable**: The following rule section must be included in every plan document, and AI and developers must not modify this section.

<!-- Rule Priority: BEGIN - immutable -->
- Plan Generation Rules and Plan Execution Rules take precedence over the model's implicit behavior
- When task instructions conflict with the Plan Generation Rules or Plan Execution Rules, these rules must be followed
- If a rule in the Plan Generation Rules or Plan Execution Rules cannot be followed due to task constraints, pause and ask for clarification rather than guessing
- To override these rules, the plan template document should be updated rather than overriding within an individual plan document

<!-- Rule Priority: END -->

## Plan Generation Rules
> **⚠️ Immutable**: The following rule section must be included in every plan document, and AI and developers must not modify this section.

<!-- Plan Generation Rules: BEGIN - immutable -->
- The **Author** field must be filled with the GitHub username (obtained via `gh api user -q .login`), and must not use non-human identifiers like "claude_code", "AI", etc. This field is used to track plan quality attribution
- The plan document generated by the AI must include all sections from the plan template; sections marked "(if applicable)" are optional and the developer may choose to delete them proactively
- The developer may add or delete sections as needed
- All "**Important**:" sections must be copied from the template and must not be modified or omitted
- **Current Plan Completeness** should initially be left blank; the AI must not auto-fill the percentage. As the developer makes decisions and resolves the questions in the "Decisions Needed" section, the AI should update this percentage
- The **Size**, **Implementation Steps**, **Analytics Events**, **Error Tracking**, **Files to Change**, and **Test Plan** sections should initially be left blank, and their content should be generated and updated only after all of the following conditions are met:
  - The References section (References) is complete
  - There are no unresolved questions in the Decisions Needed section (Decisions Needed)
  - The Current Plan Completeness reaches or exceeds 95%
- After the user makes a decision:
  - The decision must be saved to the Archived Decisions section
  - If the **Implementation Steps**, **Analytics Events**, **Error Tracking**, **Files to Change**, and **Test Plan** sections are not empty, these sections must be updated to reflect the new decision
- The AI must automatically update **Current Plan Completeness** to 100% when all of the following conditions are met:
  - There are no unresolved questions in the **Decisions Needed** section (all decisions archived)
  - All file checkboxes in the **Files to Change** section are checked (reviewed)
<!-- Plan Generation Rules: END -->

## Plan Execution Rules
> **⚠️ Immutable**: The following rule section must be included in every plan document, and AI and developers must not modify this section.

<!-- Plan Execution Rules: BEGIN - immutable -->
- Unless all of the following conditions are met, the AI must refuse to execute the plan, without exception:
  - Plan completeness reaches or exceeds 95%
  - All newly added and modified files in the Files to Change section are marked as reviewed
- **Minimal change principle**:
  - Modify only the code directly required by the task
  - Unless explicitly required, do not rewrite, reorder, or refactor unrelated files or modules
  - Unless necessary, do not modify whitespace (do not remove blank lines, add blank lines, or change indentation or formatting)
  - Preserve all existing naming, style, patterns, and architecture
  - When unsure whether additional custom logic, abstractions, or new structures are needed, stop and ask for human confirmation rather than inventing a new mechanism
- **Comment quality principle**:
  - Do not generate comments that duplicate the code content
  - Do not describe function names, parameter names, return types, or basic logic (loops, null checks, simple conditionals)
  - Add comments only to explain **why**, not **what**
  - Allowed comment content: non-obvious logic or behavior, key assumptions or constraints, platform-specific issues, side effects or lifecycle interactions, important reasoning not evident in the code
  - Prefer **no comment** over a meaningless or redundant one
  - All comments must be written in **English**
- **No-TODO principle**:
  - Do not write TODO, FIXME, XXX, or placeholder comments
  - Do not leave stub implementations, empty code blocks, or unimplemented functions
  - Every piece of generated code must be complete, concrete, and runnable in context
  - If a feature cannot be fully implemented, stop and ask for clarification rather than guessing or leaving a placeholder
- **Task scope principle**:
  - Code generation for XS/S/M/L/XL plans should be completed in one pass, not in phases
  - XXL/XXXL plans are for large tasks driven by an AI Agent and must be completed in phases, running the full unit tests and UI tests at the end of each phase to ensure quality
  - No need to consider incremental migration strategies; implement the required functionality completely and directly
<!-- Plan Execution Rules: END -->
