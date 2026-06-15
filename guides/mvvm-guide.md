# MVVM Architecture Guide

## Core Philosophy

The core value of MVVM is not "clean code" — it is **testability** and **cross-platform consistency**.

We adopt MVVM for two fundamental reasons:

1. **End-to-end tests at the ViewModel level**: ViewModel + real Services can run integration tests on a pure JVM without devices, simulators, or UI frameworks. This means we can verify complete user behavior paths at unit-test speed. Each public method of a ViewModel corresponds to one user action; the tests read like user stories. In KMP projects this advantage is even more pronounced — write a test once in `commonTest` and it simultaneously validates the business flow on both iOS and Android.

2. **Kotlin/Swift cross-platform consistency**: SwiftUI's native pattern (`ObservableObject` + `@Published` + direct method calls) is essentially MVVM. Our Swift code (authentication, paywall pages, etc.) and Compose code share the same architectural mental model:

```
// Swift (SwiftUI)                     // Kotlin (Compose)
class AuthViewModel: ObservableObject   class EditorViewModel: ViewModel
@Published var uiState: AuthState       val uiState: StateFlow<UiState>
func login() { ... }                    fun selectFont(id: String) { ... }
```

This enables LLMs to efficiently generate spec-compliant code on both platforms — the most mainstream pattern has the richest training data coverage.

---

## Core Principles

### 1. Business Logic Belongs in the Service, Not the ViewModel

The ViewModel's responsibilities are: hold UI state, receive user events, call the Service, and map results to UI state.

ViewModels **must not** contain business logic. All business logic must be encapsulated in the Service layer. The ViewModel is a thin glue layer between the Service and the View.

Decision test: if a piece of logic might be used by a second feature, it belongs in the Service.

### 2. Not Every View Needs a ViewModel

If a View's state management is simple (e.g., pure display, simple local UI state toggling), a plain View is sufficient. Do not force a ViewModel in the name of "architectural uniformity."

**Signals that a ViewModel is needed:**
- State logic is complex, with linkages among multiple states
- Integration tests need to be written for this feature

**Signals that a ViewModel is NOT needed:**
- Pure UI state (expand/collapse, animation, selection highlight)
- No external dependencies; all state is managed inside the Composable
- State is simple enough that `remember` / `mutableStateOf` suffices

**A View without a ViewModel may directly call the Service:**

When a View is too small and too simple to justify a ViewModel, the View may take on the ViewModel's responsibilities itself — including calling the Service. For example, a `TabBar` with only one click event calling `editorService.addTextElement()` — creating a ViewModel for this is over-engineering. In this case the View itself is the ViewModel layer, and a direct View → Service call is legitimate.

Decision test: if introducing a ViewModel results in a stateless method-passthrough layer (every method just calls one Service method, no `StateFlow`, no state linkages), the ViewModel is unnecessary.

### 3. ViewModel Has Zero Platform Dependencies

No platform-related references are allowed inside a ViewModel. No `Context`, no Compose dependencies, no Android/iOS framework imports.

The reason is simple: once a platform dependency is introduced, the ViewModel can no longer be tested on a pure JVM, and the entire testing strategy collapses.

---

## Two-Layer State Management

Only two state management patterns are allowed in the project; a third is not permitted:

### Layer 1: ViewModel + StateFlow (features that interact with the Service)

Inherits `androidx.lifecycle.ViewModel`, exposes a single `StateFlow<UiState>`. Used for features that call the Service, have complex state linkages, or need integration tests.

UiState has two valid forms; choose based on state characteristics:

**Form A: data class** (default) — when state fields can change independently.

```kotlin
class FeatureViewModel(
    private val editorService: EditorService,
) : ViewModel() {
    data class UiState(...)
    private val _uiState = MutableStateFlow(UiState())
    val uiState: StateFlow<UiState> = _uiState.asStateFlow()
}
```

**Form B: sealed class** — when states are mutually exclusive (only one state possible at a time). This is the Compose-recommended approach to state modeling, eliminating impossible state combinations.

```kotlin
class MenuViewModel(
    private val editorService: EditorService,
) : ViewModel() {
    sealed class UiState {
        data object Loading : UiState()
        data class Root(val itemCount: Int) : UiState()
        data class Detail(val itemId: String) : UiState()
        data class Error(val message: String) : UiState()
    }
    private val _uiState = MutableStateFlow<UiState>(UiState.Loading)
    val uiState: StateFlow<UiState> = _uiState.asStateFlow()
}
```

Selection criterion: if a data class has the pattern "when field A is true, field B is meaningless," the states are mutually exclusive and a sealed class should be used.

### Layer 2: Local Composable State (pure UI state)

`remember` / `mutableStateOf`, used only for pure UI state that does not involve Service interaction.

```kotlin
@Composable
fun SimpleToggle() {
    var expanded by remember { mutableStateOf(false) }
    // ...
}
```

**Prohibited patterns:**
- ❌ Plain class + `mutableStateOf` (pseudo-ViewModel)
- ❌ Plain class that requires an externally passed `CoroutineScope`
- ❌ A single ViewModel exposing multiple independent `StateFlow`s

---

## Naming Conventions

- View (Composable): `[Feature]`, e.g., `FontPicker`, `ColorPicker`
- ViewModel: `[Feature]ViewModel`, e.g., `FontPickerViewModel`, `ColorPickerViewModel`

A Composable is already a View; no `View` suffix is needed.

---

## State Modeling

Each ViewModel exposes a single `UiState` (data class or sealed class) and provides state to the View via `StateFlow`.

Avoid exposing multiple scattered `StateFlow`s from a single ViewModel — this leads to inconsistent state and is hard to test.

---

## View Layer Conventions

**Core rule: each view owns its own VM.** A feature-level composable creates its own VM inside the function via `viewModel { }` and does **not** receive the VM as a parameter. This is the official Compose pattern ([Android docs](https://developer.android.com/develop/ui/compose/migrate/other-considerations): *"Try to avoid passing down ViewModel instances to other composables as this can make those composables more difficult to test and can break previews."*).

Composables fall into two levels:

### Screen-level Composable (creates its own VM)

The entry composable for a feature. Creates the VM inside the function, subscribes to state with `collectAsState()`, and passes state + lambdas to child composables. **Does not receive VM as a parameter**.

```kotlin
@Composable
fun TextPropertiesBar() {
    val viewModel: TextPropertiesBarViewModel = viewModel {
        TextPropertiesBarViewModel(KoinAccessor.editorService)
    }
    val state by viewModel.uiState.collectAsState()
    TextPropertiesBarContent(
        state = state,
        onSelectFont = viewModel::selectFont,
        onOpenColorPicker = viewModel::openColorPicker,
        // ...
    )
}
```

For simple cases, the Route (owns VM) and Content (pure rendering) can be merged into one function. Split only when previewing or cross-scenario reuse is needed.

### Child Composable (only receives state values + lambdas)

Does not create a VM and does not receive a VM. Only receives the state values and lambda callbacks it needs. This is Compose's official state hoisting best practice — child components don't know where state comes from, so they are reusable, previewable, and testable.

```kotlin
@Composable
private fun TextPropertiesBarContent(
    state: TextPropertiesBarViewModel.UiState,
    onSelectFont: (String) -> Unit,
    onOpenColorPicker: () -> Unit,
) {
    // pure rendering + callbacks, no ViewModel reference
}
```

### Do Not Pass VM as a Parameter to a Composable

```kotlin
// ❌ Wrong: VM passed as parameter
@Composable
fun LayersPanel(viewModel: LayersPanelViewModel) { ... }

// ✅ Correct: creates its own
@Composable
fun LayersPanel(onDismiss: () -> Unit) {
    val viewModel: LayersPanelViewModel = viewModel {
        LayersPanelViewModel(KoinAccessor.editorService)
    }
    // ...
}
```

Passing a VM as a parameter breaks the composable's independence, reusability, and preview capability, and couples the VM's lifecycle to the caller.

---

## Event Pattern

The View communicates with the ViewModel by calling the ViewModel's public methods. Each public method corresponds to one user action.

```kotlin
// ViewModel
class FontPickerViewModel(...) : ViewModel() {
    fun selectFont(fontId: String) { ... }
    fun showFontPicker() { ... }
    fun dismissFontPicker() { ... }
}

// View
Button(onClick = { viewModel.selectFont(fontInfo.id) })
```

**Why direct method calls instead of `sealed UiEvent + onEvent()`:**
- The method signature itself is a type-safe event definition; no extra sealed class wrapper is needed
- In tests, `viewModel.selectFont("INTER")` is more intuitive than `viewModel.onEvent(UiEvent.SelectFont("INTER"))`
- This is the pattern used by the official Google Compose sample (Now in Android) and SwiftUI (direct method calls)
- LLMs have the richest training data on this pattern

---

## Cross-Sibling Coordination

When component A needs to trigger component B (e.g., a context menu opens a panel, a navigation menu pops a dialog), **do not** have a Factory hold both VMs and pass references between them. This breaks the "view owns its own VM" principle. The correct pattern has two forms:

### Pattern 1: Navigation/visibility state goes in the parent VM (UI coordination)

If the coordination is about UI state (open/close, currently selected tab, currently shown panel), put that state in the **parent VM**'s `UiState`. The trigger calls the parent VM's method via a lambda; the triggered component is rendered conditionally by the parent composable based on state; the triggered component's own VM is still created by itself inside its function.

```kotlin
// Parent VM
class EditorPageViewModel(...) : ViewModel() {
    data class UiState(
        val openPanel: OpenPanel? = null,
        // ...
    )
    sealed class OpenPanel {
        data object Layers : OpenPanel()
        data object Alignment : OpenPanel()
    }
    fun openLayersPanel() { _uiState.update { it.copy(openPanel = OpenPanel.Layers) } }
    fun closePanel() { _uiState.update { it.copy(openPanel = null) } }
}

// Factory (composition root)
val editorPageViewModel = viewModel { EditorPageViewModel(...) }
val state by editorPageViewModel.uiState.collectAsState()

SharedContextMenu(
    onOpenLayers = editorPageViewModel::openLayersPanel,
    onOpenAlignment = editorPageViewModel::openAlignmentPanel,
)
when (state.openPanel) {
    OpenPanel.Layers -> LayersPanel(onDismiss = editorPageViewModel::closePanel)    // owns its VM
    OpenPanel.Alignment -> AlignmentPanel(onDismiss = editorPageViewModel::closePanel)
    null -> {}
}
```

### Pattern 2: Business events go through the Service (business coordination)

If the coordination is about business events (delete element, submit form, select a layer), route it through the **Service**. The Service is a shared singleton across VMs; VMs subscribe to the Service's state flows, and any VM can call Service methods — the two VMs don't need to know about each other.

```kotlin
// Context menu triggers a business operation
onDelete = { editorService.deleteSelected() }

// Other VMs listen to Service state changes
editorService.canvasState
    .onEach { /* update own UiState */ }
    .launchIn(viewModelScope)
```

### Prohibited Patterns

- ❌ Factory creates multiple feature VMs and passes references between them
- ❌ One feature VM directly holds a reference to another feature VM
- ❌ A Composable receives "another component's VM" as a parameter just to call its methods

---

## One-Time Events (Side Effects)

One-time events such as Toast, Snackbar, and navigation jumps are sent via `SharedFlow<UiEffect>`.

The key point: these events cannot live in `UiState` (because `UiState` is persistent state, not a one-time signal).

---

## Dependency Injection

### Compose (KMP)

The Factory acts as the page composition root and receives top-level dependencies (Services, infrastructure) through its constructor, and creates the **parent coordination VM** (e.g., `EditorPageViewModel`, which holds cross-feature UI state such as selection state and panel navigation state).

**Feature-level VMs are not created in the Factory.** Each feature composable creates its VM inside its own function via `viewModel { }`, obtaining dependencies from Koin via `KoinAccessor`:

```kotlin
@Composable
fun TextPropertiesBar() {
    val viewModel: TextPropertiesBarViewModel = viewModel {
        TextPropertiesBarViewModel(KoinAccessor.editorService)
    }
    // ...
}
```

A screen-level composable is itself the composition root for its feature, and obtaining dependencies from Koin is legitimate here — the issue with the service locator anti-pattern is **deep components** secretly obtaining dependencies; a screen-level composable is a valid location to declare dependencies. Child composables still cannot access Koin; they can only receive state + lambdas.

### Swift (iOS)

ViewModels receive dependencies through constructor injection. SwiftUI Views pass in the ViewModel at creation time.

---

## Testing Strategy

This is the most important output of the entire architecture.

### Integration Tests = ViewModel + Real Service

Our testing strategy is: perform "end-to-end" integration tests at the ViewModel layer. Use real Service implementations (not mocks) to verify the complete path from user action to state change.

```kotlin
@Test
fun selectFont_updatesStateAndRemeasuresBounds() {
    val viewModel = TextPropertiesBarViewModel(editorService)
    // simulate user action
    viewModel.selectFont("BEBAS_NEUE")
    // verify state change
    assertEquals("BEBAS_NEUE", viewModel.uiState.value.selectedTextInfo?.fontId)
}
```

**What these tests verify:**
- User triggers action → ViewModel calls Service → state updates correctly
- Complete user behavior paths, not just individual functions

**Advantages of this testing approach:**
- Runs on pure JVM; fast
- No device, simulator, or UI framework required
- Covers real business flows, not fake flows mocked up
- Runs in KMP's `commonTest`; one test covers both platforms

### Tests Are the Termination Condition for Automated Loops

Tests are not just a quality guarantee — they are the exit condition for automated loops. After generating code, the agent runs ViewModel tests. If state transitions match expectations, the loop ends. This requires tests to be deterministic, fast, and independent of external environments.

### Platform-Specific Async Mechanisms

Kotlin and Swift have different async mechanisms, but the testing strategy is the same:

- **Kotlin**: `viewModelScope` (automatically bound to the ViewModel lifecycle); tests use `UnconfinedTestDispatcher`
- **Swift**: `Task` bound to the View lifecycle; tests use `@MainActor` and synchronous waiting

The pattern is the same (ViewModel manages the lifecycle of async operations); the mechanism differs (coroutines vs. Swift concurrency). Do not try to mimic Kotlin coroutine syntax in Swift.

---

## ViewModel No-Go Zone

Explicitly listing what a ViewModel **must not do**, because a negative list is often more instructive than a positive one:

- ❌ Must not contain business logic (belongs in the Service)
- ❌ Must not reference any platform API (`Context`, `UIKit`, etc.)
- ❌ Must not do string formatting, color references, or size references for UI resources
- ❌ Must not initiate network requests or database operations directly (via the Service)
- ❌ Must not hold a reference to another ViewModel
- ❌ Must not be passed as a parameter to a Composable (screen-level composables create their own VM internally; child composables only receive state + lambdas)
- ❌ Must not be created by the Factory and then passed to a feature composable (the Factory only creates the parent coordination VM; it does not create feature VMs)
- ❌ Must not launch coroutines without a structured Scope
- ❌ Must not use Compose's `mutableStateOf` (use `StateFlow`)
- ❌ Must not exist as a plain class (must inherit `androidx.lifecycle.ViewModel`)
