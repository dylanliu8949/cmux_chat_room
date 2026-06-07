# 命名规范

函数名、类名、属性名本身就是文档。名称应当足够描述性，让读者不看注释就能知道这是什么、做什么、接受什么、返回什么。项目禁止在函数和类上方添加文档注释（`lint_stupid_comment.sh` 强制执行），因此命名质量是唯一的文档来源。

## 语言规范

所有代码中的标识符（函数名、类名、变量名、常量名、枚举值等）统一使用**美式英语**拼写：

```
color            ✓  美式
colour           ✗  英式
initialize       ✓  美式
initialise       ✗  英式
serialize        ✓  美式
serialise        ✗  英式
center           ✓  美式
centre           ✗  英式
canceled         ✓  美式
cancelled        ✗  英式
```

**禁止使用拼音**。所有标识符必须使用英文，不得使用汉语拼音：

```
deleteElement    ✓  英文
shanchuYuansu   ✗  拼音
fontSize         ✓  英文
zitiDaxiao       ✗  拼音
```

## 模块命名

模块名使用 **kebab-case**（小写字母 + 短横线）。

| 类型 | 后缀 | 示例 |
|------|------|------|
| 业务逻辑模块 | 无强制后缀，但推荐语义化 | `editor-service`, `editor-protocol`, `editor-text` |
| UI 模块 | 必须以 `-ui` 结尾 | `editor-phone-ui`, `editor-tablet-ui` |
| 调试/工具模块 | 按职责命名 | `editor-debug-server`, `editor-utilities` |

**UI 模块不包含 Service 类**。UI 模块只负责渲染和事件转发，业务逻辑归 Service 层。

### 文档文件命名

各文档类型的定义详见 `guides/dictionary.md`。命名规则：

| 文档类型 | 位置 | 命名规则 | 示例 |
|----------|------|---------|------|
| 模块架构 | `模块/docs/` | `architecture.md`（不用 `README.md`） | `editor-service/docs/architecture.md` |
| 使用指南 | 工具目录 | `how_to.md` | `lint/how_to.md` |
| 指导原则 | `guides/` | `*-guide.md`，kebab-case | `naming-guide.md` |
| 计划文档 | `plans/` | kebab-case，无 `-plan` 后缀 | `text-edit-cursor-input.md` |
| 产品设计 | `projects/` | kebab-case | `canvas-editor.md` |
| 生成模板 | `templates/` | kebab-case | `plan-template.md` |

**已知例外**：`shared-services/` 下的模块目前使用 camelCase（`photoService`, `localStorageService`）。新模块应使用 kebab-case，现有模块待统一重命名。

## 文件夹命名

文件夹名使用 **kebab-case**。

```
canvas-editor/editor-service/       ✓
canvas-editor/editorService/        ✗
shared-services/photo-service/      ✓（目标）
shared-services/photo-service/       ✗（现状，待迁移）
```

## 文件命名

| 语言 | 规则 | 示例 |
|------|------|------|
| Kotlin | PascalCase | `ViewportManager.kt`, `CanvasPoint.kt` |
| Swift | PascalCase | `PhotoServiceBridge.swift`, `CanvasEditorView.swift` |
| Python | snake_case | `ralph_lint_loop.py`, `run_kmp_shared.py` |
| Shell | snake_case, `verb_noun` | `run_kmp_shared.sh`, `lint_visibility.sh` |
| YAML/Config | snake_case | `lint_visibility.yaml`, `lint_dead_code.yaml` |
| Markdown | kebab-case | `naming-guide.md`, `code-review-guide.md` |

### Shell 脚本命名

Shell 脚本和函数名一样，使用 **动词开头**（`verb_noun`）：

```
run_all_lint.sh          ✓  run + 宾语
run_kmp_shared.sh        ✓  run + 宾语
lint_visibility.sh       ✓  lint + 宾语
lint_dead_code.sh        ✓  lint + 宾语
launch_ios_app.sh        ✓  launch + 宾语
setup_devices.sh         ✓  setup + 宾语
```

### Claude 命令（Slash Commands）命名

Claude 命令使用 **kebab-case**，同样 **动词开头**（`verb-noun`）：

```
/commit-and-push         ✓  commit（动词）
/execute-plan            ✓  execute（动词）
/review-plan             ✓  review（动词）
/launch-ios-app          ✓  launch（动词）
/create-plan             ✓  create（动词）
/rebase-origin-main      ✓  rebase（动词）
/worktree-new            ✗  名词开头，应为 /create-worktree
```

### Kotlin 扩展文件

当一个类通过扩展文件拆分职责时，使用 `ClassName.Topic.kt` 格式：

```
EditorService.kt                    # 主文件
EditorService.Elements.kt           # 元素操作扩展
EditorService.Viewport.kt           # 视口操作扩展
EditorService.TextEditMode.kt       # 文本编辑模式扩展
LocalSessionManager.Locking.kt      # 锁定操作扩展
LocalSessionManager.TextEditing.kt  # 文本编辑扩展
```

## 类命名

PascalCase，名词或名词短语。名称应明确表达这个类**是什么**。

### MVVM 层级命名

| 层级 | 后缀要求 | 示例 |
|------|---------|------|
| ViewModel | **必须** `*ViewModel` 后缀 | `ContextMenuViewModel`, `TextPropertiesViewModel` |
| View (页面) | 使用 `*Page` 命名页面级 View | `EditorPage`, `SettingsPage` |
| View (组件) | 无强制后缀，按 UI 组件语义命名 | `ContextMenuPanel`, `TextPropertiesBar` |
| Model | 无强制后缀，按领域语义命名 | `CanvasState`, `TextElement`, `Viewport` |

ViewModel 强制后缀是因为它是架构中唯一需要从名称上立刻辨识的层级——它连接 View 和 Service，决定了依赖方向和测试策略。View 和 Model 的身份从它们所在的模块和上下文已经足够清楚。

**页面级 View 使用 `Page`**，不使用平台特定术语：

```
EditorPage               ✓  跨平台
SettingsPage             ✓  跨平台
EditorActivity           ✗  Android 术语
EditorViewController     ✗  iOS 术语
EditorScreen             ✗  Compose 术语（已有使用，新代码应用 Page）
```

**在文档和讨论中**，组合多个子 View 的容器称为 **component**，不用 ViewGroup 等平台术语。代码中使用语义化的 UI 后缀：

| 后缀 | 含义 | 示例 |
|------|------|------|
| `*Panel` | 弹出式面板（不用 Popover/Modal） | `LayersPanel`, `ColorPickerPanel` |
| `*Bar` | 固定位置的工具/属性条 | `TextPropertiesBar`, `NavigationBar`, `TabBar` |
| `*Dialog` | 模态对话框（不用 Popup/Alert） | `ExportDialog`, `SaveBeforeExitDialog` |
| `*BottomSheet` | 底部弹出面板（不用 Modal/Popover） | `EditorBottomSheet`, `FontPickerBottomSheet` |
| `*Menu` | 上下文菜单/弹出菜单 | `ImageContextMenu`, `SharedContextMenu` |

### Service vs Manager

| 类型 | 含义 | 示例 |
|------|------|------|
| `*State` | 纯数据快照，描述某个领域的当前状况 | `CanvasState`, `LocalSessionState`, `GestureState` |
| `*Manager` | 状态管理器，持有并变更 `*State` | `ViewportManager`, `LockManager`, `LocalSessionManager` |
| `*Service` | 业务逻辑编排器，协调多个操作 | `EditorService`, `PhotoService`, `DocumentSyncService` |

**State 是纯数据**。State 类是 `data class`，描述某一时刻的状态快照，不持有 `MutableStateFlow`，不包含业务逻辑：

```kotlin
// State 示例：LocalSessionState — 纯数据快照
data class LocalSessionState(
    val sessionId: String,
    val interactionMode: InteractionMode,
    val gestureState: GestureState,
    val viewport: Viewport?,
)
```

State 和 Manager 的关系：**Manager 持有并管理 State**。`LocalSessionManager` 内部持有 `MutableStateFlow<LocalSessionState>`，对外暴露 `StateFlow<LocalSessionState>`。

**Manager 是纯状态管理器**。Manager 类的职责是：
- 持有 `StateFlow` / `MutableStateFlow` 作为状态的唯一来源
- 提供读取状态的方法（`getXxx()`, `isXxx()`）
- 提供变更状态的方法（`setXxx()`, `updateXxx()`, `clearXxx()`）
- **不调用其他 Service**，不协调多步业务流程，不做 I/O

```kotlin
// Manager 示例：LockManager — 纯状态容器
class LockManager {
    private val _permanentLocks = MutableStateFlow<Set<String>>(emptySet())
    val permanentLocks: StateFlow<Set<String>> = _permanentLocks.asStateFlow()

    fun isPermanentlyLocked(elementId: String): Boolean = ...
    fun permanentLock(elementIds: List<String>) { ... }
    fun permanentUnlock(elementIds: List<String>) { ... }
}

// Service 示例：EditorService — 协调 Manager + 其他依赖
class EditorService(
    val sessionManager: LocalSessionManager,  // 委托状态管理给 Manager
    val documentSyncService: DocumentSyncService?,
    ...
) {
    fun deleteSelectedElements() {
        // 协调多个步骤：获取选中 → 删除元素 → 记录历史 → 清除选中
    }
}
```

如果一个类既持有状态又协调业务流程，说明它需要拆分——状态部分提取为 Manager，业务部分留在 Service。

### 其他常见后缀

| 后缀 | 含义 | 示例 |
|------|------|------|
| `*Handler` | 处理特定事件/手势 | `MoveGestureHandler`, `ResizeGestureHandler` |
| `*Recognizer` | 识别并分派事件 | `GestureRecognizer` |
| `*Provider` | 提供只读数据的接口 | `ViewportProvider`, `ParagraphProvider` |
| `*Factory` | 创建对象实例 | `EditorServiceFactory`, `ExportRendererFactory` |
| `*Serializer` | 序列化/反序列化 | `CanvasSerializer`, `EditorSnapshotSerializer` |
| `*Callbacks` | Swift 桥接回调容器（iOS 特有） | `PhotoServiceCallbacks`, `LocalStorageCallbacks` |
| `*Utils` | 无状态工具函数集合 | `GeometryUtils`, `CoordinateTransformer` |
| `*Command` | 可撤销的操作（历史系统） | `MoveElementCommand`, `InsertElementCommand` |

## 函数命名

camelCase，动词开头。名称应明确表达这个函数**做什么**。

```kotlin
fun moveElement(...)          ✓  动词 + 宾语
fun element(...)              ✗  不知道要对 element 做什么
fun handleMoveGesture(...)    ✓  handle + 事件名
fun process(...)              ✗  太模糊
```

### 布尔返回值

以 `is` / `has` / `should` / `can` 开头：

```kotlin
fun isElementSelected(...)    ✓
fun hasPermission(...)        ✓
fun shouldShowHandle(...)     ✓
fun canUndo(): Boolean        ✓
fun checkSelected(...)        ✗  不清楚返回什么
```

### Composable 函数

PascalCase，名词（Compose 约定）：

```kotlin
@Composable
fun EditorScreen(...)         ✓
@Composable
fun ContextMenuPanel(...)     ✓
@Composable
fun showEditor(...)           ✗  Composable 不用动词开头
```

## 属性与变量命名

camelCase，名词。名称应明确表达这个值**是什么**。

```kotlin
val selectedElementIds: Set<String>       ✓
val ids: Set<String>                      ✗  什么的 id？
val viewport: Viewport                    ✓
val v: Viewport                           ✗  别缩写
```

### 常量

UPPER_SNAKE_CASE：

```kotlin
private const val LOG_TAG = "ViewportManager"
private const val MIN_ZOOM_SCALE = 0.1f
private const val ANIMATION_FRAME_DELAY_MS = 16L
```

### StateFlow

后缀 `Flow`（公开）或前缀 `_`（私有可变）：

```kotlin
private val _canvasStateFlow = MutableStateFlow(initialState)
val canvasStateFlow: StateFlow<CanvasState> = _canvasStateFlow
```

## 类型安全包装

PascalCase，领域名词。不用 `*Wrapper` 后缀——包装类型本身就是一等公民：

```kotlin
CanvasPoint          ✓  不是 FloatPointWrapper
Degrees              ✓  不是 FloatDegreeWrapper
Scale                ✓
FontSize             ✓
CanvasDistance        ✓
ViewportDistance      ✓
```

## 坐标类型前缀

坐标类型以所属坐标系为前缀，区分同构但语义不同的类型：

| 前缀 | 坐标系 | 示例 |
|------|--------|------|
| `Canvas*` | 逻辑画布坐标 | `CanvasPoint`, `CanvasDistance` |
| `Viewport*` | 屏幕像素坐标 | `ViewportPoint`, `ViewportDistance` |
| `Local*` | Compose 组件本地坐标 | `LocalPoint`, `LocalDistance` |
| `Element*` | 元素内容坐标 | `ElementPoint` |
| `Screen*` | 绝对屏幕坐标（可序列化） | `ScreenPoint`, `ScreenBounds` |

## 包命名

全小写，无分隔符：

```
com.vibe.canvaseditor.models
com.vibe.canvaseditor.services
com.vibe.canvaseditor.rendering
com.vibe.photoservice
com.vibe.loggerservice
```

## 测试命名

| 类型 | 规则 | 示例 |
|------|------|------|
| Kotlin 测试类 | `*Test` 后缀 | `ViewportManagerTest.kt` |
| Kotlin 按主题拆分的测试类 | `ClassUnderTest` + `Topic` + `Test` | `EditorServiceDuplicateTest.kt`, `EditorServiceLayeringTest.kt` |
| Kotlin Mock 类 | `Mock*` 前缀 | `MockEditorServiceFactory.kt` |
| Kotlin 测试 Helper | `*TestHelper` 后缀 | `ElementTestHelper.kt`, `EditorServiceTestHelper.kt` |
| Kotlin 测试函数 | 反引号 + 自然语言描述行为 | `` `duplicate image to target center preserves properties` `` |
| Python 单元测试 | `test_` 前缀 | `test_models.py` |
| Python 单元测试类 | `Test*` 前缀 | `TestCanvasState` |
| Swift 测试文件 | `*Tests` 后缀 | `PhotoServiceTests.swift` |

### UI 测试命名

UI 测试分两类目录：

| 目录 | 用途 | 命名规则 | 示例 |
|------|------|---------|------|
| `ui-test/e2e-tests/` | 回归测试（全流程） | `editor_e2e_N_test.py`（编号） | `editor_e2e_1_test.py` |
| `ui-test/feature-tests/` | 新功能 TDD 测试 | `feature_name_test.py`（与 plan 名对应） | `lock_and_unlock_test.py` |

feature-tests 文件名从计划文档名转换而来（kebab-case → snake_case）：

```
plans/lock-and-unlock.md           → feature-tests/lock_and_unlock_test.py
plans/image-crop-mode.md           → feature-tests/image_crop_mode_test.py
plans/layers-panel.md              → feature-tests/layers_panel_test.py
```

每个 UI 测试文件包含平台入口函数对（`test_xxx_ios` + `test_xxx_android`），委托到共享的 `_test_xxx` 实现：

```python
@pytest.mark.asyncio
async def test_lock_and_unlock_ios(ios_runner, ios_gesture):
    await _test_lock_and_unlock(ios_runner, ios_gesture, "iOS")

@pytest.mark.asyncio
async def test_lock_and_unlock_android(android_runner, android_gesture):
    await _test_lock_and_unlock(android_runner, android_gesture, "Android")
```

### Kotlin 测试类结构

- 测试类标记为 `internal class`
- 一个测试类对应一个文件
- 当被测类功能多时，按主题拆分为多个测试文件：`EditorServiceDuplicateTest`、`EditorServiceLayeringTest`、`EditorServiceTextEditModeTest`
- 测试函数名使用反引号包裹的自然语言，描述 **行为** 而非实现：

```kotlin
internal class EditorServiceDuplicateTest {
    @Test
    fun `duplicate image to target center preserves properties`() { ... }

    @Test
    fun `duplicate with invalid source id returns null`() { ... }

    @Test
    fun `duplicate elements is single undoable operation`() { ... }
}
```

测试函数名的模式：`` `操作 + 条件（可选） + 预期结果` ``

```
`initializeViewport should set up viewport correctly`     ✓  行为描述
`duplicate with invalid source id returns null`            ✓  条件 + 结果
`testDuplicate`                                            ✗  不描述行为
`test_duplicate_returns_null`                              ✗  不用 test_ 前缀
```

### 测试 Helper 的位置

| 场景 | 位置 | 示例 |
|------|------|------|
| 被多个模块的测试共用 | `commonMain`（非 `commonTest`） | `ElementTestHelper.kt`, `EditorServiceTestHelper.kt` |
| 仅被当前模块的测试使用 | `commonTest` | `GestureHandlerTestHelper.kt` |

放在 `commonMain` 的 TestHelper 需要在文件头部添加警告注释，防止在生产代码中误用：

```kotlin
// ============================================================================
// WARNING: TEST HELPER ONLY
// This file exists in commonMain so that ALL modules' test sources can use it.
// Do NOT use these functions in production code.
// ============================================================================
```

## DI 模块命名

camelCase 的 `val`，`*Module` 后缀：

```kotlin
val editorServiceModule = module { ... }
val editorTextModule = module { ... }
val androidPhotoServiceModule = module { ... }
val iosPhotoServiceModule = module { ... }
```

## Accessibility ID

PascalCase 字符串，与组件名对应：

```kotlin
Modifier.semantics { contentDescription = "EditorCanvas" }
Modifier.semantics { contentDescription = "ContextMenuDelete" }
Modifier.semantics { contentDescription = "TextPropertiesBar" }
```

## 枚举命名

PascalCase 类名，UPPER_CASE 条目：

```kotlin
enum class InteractionMode {
    IDLE,
    DRAGGING,
    RESIZING,
    ROTATING,
}
```

对于携带数据的枚举（sealed class），条目使用 PascalCase：

```kotlin
sealed class InteractionMode {
    data object Idle : InteractionMode()
    data class Dragging(val elementId: String) : InteractionMode()
}
```
