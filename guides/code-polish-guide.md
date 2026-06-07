# 代码打磨指南

代码打磨是 max_full_send 流水线中 lint 之前的最后一道人工智能审查步骤。所有代码生成和调试循环完成后、进入 lint 之前，打磨 agent 对全部变更代码进行质量改善。打磨的目标是：**在不改变任何行为的前提下，让代码更易读、更一致、更整洁**。打磨后紧接着 lint 阶段会捕获任何格式问题。

打磨不是重构。重构改变代码结构以支持新需求；打磨只是擦亮已有的代码。一个好的打磨 diff 应该让审查者觉得"这些改动显而易见，我自己也会这么改"，而不是"这段代码被重新设计了"。

打磨不是 linting。Linter 处理机械性的格式问题（缩进、空行、import 排序、行长度）。打磨处理的是 linter 无法检测的语义层面问题——相当于 code review 中的 nit picking：命名不够清晰、逻辑可以更简洁、死代码未清理、注释冗余、日志缺失。两者互补但不重叠，打磨不应浪费 turns 在 linter 会处理的事情上。

## 核心原则

代码打磨与代码审查共享同一套工程原则（KISS/DRY/YAGNI/模式一致性），但颗粒度是 **micro**：函数、类、单文件可读性与整洁度。打磨 agent 在做每一处改动时都应以此为判断基准：

- **KISS — 保持简单**：最简单的方案就是最好的方案。去掉一个抽象/一层间接后功能仍然正确？那这个抽象不应该存在。
- **DRY — 不要重复自己**：同一逻辑只存在于一处。两段相似的代码如果变更理由相同，提取为共享函数；如果变更理由不同，保持独立。
- **YAGNI — 你不会需要它**：不要为假想的未来需求编写代码。"预留扩展点"、"为后续功能铺路"——没有确定需求支撑的扩展全部砍掉。
- **遵循现有模式**：代码库中已有的模式就是最好的参考。发明新模式的门槛极高：只有当现有模式确实无法满足需求时才考虑。
- **变更范围**：以 diff 触及的函数/类/文件为主做局部打磨；不主动做跨模块扩散修改。
- **Factory 模式例外**：`*Factory.kt` / `*Factory.swift` 文件不受 DRY、YAGNI、KISS 约束。打磨时不要提取 Factory 变体之间的共用逻辑。详见 `guides/factory-pattern-guide.md`。

### 最小变更面

打磨的每一处改动都应有明确理由，不要为了"更好"而改，要为了"明显更好"而改。

打磨不是重写。如果一段代码已经可读、可维护，不需要碰它。常见的变更膨胀来源：

- **吹毛求疵**：把完全可读的 `items.filter { it.isValid }.map { it.name }` 改写为"更优雅"的写法
- **风格偏好**：把 `if/else` 换成 `when` 仅因为个人偏好，而非可读性有明显改善
- **过度提取**：只出现一次的代码不需要提取为函数。提取的触发条件是**重复**，不是"可能以后会复用"
- **大面积格式调整**：仅调整空行、缩进、import 排序等纯格式问题应交给 linter 处理

## 打磨清单

### 1. 移除所有死代码

Linter 能捕获未使用的 import，但无法检测更复杂的死代码。打磨 agent 必须在变更文件中找到并删除：

- **未使用的参数** — 函数签名中存在但函数体内从未引用的参数
- **未使用的函数** — 定义了但没有任何调用方的函数（使用 `Grep` 确认无调用）
- **未引用的类/接口** — 定义了但没有被实例化、继承或引用
- **只赋值不读取的变量** — `val x = compute()` 但 `x` 从未被后续代码使用
- **注释掉的代码** — `// val oldValue = ...` 整行删除，版本控制就是历史记录
- **不可达代码** — return/throw 之后的语句

### 2. 命名必须详尽描述意图

函数名和参数名是最好的文档。命名应当让读者不看函数体就能知道这个函数做什么、接受什么、返回什么。

- `fun process(d: List<Any>)` → `fun filterExpiredSubscriptions(subscriptions: List<Subscription>)`
- `val result = check()` → `val isSubscriptionValid = validateSubscriptionStatus()`
- `fun handle(e: Event)` → `fun dispatchCanvasTouchEvent(event: CanvasTouchEvent)`

命名原则：
- 函数名用**动词短语**，描述它做什么
- 参数名用**名词短语**，描述它是什么
- 布尔变量/函数用 `is`/`has`/`should` 前缀
- 不缩写（`btn` → `button`，`msg` → `message`，`ctx` → `context`），除非是领域内广泛接受的缩写（`id`、`url`、`api`）
- **拼写必须正确**：函数名、参数名、类名、变量名中的英文单词必须拼写正确。常见错误如 `recieve` → `receive`、`seperate` → `separate`、`occured` → `occurred`、`lenght` → `length`

### 3. 删除描述代码元素自身含义的注释

函数名、类名、属性名本身就是文档。名称应当足够描述性（descriptive），让读者不看注释就能知道这是什么、做什么、接受什么、返回什么。凡是注释只在描述"这是什么"、"做什么"、"参数是什么"、"返回什么"——而名称本身已经表达了这些——该注释全部冗余，必须删除。这条规则适用于函数、类定义、属性定义，以及 KDoc / docstring 的 `@param`、`@return` 标签。

**删除——函数：**
```kotlin
/**
 * Returns all elements in the canvas.
 * @return List of all canvas elements
 */
fun getAllElements(): List<CanvasElement>
```
```swift
// Dismisses the photo picker and invokes the completion handler
func dismissPickerAndInvokeCallback(picker: PHPickerViewController, completion: () -> Void)
```
```python
def _build_update_docs_prompt(...) -> str:
    """构建文档更新 prompt。"""
```

**删除——类：**
```kotlin
// 管理视口状态
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

**删除——属性：**
```kotlin
// 当前选中的元素 ID 集合
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

**注释存在的合理理由只有三种：**
1. **设计决策** — 解释为什么选择这个方案，而不是更显而易见的方案
2. **领域知识** — 非工程背景的读者无法从代码推断出的业务规则或行业约定
3. **陷阱与警告** — 这段代码有非显而易见的副作用、时序依赖、平台行为差异，踩过才知道

不属于以上任何一种的注释，删除。

```kotlin
// iOS 上 PHPickerViewController 在模态关闭动画期间会触发 KLKeyboardObserver 约束冲突，
// 必须在 dismiss completion handler 中延迟调用 Kotlin 回调        ← 陷阱与警告
fun dismissPickerSafely(picker: PHPickerViewController, completion: () -> Unit)
```
```python
# standalone 模式：使用明确指定的目标路径（不从 git diff 推断）   ← 设计决策
if targets is not None:
```

判断标准：读完注释后再看名称，如果注释没有提供任何名称之外的信息，删除它。

### 4. 禁止 TODO / FIXME

已提交的代码中不应存在 `TODO` 或 `FIXME` 注释。这类标记意味着代码尚未完成，不应进入代码库。

- 如果功能尚未完成，不要提交这段代码
- 如果是已知问题或技术债，创建对应的 issue / ticket，不要把追踪信息留在代码里
- 注释掉的代码同样禁止——版本控制就是历史记录

```kotlin
// TODO: handle the case where element is null  ← 删除，或实现它，或不提交
// FIXME: this crashes on rotation              ← 删除，或修复它，或不提交
```

### 5. 禁止空函数体 / 类体

函数体或类体为空是未完成的代码，不应提交。

```kotlin
fun onElementSelected(elementId: String) {
    // TODO: implement
}

class ToolbarViewModel {
}
```

如果接口要求实现但当前不需要逻辑，显式标注原因；如果是占位符，不要提交。

### 6. 展平嵌套

降低嵌套层级让代码的主路径更明显。用 guard clause + early return 替代深层 if-else。

之前：
```kotlin
fun processElement(element: CanvasElement?) {
    if (element != null) {
        if (element.isVisible) {
            if (!element.isLocked) {
                // 实际逻辑
            }
        }
    }
}
```

之后：
```kotlin
fun processElement(element: CanvasElement?) {
    if (element == null) return
    if (!element.isVisible) return
    if (element.isLocked) return
    // 实际逻辑
}
```

### 7. 简化布尔表达式

Linter 能捕获部分冗余，但更复杂的模式需要人工简化。

- `if (condition) return true else return false` → `return condition`
- `if (x == true)` → `if (x)`
- `if (x != null) x else defaultValue` → `x ?: defaultValue`
- `if (a) { if (b) { ... } }` → `if (a && b) { ... }`（仅当无副作用时）

### 8. 收紧可见性

**Kotlin 类和函数默认 `public`**——不写修饰符 = 对外暴露 API。代码生成 agent 几乎总是生成 `class Foo` 而非 `internal class Foo`，这是打磨阶段最常见的必修项。

**检查步骤**：
1. 对 diff 中每个新增的 `class`、`object`、`fun`（顶层或类成员），检查是否缺少可见性修饰符
2. 使用 `Grep` 搜索名称，确认实际引用范围
3. 按最小权限原则设置可见性：
   - 无跨文件引用 → `private`
   - 仅同模块引用 → `internal`
   - 只有确实被外部模块调用的才保持 `public`

**高频违规类型**（打磨时重点扫描）：
- ViewModel 类（只在同模块 Screen 中 `viewModel { }` 创建，必须 `internal`）
- 数据对象 / 常量集合（如 `PresetColors`、配置常量，必须 `internal`）
- Composable 内部子组件（已用 `internal fun`，但其参数类型的类可能仍是 `public`）
- 扩展函数（如果只在当前模块使用，应为 `internal`）

### 9. 移除无意义的中间变量

当变量名不比函数名提供更多信息时，中间变量就是噪音。

- `val result = computeTotal(); return result` → `return computeTotal()`
- `val isValid = list.isNotEmpty(); if (isValid) { ... }` → `if (list.isNotEmpty()) { ... }`

保留中间变量的情况：
- 变量名确实增加了可读性（`val activeSubscriptions = subscriptions.filter { it.isActive }`）
- 值被多次使用
- 需要在 debugger 中检查

### 10. 遵循周围代码的模式

新代码应当与相邻代码保持相同的风格、结构和惯例。Linter 强制语法一致，但无法强制项目约定一致。

- 如果现有代码用 builder pattern，新代码也用 builder pattern
- 如果现有代码用 factory method 创建对象，新代码也用 factory method
- 如果现有代码用 `Result<T>` 处理错误，新代码也用 `Result<T>`
- 如果现有的 HistoryCommand 都遵循 execute/undo 对称结构，新命令也必须如此

发明新模式的门槛极高：只有当现有模式确实无法满足需求时才考虑。

### 11. 日志覆盖

日志是 Ralph debug loop 在运行时定位问题的**唯一手段**。没有人类在场看 console，debug loop 完全依赖日志判断代码执行到了哪一步、在哪里出了问题。因此日志必须在"够用"和"不刷屏"之间找到平衡。

这一点在响应式代码里尤其重要。只靠静态阅读代码，经常很难准确推断状态流、callback、协程和 UI 事件之间的实际执行顺序。日志的价值不只是"报错时看一眼"，而是让 agent 能从 runtime 轨迹里还原：什么用户动作触发了哪条链路、哪次 service 调用真正执行了、状态是在哪个阶段偏掉的。

**规则：优先补齐关键业务链路的日志（UI 动作入口、Service 入口、错误路径），不强制为所有函数的每个 return 路径补日志。**

这确保无论函数走了哪条分支，debug loop 都能通过日志确认函数执行到了哪里、以什么结果退出。

```kotlin
fun loadDocument(documentId: String): Document? {
    val cached = cache.get(documentId)
    if (cached != null) {
        Logger.logDebug(TAG, "loadDocument: cache hit for $documentId")
        return cached
    }

    val document = repository.fetch(documentId)
    if (document == null) {
        Logger.logDebug(TAG, "loadDocument: document not found $documentId")
        return null
    }

    cache.put(documentId, document)
    Logger.logDebug(TAG, "loadDocument: fetched and cached $documentId")
    return document
}
```

**中间日志**——函数体中、return 之前的日志——允许但应与函数长度成比例：

- 短函数（< 10 行）：0 条中间日志，return 日志已足够
- 中等函数（10-30 行）：1-2 条中间日志，标记关键节点
- 长函数（> 30 行）：适量中间日志，标记每个重要阶段的入口

**日志格式**遵循代码库现有模式：
- Kotlin: `Logger.logDebug(TAG, "functionName: message")`
- Swift: `logger.logDebug(tag: TAG, message: "functionName: message")`
- Python: `print("[module] functionName: message")`

**日志内容**必须包含足够上下文：函数名、关键参数值、执行结果。`"loading..."` 没用，`"loadDocument: fetched and cached doc_abc123"` 有用。

打磨时应特别检查两类入口：

- **UI 动作入口**：点击、拖拽、菜单操作、导航切换、提交按钮等用户动作，一旦进入应用逻辑，应有明确日志。这样 debug loop 才能确认"用户动作是否真的触发了目标链路"。
- **Service 入口**：所有承载业务逻辑的 service 调用，应有入口日志和关键退出日志。这样 debug loop 才能确认"业务逻辑是否真的执行、执行到了哪一步、以什么结果退出"。

但不要把日志要求机械地扩展到所有纯函数和数据模型 helper。像 `AxisAlignedBounds.center/width/height` 这类无副作用、无分支、纯几何访问器，通常不需要日志。日志应优先覆盖**运行时流程节点**，而不是给每个简单 getter 都加噪音。

### 12. 断言覆盖

对于**绝不应该发生**的状态（不是预期运行时错误，而是代码 bug），应使用 `Assert.that` / `Assert.notNull` / `Assert.unreachable`（来自 `com.vibe.assertion`）而非 `Logger.logError`。语义：debug 抛 `AssertionError` 终止进程，release 退化为 `Logger.logError`。参见 `shared-services/assertion/docs/how_to.md`。

打磨时重点扫描：

- `if (x == null) return` — 如果 null 不应该发生，改为 `Assert.notNull(x) ?: return`
- `if (x !is ExpectedType) return` — 如果类型不匹配不应该发生，添加 `Assert.that`
- `error()` 或 `throw IllegalStateException` 用于不可能的分支 — 改为 `Assert.unreachable`（控制流要 Nothing）或 `Assert.that(false) ... return`（release 兜底可继续）
- 接受 `elementId` 的 public 方法缺少入口断言
- callsite message 出现 `[ASSERT_FAILED]` 字面前缀——`Assert.*` 内部已自动加前缀，手写会产生 doubled prefix，应删除

一行式用法：
```kotlin
if (!Assert.that(isInCropMode(), LOG_TAG) { "applyCrop: not in crop mode" }) return
val element = Assert.notNull(getElementById(id), LOG_TAG) { "element $id not found" } ?: return
```

**何时用 Assert vs logError**：
- `Logger.logError`：预期中可能发生的错误（网络超时、文件不存在、catch 块）
- `Assert.that` / `Assert.notNull` / `Assert.unreachable`：绝不应该发生的状态——如果发生了，说明代码有 bug

## 禁止的操作

| 类别 | 说明 | 为什么禁止 |
|------|------|------------|
| **模块重组** | 移动文件、拆分/合并模块 | 破坏现有架构，需要专门的重构计划 |
| **改变公开 API** | 修改 public 方法签名、返回类型、异常类型 | 影响调用方，可能引入编译错误 |
| **新增依赖** | 引入新的第三方库或框架 | 改变项目依赖图，需要架构审批 |
| **修改/新增测试** | 修改测试文件、新增测试用例 | 测试已通过，改动测试可能掩盖问题 |
| **新增功能** | 增加新行为、新参数、新配置项 | 超出当前计划的范围 |
| **改变行为** | 修改业务逻辑、调整条件判断的语义 | 已通过的测试验证的是当前行为 |
| **文件移动** | 将代码从一个文件移到另一个文件 | 即使逻辑上更合理，也属于重构而非打磨 |

### 边界判断

**可以做：**
- 把 `fun processData(input: List<Any>)` 内部的局部变量从 `val x` 改为 `val processedItems` — 内部重命名，不影响 API
- 把连续三个相同的 null check 提取为 `requireNotNull()` 调用 — 简化，不改变行为
- 删除一个只被赋值但从未读取的变量 — 移除死代码
- 给已有函数的每个 return 路径补充日志 — 提升可观测性

**不可以做：**
- 把 `fun processData(input: List<Any>)` 改为 `fun processData(input: List<String>)` — 改变了 API
- 把三个独立的 if 检查合并为一个 when 表达式并改变分支顺序 — 如果分支有副作用，顺序可能影响行为
- 把 `catch (e: Exception)` 改为 `catch (e: IOException)` — 改变了异常捕获范围
- 新增一个 `companion object` 来存放常量并把其他文件的常量也迁移过来 — 涉及跨文件重组

## 操作约束

### 输入上下文

打磨 agent 收到的 prompt 包含：
- **精简版计划文档**（经 `strip_plan_for_codegen()` 处理）
- **git diff**（`git diff origin/main...HEAD`）— 完整变更内容，diff headers 中包含所有变更文件路径

这些内容已在 prompt 中，不需要重新读取。按需读取源文件——修改某个文件前先 `Read` 它，确认当前完整内容。不要一次性读取所有变更文件，逐个处理以避免上下文膨胀。
