# MVVM 架构指南

## 核心理念

MVVM 的核心价值不是「代码整洁」，而是**可测试性**和**跨平台一致性**。

我们采用 MVVM 的两个根本原因：

1. **ViewModel 级别的端到端测试**：ViewModel + 真实 Service 可以在纯 JVM 上运行集成测试，不需要设备、不需要模拟器、不需要 UI 框架。这意味着我们可以用单元测试的速度，验证完整的用户行为路径。ViewModel 的每个公开方法对应一个用户操作，测试读起来就像用户故事。在 KMP 项目中优势更加明显——`commonTest` 中编写一次测试，同时验证 iOS 和 Android 两个平台的业务流程。

2. **Kotlin/Swift 跨平台一致性**：SwiftUI 的原生模式（`ObservableObject` + `@Published` + 直接方法调用）本质上就是 MVVM。我们的 Swift 代码（认证、付费墙等页面）和 Compose 代码共享相同的架构心智模型：

```
// Swift (SwiftUI)                     // Kotlin (Compose)
class AuthViewModel: ObservableObject   class EditorViewModel: ViewModel
@Published var uiState: AuthState       val uiState: StateFlow<UiState>
func login() { ... }                    fun selectFont(id: String) { ... }
```

这使得 LLM 在两个平台上都能高效生成符合项目规范的代码——MVVM 是最主流的模式，训练数据最丰富。

---

## 基本原则

### 1. 业务逻辑归 Service，不归 ViewModel

ViewModel 的职责是：持有 UI 状态、接收用户事件、调用 Service、将结果映射为 UI 状态。

ViewModel **不应该**包含业务逻辑。所有业务逻辑必须封装在 Service 层中。ViewModel 是 Service 和 View 之间的薄胶水层。

判断标准：如果一段逻辑在另一个功能中也可能用到，它就应该在 Service 里。

### 2. 不是所有 View 都需要 ViewModel

如果一个 View 的状态管理很简单（例如纯展示、简单的本地 UI 状态切换），直接写一个 View 就够了。不要为了「架构统一」而强行引入 ViewModel。

**需要 ViewModel 的信号：**
- 状态逻辑复杂，涉及多个状态之间的联动
- 需要为该功能编写集成测试

**不需要 ViewModel 的信号：**
- 纯 UI 状态（展开/收起、动画、选中高亮）
- 无外部依赖，所有状态都在 Composable 内部完成
- 状态简单到 `remember` / `mutableStateOf` 就能搞定

**无 ViewModel 的 View 可以直接调用 Service：**

当一个 View 太小、太简单，不值得引入 ViewModel 时，View 可以直接承担 ViewModel 的职责——包括调用 Service。例如 `TabBar` 只有一个点击事件调用 `editorService.addTextElement()`，为此创建 ViewModel 是过度工程化。此时 View 本身就是 ViewModel 层，View → Service 的直接调用合法。

判断标准：如果引入 ViewModel 后，ViewModel 只是一个无状态的方法透传层（每个方法只调用 Service 的一个方法，不持有 `StateFlow`，不做状态联动），说明 ViewModel 不必要。

### 3. ViewModel 零平台依赖

ViewModel 中不允许出现任何平台相关的引用。没有 `Context`，没有 Compose 依赖，没有 Android/iOS 框架导入。

原因很简单：一旦引入平台依赖，ViewModel 就无法在纯 JVM 上测试，整个测试策略就会崩塌。

---

## 两层状态管理

项目中只允许两种状态管理模式，不允许第三种：

### 层 1：ViewModel + StateFlow（与 Service 交互的功能）

继承 `androidx.lifecycle.ViewModel`，暴露单一 `StateFlow<UiState>`。用于需要调用 Service、有复杂状态联动、或需要集成测试的功能。

UiState 有两种合法形态，根据状态特征选择：

**形态 A：data class**（默认）——当状态字段之间可以独立变化时。

```kotlin
class FeatureViewModel(
    private val editorService: EditorService,
) : ViewModel() {
    data class UiState(...)
    private val _uiState = MutableStateFlow(UiState())
    val uiState: StateFlow<UiState> = _uiState.asStateFlow()
}
```

**形态 B：sealed class**——当状态之间互斥（同一时刻只能处于一种状态）时。这是 Compose 官方推荐的状态建模方式，消除不可能的状态组合。

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

选择标准：如果你发现 data class 中存在「字段 A 为 true 时字段 B 无意义」的情况，说明状态互斥，应该用 sealed class。

### 层 2：本地 Composable 状态（纯 UI 状态）

`remember` / `mutableStateOf`，仅用于不涉及 Service 交互的纯 UI 状态。

```kotlin
@Composable
fun SimpleToggle() {
    var expanded by remember { mutableStateOf(false) }
    // ...
}
```

**禁止的模式：**
- ❌ 普通类 + `mutableStateOf`（伪 ViewModel）
- ❌ 普通类需要外部传入 `CoroutineScope`
- ❌ 一个 ViewModel 暴露多个独立的 `StateFlow`

---

## 命名规范

- View（Composable）：`[Feature]`，例如 `FontPicker`、`ColorPicker`
- ViewModel：`[Feature]ViewModel`，例如 `FontPickerViewModel`、`ColorPickerViewModel`

Composable 本身就是 View，不需要加 `View` 后缀。

---

## 状态建模

每个 ViewModel 暴露单一的 `UiState`（data class 或 sealed class），通过 `StateFlow` 向 View 提供状态。

避免在一个 ViewModel 中暴露多个零散的 `StateFlow`，这会导致状态不一致且难以测试。

---

## View 层规范

**核心规则：每个 view 自己拥有自己的 VM。** Feature 级 composable 在函数内部通过 `viewModel { }` 创建自己的 VM，**不**接收 VM 作为参数。这是 Compose 官方模式（[Android docs](https://developer.android.com/develop/ui/compose/migrate/other-considerations)：*"Try to avoid passing down ViewModel instances to other composables as this can make those composables more difficult to test and can break previews."*）。

Composable 分为两级：

### Screen-level Composable（自己创建 VM）

Feature 功能的入口 composable。在函数内部创建 VM、`collectAsState()` 订阅状态，将 state + lambda 传给 child composable。**不接收 VM 作为参数**。

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

简单场景可以把 Route（自持 VM）和 Content（纯渲染）合并成一个函数。需要 preview 或跨场景复用时再拆分。

### Child Composable（只接收状态值 + lambda）

不创建 VM，也不接收 VM。只接收它需要的状态值和 lambda 回调。这是 Compose 官方的 state hoisting 最佳实践——子组件不知道状态从哪来，因此可复用、可预览、可测试。

```kotlin
@Composable
private fun TextPropertiesBarContent(
    state: TextPropertiesBarViewModel.UiState,
    onSelectFont: (String) -> Unit,
    onOpenColorPicker: () -> Unit,
) {
    // 纯渲染 + 回调，不持有 ViewModel 引用
}
```

### 禁止把 VM 作为参数传入 Composable

```kotlin
// ❌ 错误：VM 作为参数传入
@Composable
fun LayersPanel(viewModel: LayersPanelViewModel) { ... }

// ✅ 正确：自己创建
@Composable
fun LayersPanel(onDismiss: () -> Unit) {
    val viewModel: LayersPanelViewModel = viewModel {
        LayersPanelViewModel(KoinAccessor.editorService)
    }
    // ...
}
```

VM 参数传递会破坏 composable 的独立性、可复用性和 preview 能力，也会把 VM 的生命周期与调用方耦合。

---

## 事件模式

View 通过调用 ViewModel 的公开方法与 ViewModel 通信。每个公开方法对应一个用户操作。

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

**为什么选择直接方法调用而非 `sealed UiEvent + onEvent()`：**
- 方法签名本身就是类型安全的事件定义，不需要额外的密封类包装
- 测试中 `viewModel.selectFont("INTER")` 比 `viewModel.onEvent(UiEvent.SelectFont("INTER"))` 更直观
- 这是 Google 官方 Compose 示例（Now in Android）和 SwiftUI（直接方法调用）共同使用的模式
- LLM 对这种模式有最丰富的训练数据

---

## 跨兄弟组件协调

当 A 组件需要触发 B 组件（例如 context menu 打开 panel、导航菜单弹出 dialog），**不要**让 Factory 持有双方的 VM 再互相传引用。这会破坏「view 自持 VM」的原则。正确的模式有两种：

### 模式 1：导航/可见性状态归父 VM（UI 协调）

如果协调的是 UI 状态（打开/关闭、当前选中的 tab、当前展示的 panel），把这部分状态放到**父 VM** 的 `UiState` 里。触发方通过 lambda 调用父 VM 的方法；被触发方由父 composable 根据状态条件渲染；被触发方自己的 VM 仍然由它自己在函数体内创建。

```kotlin
// 父 VM
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

// Factory（组合根）
val editorPageViewModel = viewModel { EditorPageViewModel(...) }
val state by editorPageViewModel.uiState.collectAsState()

SharedContextMenu(
    onOpenLayers = editorPageViewModel::openLayersPanel,
    onOpenAlignment = editorPageViewModel::openAlignmentPanel,
)
when (state.openPanel) {
    OpenPanel.Layers -> LayersPanel(onDismiss = editorPageViewModel::closePanel)    // 自持 VM
    OpenPanel.Alignment -> AlignmentPanel(onDismiss = editorPageViewModel::closePanel)
    null -> {}
}
```

### 模式 2：业务事件归 Service（业务协调）

如果协调的是业务事件（删除元素、提交表单、选中图层），通过 **Service** 传递。Service 是跨 VM 的共享单例，VM 订阅 Service 的状态流，任何 VM 都可以调用 Service 方法——两个 VM 之间不需要互相知道对方的存在。

```kotlin
// Context menu 触发业务操作
onDelete = { editorService.deleteSelected() }

// 其他 VM 监听 Service 状态变化
editorService.canvasState
    .onEach { /* 更新自己的 UiState */ }
    .launchIn(viewModelScope)
```

### 禁止的模式

- ❌ Factory 创建多个 feature VM 后互相传引用
- ❌ 一个 feature VM 直接持有另一个 feature VM
- ❌ Composable 从参数接收「别人的 VM」只为了调用它的方法

---

## 一次性事件（Side Effects）

Toast、Snackbar、导航跳转等一次性事件，使用 `SharedFlow<UiEffect>` 发送。

关键在于：这类事件不能放在 `UiState` 里（因为 `UiState` 是持久状态，不是一次性信号）。

---

## 依赖注入

### Compose (KMP)

Factory 作为页面组合根（composition root），通过构造函数接收顶层依赖（Service、基础设施），并创建**父级协调 VM**（例如 `EditorPageViewModel`，持有选中状态和 panel 导航状态等跨 feature 的 UI 状态）。

**Feature 级 VM 不在 Factory 创建**。每个 feature composable 在自己的函数体内通过 `viewModel { }` 创建 VM，依赖通过 `KoinAccessor` 对象从 Koin 获取：

```kotlin
@Composable
fun TextPropertiesBar() {
    val viewModel: TextPropertiesBarViewModel = viewModel {
        TextPropertiesBarViewModel(KoinAccessor.editorService)
    }
    // ...
}
```

Screen-level composable 本身就是该 feature 的 composition root，从 Koin 取依赖是合法的——service locator 反模式的问题是**深层组件**偷偷取依赖，而 screen-level composable 是声明依赖的合法位置。Child composable 仍然禁止访问 Koin，只能接收 state + lambda。

### Swift (iOS)

ViewModel 通过构造函数注入依赖。SwiftUI View 在创建时传入 ViewModel。

---

## 测试策略

这是整个架构最重要的产出。

### 集成测试 = ViewModel + 真实 Service

我们的测试策略是：在 ViewModel 层做「端到端」集成测试。使用真实的 Service 实现（不是 Mock），验证从用户操作到状态变化的完整路径。

```kotlin
@Test
fun selectFont_updatesStateAndRemeasuresBounds() {
    val viewModel = TextPropertiesBarViewModel(editorService)
    // 模拟用户操作
    viewModel.selectFont("BEBAS_NEUE")
    // 验证状态变化
    assertEquals("BEBAS_NEUE", viewModel.uiState.value.selectedTextInfo?.fontId)
}
```

**测试验证的是：**
- 用户触发操作 → ViewModel 调用 Service → 状态正确更新
- 完整的用户行为路径，不只是单个函数

**这种测试的优势：**
- 运行在纯 JVM 上，速度快
- 不需要设备、模拟器或 UI 框架
- 覆盖真实的业务流程，不是 Mock 出来的假流程
- 在 KMP 的 `commonTest` 中运行，一次测试覆盖两个平台

### 测试即 Ralph 的终止条件

测试不仅仅是质量保障，它是 Ralph 自动化循环的退出条件。Agent 生成代码后运行 ViewModel 测试——如果状态转换符合预期，循环结束。这要求测试必须是确定性的、快速的、不依赖外部环境的。

### 平台特定的异步机制

Kotlin 和 Swift 的异步机制不同，但测试策略相同：

- **Kotlin**：`viewModelScope`（自动绑定 ViewModel 生命周期），测试中使用 `UnconfinedTestDispatcher`
- **Swift**：`Task` 绑定 View 生命周期，测试中使用 `@MainActor` 和同步等待

模式相同（ViewModel 管理异步操作的生命周期），机制不同（协程 vs Swift 并发）。不要在 Swift 中强行模仿 Kotlin 协程的写法。

---

## ViewModel 的禁区

明确列出 ViewModel **不应该做**的事情，因为负面清单往往比正面清单更有指导价值：

- ❌ 不包含业务逻辑（归 Service）
- ❌ 不引用任何平台 API（`Context`、`UIKit` 等）
- ❌ 不做字符串格式化、颜色引用、尺寸引用等 UI 资源操作
- ❌ 不直接发起网络请求或数据库操作（通过 Service）
- ❌ 不持有其他 ViewModel 的引用
- ❌ 不作为参数传入 Composable（screen-level composable 内部自己创建；child composable 只接收 state + lambda）
- ❌ 不由 Factory 创建后传给 feature composable（Factory 只创建父级协调 VM，不创建 feature VM）
- ❌ 不在没有结构化 Scope 的情况下启动协程
- ❌ 不使用 Compose 的 `mutableStateOf`（使用 `StateFlow`）
- ❌ 不以普通类形式存在（必须继承 `androidx.lifecycle.ViewModel`）
