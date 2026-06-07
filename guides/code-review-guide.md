# 代码审查指南

审查 agent 收到 `git diff <base>...HEAD` 和可选的关联计划文档，判断代码变更是否可以合并到 main。`<base>` 是可选输入参数（commit hash），未指定时默认为 `origin/main`。

不是 lint，不是 code polish，不是 plan review。代码审查关注：计划是否被完整实现、设计决策在实现后是否仍然合理、模块边界是否完整、代码变更对代码库长期健康的影响。
代码审查是 CI 质量门禁，覆盖从 **macro（架构/模块）到 micro（类/函数）** 的完整范围；尤其用于拦截非 `max_full_send` 产出的低质量 PR。

## 审查范围

审查不限于 diff 中的变更行。如果 diff 触及了某个文件或模块，审查 agent 应评估该文件和模块的整体状态。但不要评估 diff 未触及的模块。

例如：
- diff 在 `PhotoService` 中添加了新方法，但 `PhotoService` 已有 30 个 public 方法、职责横跨三个领域 → 建议拆分
- diff 修改了 `ContextMenuViewModel` 的状态管理，但 ViewModel 承载了属于 Service 层的业务计算 → 建议下沉
- diff 新增了 `LockStateManager`，但 `SessionManager` 已有类似机制 → 重复造轮子

超出 diff 范围的发现作为 needs-refinement 建议提出。

## 三种结论

| 结论 | 含义 |
|------|------|
| **Ready** | 代码可以合并 |
| **Needs Refinement** | 代码可以合并，有改进建议 |
| **Abandon** | 代码不应合并 |

只有 abandon 阻断 PR。needs-refinement 是 non-blocking 建议。

## Clean Architecture 原则

### 关注点分离

- **Service 层**：业务逻辑。不依赖 UI 框架、渲染引擎或平台 API。
- **ViewModel 层**：view state 和交互编排。可复用的逻辑应下沉到 Service。
- **View 层**：渲染和事件转发。控制显示/隐藏是 View 的事，计算状态不是。

判断方法：这段逻辑如果要被第二个调用方复用，它是否仍应放在当前位置？

### 单一职责

一个函数做一件事。一个文件围绕一个主题。一个模块承担一个职责。

### 最小公开 API（可见性）

Kotlin 类和函数默认 `public`。这意味着**不写可见性修饰符 = 对外暴露 API**。代码生成 agent 尤其容易犯这个错误——生成 `class Foo` 而非 `internal class Foo`。

**规则**：新增的类、函数、属性必须使用最小可见性：
- **`private`** — 仅当前文件使用
- **`internal`** — 仅当前模块使用（同一 Gradle module）
- **`public`** — 确实被外部模块调用

**常见违规模式**：
- ViewModel 类缺少 `internal`（ViewModel 只在同模块的 Screen/Composable 中创建，不应暴露给其他模块）
- 数据对象（如预设颜色、常量集合）缺少 `internal`
- Composable 函数使用 `internal` 但其参数类型的类是 `public`（参数类型的可见性不应比函数更宽）

**检查方法**：用 Grep 搜索类名/函数名，确认是否有跨模块引用。无跨模块引用则必须收紧。

### 依赖方向

**模块依赖**（Gradle/KMP 模块之间）：

- editor-phone-ui → editor-service（合理）
- editor-phone-ui → editor-models（合理）
- editor-service → editor-models（合理）
- editor-service → editor-phone-ui（违规）
- editor-models → editor-service（违规）
- editor-models → editor-phone-ui（违规）

模块依赖应参照各模块的 `architecture.md` 文件确认。

**层级依赖**（同模块或跨模块的类之间）：

- View → ViewModel（合理）
- ViewModel → Service（合理）
- Service → Models（合理）
- View → Service（通常违规，但简单 View 无需 ViewModel 时合法——详见 `guides/mvvm-guide.md`「不是所有 View 都需要 ViewModel」）
- ViewModel → View（违规）
- Service → ViewModel（违规）
- Service → View（违规）

### shared-services 平台源集只做 bridge 薄转发

`shared-services/*` 中 Kotlin 的 `iosMain` / `androidMain` 源集**不得直接调用平台原生 API**（如 `platform.Photos.*`、`platform.UIKit.*`、`platform.CoreGraphics.*`、`android.graphics.*`、`android.net.Uri`、`android.provider.MediaStore` 等）。平台原生代码应写在 app 侧的 **bridge 层**（`apps/phone/ios/**/services/*Bridge.swift` 与 `apps/phone/android/app/src/main/java/**/services/*Bridge.kt`）；`iosMain` / `androidMain` 只通过 `expect`/`actual` 或注入接口向 bridge 做**薄转发**（类型翻译、挂起协程包装、回调转换）。

**为什么**：
1. 原生 API 的生命周期、线程约束、内存规则（PHImageManager 回调可能多次触发、UIKit 主线程要求、Android Activity / ContentResolver 生命周期等）在原生语言中最容易推理和调试
2. 在原生代码里可以使用 Xcode / Android Studio 的完整调试器、profiler、crash symbolication；KMP cinterop 层会吞掉这些工具链
3. 原生 crash 经 KMP 互操作层反弹回 Kotlin 侧后 stacktrace 被截断，现场难以定位
4. bridge 层天然是 app 形态特有（phone / tablet / desktop），不应与跨 app surface 的 shared-services 逻辑混在同一源集

**违规示例**：

```kotlin
// shared-services/photo-library/src/iosMain/.../IosPhotoLibraryAssetSource.kt
import platform.Photos.PHAsset                 // ❌
import platform.UIKit.UIImage                  // ❌
import platform.CoreGraphics.CGImageCreate...  // ❌

internal class IosPhotoLibraryAssetSource : PhotoLibraryAssetSource {
    override suspend fun loadAssetBytes(...) {
        val asset = PHAsset.fetchAssetsWithLocalIdentifiers(...)  // 平台 API 直接调用
        // PHImageManager + CGImageCreateWithImageInRect + UIImagePNGRepresentation 一大片
        // → 全部应下沉到 PhotoLibraryBridge.swift
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
        // BitmapFactory 探测 + decodeStream + region crop + scale 的整条链路
        // → 应下沉到 PhotoLibraryBridge.kt（app 侧）
    }
}
```

**正确形态**：

```kotlin
// shared-services/photo-library/src/iosMain/...
internal class IosPhotoLibraryAssetSource(
    private val bridge: PhotoLibraryBridgeProtocol,   // 由 app 侧注入，Swift 定义协议 + 实现
) : PhotoLibraryAssetSource {
    override suspend fun loadAssetBytes(...): ImageData? =
        suspendCancellableCoroutine { cont ->
            bridge.loadAssetBytes(localMediaId, region, target) { result ->
                cont.resume(result)            // 只做类型翻译与回调桥接
            }
        }
}
```

```swift
// apps/phone/ios/.../services/PhotoLibraryBridge.swift
@objc class PhotoLibraryBridge: NSObject, PhotoLibraryBridgeProtocol {
    @objc func loadAssetBytes(...) {
        // PHAsset / PHImageManager / CGImageCreateWithImageInRect /
        // UIImagePNGRepresentation — 平台原生逻辑全部在 Swift 里
    }
}
```

**豁免**：
- KMP 官方库（如 `kotlinx-io.SystemFileSystem`、`kotlinx-datetime`、ktor 各 engine）不算"平台原生 API"——它们本身就是 KMP 抽象，可以在 `*Main` 源集直接使用
- `expect` 函数的 `actual` 实现只用 JVM stdlib (`java.io.*`, `java.util.*`) 或 Kotlin native stdlib（非 cinterop platform.* 包）不受此规则约束
- 极简常量 / 枚举 / 静态配置（无行为、无生命周期）可以留在 `*Main`

**审查时检查**：
- Grep `shared-services/*/src/{ios,android}Main/**/*.kt` 中的 `^import platform\.` 与 `^import android\.(graphics|net|content|provider|media|hardware|util|os)\.` — 命中即违规
- 出现 `@OptIn(kotlinx.cinterop.ExperimentalForeignApi::class)` 在 shared-services 的 iosMain —— 强信号正在直接调用 CoreGraphics / CoreFoundation，应下沉到 Swift bridge
- 函数体超过 ~20 行且引用平台 API 的 iosMain/androidMain 类——几乎一定应该拆到 bridge

**严重程度**：见维度 3「架构与设计」。

### 依赖注入的适用场景

DI 适用于需要在多个不相关的地方共享同一实例的场景。例如 `PhotoService` 被多个页面使用来处理照片上传下载，通过 DI 注入合理。

DI 也适用于跨平台兼容。定义一个接口（如 `PaymentService`），iOS/Android/macOS 各有自己的实现，通过 DI 注入平台特定实现。注入可以在编译时（减小包体积）或运行时（如服务端环境切换 pre/production）。

如果一个依赖只在一处使用且没有平台变体，直接通过构造函数传入即可。例如 `RenderEngine` 只被 `CanvasView` 和 `PlatformCanvasView` 使用，直接作为参数传入，不走 DI。

过度使用 DI 会模糊对象的所有权和生命周期。

### 接口隔离

不要创建大而全的接口。每个接口面向一个使用场景。

### 模块间通信

模块之间应通过明确定义的接口通信（函数调用、数据流、回调等），暴露只读接口而非可变引用。

### 防御性检查归 Service 层

输入验证和边界检查应放在 Service 层的 public API 中，而非调用方。Service 是业务逻辑的唯一入口，由它负责确保参数合法（越界 clamp、空值拦截、非法状态拒绝）。调用方（ViewModel、手势处理器、UI 层）不应重复校验——它们信任 Service 的契约。

这样做的好处：验证逻辑只写一次，新增调用方不会因为忘记校验而引入 bug；Service 的行为对所有消费者一致。

### Assert.that / Assert.notNull / Assert.unreachable

对于**绝不应该发生**的状态违反（不是预期的运行时错误，而是代码 bug），使用 `Assert.*`（来自 `com.vibe.assertion`）而非 `Logger.logError`。语义对齐 iOS Swift `assert(_:_:)` 与 Kotlin `assert(-ea)`：**debug 抛 `AssertionError` 终止进程**；release 退化为 `Logger.logError`，调用方按返回值兜底。参见 `shared-services/assertion/docs/how_to.md`。

- `Assert.that(condition, tag) { message }` — 返回 `Boolean`，条件为 false 时 debug 抛 `AssertionError` / release 写 `[ASSERT_FAILED]` ERROR 日志
- `Assert.notNull(value, tag) { message }` — 返回 `T?`，值为 null 时 debug 抛 `AssertionError` / release 写日志
- `Assert.unreachable(tag) { message }` — 返回 `Nothing`，**双构建均终止**（日志 + 抛）；用于 `when` 穷尽兜底等控制流分析要求 Nothing 的场景

一行式用法（推荐）：
```kotlin
if (!Assert.that(isInCropMode(), LOG_TAG) { "applyCrop: not in crop mode" }) return
val element = Assert.notNull(getElementById(id), LOG_TAG) { "element $id not found" } ?: return
```

**callsite message 不要再手写 `[ASSERT_FAILED]` 前缀** —— `Assert.*` 内部自动加前缀；手写会导致 doubled prefix。

**何时用 assert vs logError**：
- `Logger.logError`：预期中可能发生的错误（网络超时、文件不存在、用户输入无效）
- `Assert.that` / `notNull` / `unreachable`：绝不应该发生的状态——如果发生了，说明代码有 bug

单元测试侧：debug 路径自然抛 `AssertionError` → 测试失败。`UnitTest` 基类在 `@BeforeTest` 调用 `BuildInfo.initialize(BuildType.DEBUG, ...)` 保证派生测试走 throw 路径。故意触发断言的测试改用 `assertFailsWith<AssertionError> { ... }` 捕获并检查 `ex.message`。

**审查时检查**：
- 新增的 `if (x == null) return` 或 `if (x !is Type) return`——如果该条件不应该发生，应使用 `Assert.that` / `Assert.notNull`
- 所有接受 `elementId` 参数的 Service 层 public 方法，应在入口处断言元素存在
- 迁移期注意 `[ASSERT_FAILED]` 字面前缀已重复——所有手写前缀应被剥除

### KISS

去掉某个抽象后功能仍然正确？那它不应该存在。

代码审查必须主动压制“看起来更工程化”的多余组件和数据结构。不要因为实现里出现了一个新名词，就默认接受新的 `Locator`、`Descriptor`、`Context`、`Result`、sealed wrapper、协议/接口或组件类。先看真实调用方需要什么：

- 只有一个调用方、只消费一个字段的结果对象，应退回简单返回值。
- 只包装两个已有 ID、没有额外不变量的 locator，应直接用现有参数或现有 domain 类型。
- 只包装一个已有 domain type 再附带少量字段的 public/shared data class，应默认视为 YAGNI。额外字段如果是稳定领域事实，应考虑加入既有类型或作为既有类型的派生 API；如果只是当前调用方需要的临时值，应在调用方计算，不要引入共享 wrapper。
- private/internal 的 pipeline carrier 不同：在异步 worker → drain、多阶段 parser、batch validation 等流程里，用一个局部 `Result` / sealed carrier 携带中间状态是合理的。审查重点是它是否表达真实阶段边界、是否保持在最小作用域、是否没有泄漏到模块外 API。
- hit-test / lookup / resolve 这类 API 不应返回“以后可能有用”的 kind、bounds、index、localPoint；当前调用方不用，就不要带。
- 新组件如果只是把一个函数拆成接口 + 实现 + 注册，而没有复用点或隔离收益，就是过度工程化。

审查时把问题问具体：这个 wrapper 去掉后，调用方是否仍能用已有数据完成工作？这个复杂返回值里的每个字段是否都被当前功能使用？如果答案是否定的，应要求简化。不要接受“未来可能需要”作为理由；未来需求出现时再引入正确抽象。

如果实现结果比原计划明显更复杂，也应触发 KISS / YAGNI 复查。计划阶段已经定义了预期变更面、文件数、抽象数量和模块边界；实现阶段若新增了计划中没有的 wrapper、interface、manager、factory、状态机、配置项或跨模块 API，reviewer 必须要求它证明必要性。合理例外是实现过程中发现计划遗漏了真实约束，并且新增复杂度直接解决当前需求；否则默认应回到计划中的更简单形态，或先更新计划再继续。

### DRY

同一逻辑只存在于一处。区分真正的重复和表面相似。

### YAGNI

没有确定需求支撑的扩展点应被质疑。

尤其要拦截“为了返回几个字段”而新增的公开包装类型：如果 `FooWrapper(foo, a, b)` 中的 `a`、`b` 是 `foo` 的真实属性或不变量，就应评估是否属于 `Foo` 本身；如果它们能从 `foo` 推导或只服务单个调用点，就不应新增 wrapper。共享 API 返回的类型越多，后续维护的契约越多，不能用“以后可能会用”来证明它们存在。局部中间结果类型只有在缩小复杂流程、隔离线程/阶段边界且不扩大公开契约时才成立。

### 遵循现有模式

代码库中已有的模式优先。引入新模式需说明现有模式为何不够用。

### Factory 模式例外

`*Factory.kt` / `*Factory.swift` 文件不受 DRY、YAGNI、KISS、最小变更面约束。详见 `guides/factory-pattern-guide.md`。

### 重构优先一次完成

重构和模块重架构优先在单个 PR 中完成。拆分到多个 PR 会让代码库长期处于新旧并存的中间状态，难以测试、难以推理。如果范围太大无法一次完成，应缩小重构范围，而不是分批执行。

### 禁止无意义的 @Deprecated 过渡期

这是移动端应用，每次发布都编译自当时最新的代码。不存在"旧客户端"需要兼容的问题——每个用户运行的都是同一个 build。

- 禁止"先标记为 `@Deprecated`，下个 PR 再删"——直接删除
- 禁止"先新旧并存，后续再迁移"——一次性完成迁移

## 审查维度

### 1. 计划与代码变更的完整性对照

如果提供了计划文档，**首先**检查代码变更是否完整覆盖了计划中的所有工作。大型任务在有限 context window 下，代码生成 agent 可能丢失上下文导致部分工作遗漏。

检查方法：
- 逐项对照 `需要修改/添加的文件`，检查每个文件是否有对应变更
- 检查 `已归档的决策` 的方案是否被正确实现
- 如果提供了 UI 测试计划，检查 AccessibilityId 和 UI 组件是否已实现

常见遗漏模式：
- **文件遗漏**：计划列 10 个文件，diff 只涉及 7 个
- **步骤遗漏**：计划 8 个步骤，后 2 个完全缺失
- **半成品**：文件创建了但只有骨架（空函数体、TODO、占位符）
- **测试遗漏**：计划要求的测试未编写
严重程度：
- 核心功能未实现（多个文件或关键步骤遗漏） → **abandon**
- 实现了与 `已归档的决策` 不同的方案 → **needs-refinement**（标注偏差，但如果结果合理则不阻断）
- 小范围遗漏（一两个非关键文件） → **needs-refinement**
- 实现方式与计划略有出入但架构合理 → **needs-refinement** 或忽略

### 2. MVVM 架构合规性

当 diff 涉及 ViewModel、View 或 Service 层代码时，必须对照 `guides/mvvm-guide.md` 检查合规性。

检查点：
- **ViewModel 必须继承 `androidx.lifecycle.ViewModel`**，使用 `StateFlow<UiState>` 管理状态，不使用 `mutableStateOf`
- **ViewModel 零平台依赖** — 不允许引用 Compose、Context、Android/iOS 框架
- **业务逻辑归 Service** — ViewModel 只做状态映射和事件转发，不包含可复用的业务计算
- **View 层极薄** — View 只做渲染和事件转发，不调用 Service，不包含状态计算
- **组合根模式** — ViewModel 在 Screen 级别通过 `viewModel { }` 创建，向下传递给子组件
- **不是所有 View 都需要 ViewModel** — 纯 UI 状态（展开/收起、动画）用 `remember` / `mutableStateOf` 即可
- **构造函数注入** — ViewModel 的依赖通过构造函数传入，不使用 Service Locator 模式（如 `Koin.get()`）
- **单元测试** — ViewModel 必须可在纯 JVM 上测试，使用 `Dispatchers.setMain(UnconfinedTestDispatcher())`

严重程度：
- ViewModel 直接依赖平台框架（Context、Compose API） → **abandon**
- 业务逻辑放在 ViewModel 且无法简单下沉 → **abandon**
- View 直接调用 Service 绑过 ViewModel → **abandon**
- ViewModel 使用 `mutableStateOf` 而非 `StateFlow` → **needs-refinement**
- ViewModel 通过 Service Locator 获取依赖 → **needs-refinement**
- 缺少 ViewModel 单元测试 → **needs-refinement**

### 3. 架构与设计（通用）

代码审查也是重新审视设计决策的机会。有些在计划阶段合理的选择，在实现后可能暴露出问题（接口比预想的复杂、抽象粒度不对、职责划分不自然）。

检查点：
- 新增的类/函数是否在正确的架构层
- 模块边界是否被打破
- 是否引入了与现有机制重复的新抽象
- **可见性是否最小化** — 新增的类/函数/属性是否使用了 `internal` 或 `private`（Kotlin 默认 `public`，必须显式收紧；详见 Clean Architecture 章节「最小公开 API」）
- 依赖方向是否正确
- 新增的抽象是否有必要
- **shared-services 平台源集是否仅为 bridge 薄转发** — `shared-services/*/src/{ios,android}Main/` 下是否直接 `import platform.*` / `import android.{graphics,net,provider,...}`；平台原生逻辑应下沉到 `apps/phone/*/services/*Bridge.{swift,kt}`。详见 Clean Architecture 章节「shared-services 平台源集只做 bridge 薄转发」。

严重程度：
- 业务逻辑放在 View/ViewModel 层且无法简单移动 → **abandon**
- 循环依赖 → **abandon**
- 破坏已有模块边界 → **abandon**
- 重复造轮子 → **abandon**
- 过度抽象但不破坏架构 → **needs-refinement**
- public 可改为 internal → **needs-refinement**
- 模块职责膨胀趋势 → **needs-refinement**
- shared-services 的 iosMain / androidMain 直接调用平台原生 API（未走 bridge） → **needs-refinement**

### 4. 技术选型

当 diff 引入了新的框架、库或平台 API 时，审查其选型是否合理。评估基于三个支柱：

- **最新**（Latest & Greatest）：是否使用了平台推荐的现代方案，而非已被取代的旧方案（如 SwiftUI vs UIKit、Compose vs View-based XML、Kotlin Coroutines vs RxJava）
- **最流行**（Most Popular）：社区采用率、维护活跃度、生态系统支持。冷门方案意味着更少的参考资料和更难招人
- **最有文档**（Most Documented）：官方文档质量、StackOverflow 覆盖率、教程和示例的丰富程度

三个支柱的共同指向通常就是 AI agent 最擅长生成高质量代码的技术栈——训练数据中覆盖最充分的技术，agent 犯错更少、产出更好。

检查点：
- 是否使用了已被平台官方取代的旧 API（如直接用 UIKit 构建新页面而非 SwiftUI）
- 是否引入了冷门第三方库，而平台原生方案或主流库已能满足需求
- 如果代码库中已有某个技术栈的使用，新代码是否无理由地引入了另一套（如项目用 Kotlin Coroutines，新代码用 RxJava）

必须 abandon 的选型（零容忍）：
- **已淘汰的包管理器**：CocoaPods（应使用 SPM）
- **已被原生取代的响应式框架**：RxSwift、ReactiveSwift、RxJava（iOS 应使用 Combine/async-await，Android 应使用 Kotlin Coroutines/Flow）
- **已被平台官方废弃的 API**

严重程度：
- 上述零容忍列表中的任何一项 → **abandon**
- 引入冷门第三方库替代平台原生方案，且无充分理由 → **needs-refinement**
- 代码库内技术栈不一致但不影响架构 → **needs-refinement**

### 5. 正确性

检查点：
- 空值处理：null/Optional/空集合
- 边界条件：off-by-one、空输入、超大输入、并发
- 状态管理：转换是否完整、是否存在非法状态
- 资源管理：流、连接、订阅是否正确关闭
- 错误处理：是否静默吞掉异常
- 并发安全：竞态条件、协程/线程安全

严重程度：
- 必定导致崩溃或数据丢失 → **abandon**
- 竞态条件可能导致间歇性崩溃 → **abandon**
- 边界条件不完整但不影响主流程 → **needs-refinement**
- 错误处理可更精细 → **needs-refinement**

### 6. 安全性

检查点：
- 硬编码密钥、token、密码
- SQL/命令注入、XSS
- 明文存储敏感信息
- 不必要的权限请求
- 日志输出敏感信息

严重程度：
- 任何安全漏洞 → **abandon**

### 7. 测试覆盖

代码审查关注的是**行为场景是否被测试保护**，不是覆盖率数字本身。覆盖率脚本负责检查百分比门槛；reviewer 要检查新增代码的真实用例、替代路径、边界条件和失败路径是否有测试能证明行为正确。

检查点：
- Service 层新增 public 方法是否有单元测试
- 新增用户可见能力或核心 service 能力是否覆盖了主要使用场景，而不是只有 happy path
- 真实风险边界是否有测试：空集合、单元素、多元素、首尾位置、越界输入、id 不匹配、重复 id、不存在的目标、坐标落在视觉边缘、pending edit / undo / redo 等
- 几何、命中检测、排序、时间、序列化、跨模块状态这类结果容易受上下文影响的逻辑，是否覆盖了会改变结果的代表性场景。例如命中检测不能只测默认坐标，还要测空白区、边界外、对齐/偏移、旋转/缩放、多目标等风险点
- 已归档决策改变的行为分支是否都有测试证明，例如 Strict vs Nearest、scope-locked vs 跨层多选、硬切签名、carrier-aware 写回
- 关键状态转换是否有测试
- 条件分支是否有覆盖（特别是 error path 和 edge case）
- 测试是否真的验证行为（非空断言、非过于宽泛的断言）

严重程度：
- 核心业务逻辑完全没有测试 → **needs-refinement**
- 只覆盖 happy path，缺少真实边界 / 替代路径测试 → **needs-refinement**
- 缺少边界条件测试 → **needs-refinement**
- 断言过于宽泛 → **needs-refinement**

### 8. UI 测试就绪性

如果提供了 UI 测试计划，检查 App 代码和测试代码是否为 UI 自动化测试做好了准备。

**AccessibilityId 一致性**：
- UI 测试计划中引用的每个 AccessibilityId 是否都已在 App 代码中设置（Kotlin 的 `Modifier.semantics { contentDescription = "id" }`）
- AccessibilityId 的拼写和大小写是否与 UI 测试计划一致
- 新增的可交互 UI 组件（按钮、菜单项等）是否都有 AccessibilityId

**UI 测试 Framework API**：
- 测试步骤中调用的 framework 函数（`ui-test/framework/` 下）是否存在，或已在 diff 中实现
- 如果新增了 framework 函数，调用的底层 API（AppiumClient、DebugApiClient）是否存在

**Pages 目录结构**（参考 `ui-test/docs/architecture.md` 的 Pages 目录结构规范）：
- 新增页面是否有对应的 `pages/{page_name}/` 文件夹
- 每个页面文件夹是否包含 `cache.py`（元素位置缓存）
- UI 组件操作是否按组件组拆分为独立文件（如 `nav_bar.py`、`context_menu.py`）
- 新增页面是否在 `verification/app_state.py` 中有对应的 `verify_app_entered_{page}()` 函数

**状态验证支持**：
- 需要通过 debug_client 验证的内部状态（zIndex、元素数量、锁定状态等）是否有对应的 debug server 端点
- 涉及变换（移动/旋转/缩放）的测试是否有 before/after 对比所需的数据接口

**平台一致性**：
- 测试脚本是否平台无关（不含 `if platform == "ios"` 判断）
- 平台差异是否在底层处理（AppiumClient、cache.py 的平台感知定位）

严重程度：
- AccessibilityId 缺失或拼写不一致 → **needs-refinement**
- 测试依赖的 framework 函数不存在 → **needs-refinement**
- Pages 目录结构不符合规范 → **needs-refinement**
- debug server 端点缺失 → **needs-refinement**

### 9. 日志覆盖

日志是 ralph_code_loop 和 ralph_ui_loop 在运行时定位问题的主要手段。没有足够的日志覆盖，自动化调试无法工作。

**日志应放在 Service 层和 ViewModel 层，不放在 View 层。** View（Composable 函数、底部弹窗等）是纯 UI 渲染，它的每个用户事件都会通过回调流向 ViewModel 或 Service，日志放在接收端即可。在 View 中加日志会导致同一事件被重复记录（View 记一次、ViewModel 记一次、Service 记一次），增加噪音而非信息。

**Debug 日志**：Service 和 ViewModel 中每个函数的每个 return 路径应有一条日志，确保无论走了哪条分支都能从日志确认执行到了哪里。重点覆盖：
- ViewModel 用户动作入口（打开/关闭面板、确认/取消、预览等）
- Service 入口（业务逻辑的调用和退出）
- 状态转换节点

**Error 日志**：所有 catch 块、错误路径、失败回退必须记录 error 级别日志。error 日志会被错误上报系统收集用于趋势监控。静默吞掉异常（空 catch 块、catch 后只 return null）是明确的问题。

不需要给纯函数、简单 getter 和 View 层 Composable 加日志。

**断言覆盖**：对于不应该发生的状态（非预期运行时错误），应使用 `Assert.that` / `Assert.notNull` / `Assert.unreachable`（`com.vibe.assertion`）而非 `Logger.logError`。重点检查：
- 接受 `elementId` 的 public 方法是否在入口断言元素存在
- `if (x == null) return` 模式——如果 null 不应该发生，应改为 `Assert.notNull(x) ?: return`
- `if (x !is ExpectedType) return` 模式——如果类型不匹配不应该发生，应添加 `Assert.that`
- `error()` 或 `throw` 用于不可能的分支——应改为 `Assert.unreachable`（控制流要 Nothing）或 `Assert.that(false) ... return`（release 可继续）
- callsite message 不应手写 `[ASSERT_FAILED]` 前缀（`Assert.*` 自动加），有则报告 doubled prefix

严重程度：
- 核心业务路径完全没有日志 → **needs-refinement**
- catch 块静默吞掉异常没有 error 日志 → **needs-refinement**
- 不可能状态用 `logError` 而非 `Assert.*` → **needs-refinement**
- 不可能状态用 `error()` / `throw IllegalStateException` 直接 crash（无 release 兜底） → **needs-refinement**
- callsite 出现 `[ASSERT_FAILED]` 字面前缀（doubled） → **needs-refinement**

### 10. 死代码

Linter 能捕获未使用的 import，但无法检测更复杂的死代码。检查 diff 触及的文件中是否存在：

- **未使用的参数** — 函数签名中存在但函数体内从未引用的参数
- **未使用的函数** — 定义了但没有任何调用方的函数（用 Grep 确认无调用）
- **未引用的类/接口** — 定义了但没有被实例化、继承或引用
- **只赋值不读取的变量** — `val x = compute()` 但 `x` 从未被后续代码使用
- **注释掉的代码** — `// val oldValue = ...` 整行，版本控制就是历史记录
- **不可达代码** — return/throw 之后的语句

严重程度：
- 死代码 → **needs-refinement**

### 11. 命名与注释质量

函数名、类名、属性名本身就是文档。名称应当足够描述性（descriptive），让读者不看注释就能知道这是什么、做什么、接受什么、返回什么。凡是注释只在描述"这是什么"、"做什么"、"参数是什么"、"返回什么"——而名称本身已经表达了这些——该注释冗余，应删除。这条规则适用于函数、类定义、属性定义，以及 KDoc / docstring 的 `@param`、`@return` 标签。

**冗余注释示例（来自代码库）：**

函数：
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
    """构建文档更新 prompt。"""
```

类：
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

属性：
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
1. **设计决策** — 解释为什么选择这个方案，而不是更显而易见的方案；注释必须自解释，不能只引用计划里的决策编号
2. **领域知识** — 非工程背景的读者无法从代码推断出的业务规则或行业约定
3. **陷阱与警告** — 非显而易见的副作用、时序依赖、平台行为差异，踩过才知道

代码注释禁止依赖计划文件上下文。计划在执行后可能归档、删除或重写；代码会长期存在。`// 决策 11 / 14：...`、`// 按 plan Q2=B ...` 这类注释把理解成本转移到外部文档，审查时应要求改成完整原因。例如不要写“决策 11：interactionMode 有损还原”，要直接写“state sync pull 只恢复 Idle 或 ElementSelection；cursor、cell range 和嵌入 contentId 都是本地瞬态 UI 状态，因此这里故意只发送 mode 标签”。

```kotlin
// iOS 上 PHPickerViewController 在模态关闭动画期间会触发 KLKeyboardObserver 约束冲突，
// 必须在 dismiss completion handler 中延迟调用 Kotlin 回调        ← 陷阱与警告
fun dismissPickerSafely(...)
```

判断标准：读完注释后再看名称，如果注释没有提供名称之外的任何信息，即为冗余。

**拼写必须正确**：函数名、参数名、类名、变量名中的英文单词必须拼写正确。常见错误如 `recieve` → `receive`、`seperate` → `separate`、`occured` → `occurred`、`lenght` → `length`。

严重程度：
- 冗余注释（包括 `@param`/`@return` KDoc 标签） → **needs-refinement**
- 只引用计划决策编号、问题编号或方案代号，未在代码旁自解释原因的注释 → **needs-refinement**
- 拼写错误 → **needs-refinement**

### 12. TODO / FIXME

已提交的代码中不应存在 `TODO` 或 `FIXME` 注释。这类标记意味着代码尚未完成。未完成的代码不应进入代码库；已知问题应以 issue / ticket 追踪，不要把追踪信息留在代码里。

严重程度：
- 存在 `TODO` 或 `FIXME` → **needs-refinement**

### 13. 空函数体 / 类体

函数体或类体为空是未完成的代码。空实现应视为骨架代码，不应提交。

```kotlin
fun onElementSelected(elementId: String) {
    // TODO: implement
}
```

严重程度：
- 空函数体或空类体 → **needs-refinement**

### 14. PR 单一目的

一个 PR 应只做一件事。如果 diff 包含多个独立目的（如：新功能 + 无关重构、两个不相关的 bug fix、新 feature + 文档结构调整），应拆分为独立 PR，而不是合并成一个。

**允许的附带变更**（不视为多目的）：
- 顺手修正几行拼写/格式
- 为本次功能顺带提取了一个小工具函数
- 少量代码风格打磨，散布在几个文件中

**必须拆分的情况**：
- 一个 PR 里同时包含一个完整的独立功能（S 级以上的工作量）和其他工作——即「把一个 S PR 偷藏进 XL/XXL/XXXL PR」
- 两个不相关的 bug fix 合并在同一个 PR 中，各自都可以独立发布
- 一个 PR 同时包含 breaking API 变更和依赖该变更的功能实现

判断标准：如果你把 diff 按目的拆开，每一部分能否独立 review、独立合并、独立回滚？可以 → 应该拆分。

严重程度：
- 包含多个独立目的且各部分工作量不可忽略 → **abandon**

### 15. Bug（未预见的边缘场景）

Bug 不是正确性问题（正确性由单元测试覆盖），而是**未处理、未预见的边缘场景导致系统部分或完全失效**。这类问题通常发生在用户交互层面，代码逻辑本身在正常路径上是对的，但在特定条件下用户会陷入无法恢复的状态。

典型模式：
- **死胡同导航** — 按钮跳转到一个页面，但该页面没有返回按钮、没有手势返回、没有任何退出机制，用户被困住
- **不可关闭的弹窗/模态** — 弹出一个对话框或 bottom sheet，但没有关闭按钮、点击外部区域无效、返回键无效
- **死锁状态** — 状态机到达一个没有出边的状态，用户无法触发任何操作恢复到正常流程
- **不可逆的破坏性操作** — 用户触发了一个操作（如删除、重置），没有确认提示，也没有撤销机制
- **输入丢失** — 用户填写了表单或编辑了内容，屏幕旋转、后台切换、或意外导航导致输入全部丢失且无法恢复

检查方法：
- 对 diff 中新增或修改的导航、弹窗、状态转换进行心理演练（mental walkthrough）
- 问："用户在这个状态下，能做什么？如果答案是'什么都做不了'，就是 bug"
- 检查新增页面/弹窗是否都有退出路径
- 检查状态机的每个状态是否都有至少一条出边

报告要求（TDD 原则）：

发现 bug 时，审查 agent 必须同时提供三项内容：
1. **复现测试** — 描述一个能复现该 bug 的单元测试或 UI 测试用例（输入、操作步骤、预期失败的断言），使修复者可以先写测试、确认红灯，再修复
2. **修复建议** — 具体的修复方案（改哪个文件、怎么改、为什么这样改）
3. **回归测试** — 修复后测试应如何变绿（预期通过的断言）

如果 bug 涉及用户交互流程（导航、弹窗、状态转换），应同时建议单元测试（验证状态机/逻辑层）和 UI 测试（验证端到端用户流程）。

严重程度：
- 用户被困住、必须强制退出 app → **abandon**
- 破坏性操作无确认且不可逆 → **abandon**
- 边缘场景导致功能降级但有替代路径 → **needs-refinement**

## 护栏

1. **先读代码再下结论** — diff 说函数 A 调用函数 B，Read 函数 B 确认签名和行为。
2. **不要猜测** — 不确定就 Read 源文件。
3. **不要修改任何文件** — 纯只读操作。
4. **区分事实和偏好** — 架构违规是事实，命名风格是偏好。只对事实做 abandon。
5. **给出具体建议** — 引用文件路径和行号，说明应该怎么改。

## 运行测试

审查 agent 可以在审查过程中运行单元测试来验证正确性，但应有选择性地运行——只运行与 diff 变更直接相关的测试，而非整个测试套件。CI 会运行全部单元测试和 UI 测试，这些测试的结果才是阻断合并的门禁。

代码审查阶段运行测试的目的是帮助 agent 快速验证可疑的正确性问题，而非替代 CI。

## Nitpicking 与真正的发现

审查 agent 必须区分 nitpicking 和真正的发现。严重程度映射由本指南定义，审查 agent 不得自行升级或降级。

**以下是 nitpicking（应忽略或省略）：**
- 建议替换命名，而当前命名已足够描述性
- 建议添加可选的日志、注释、docstring
- 提出不修复也不影响正确性的微小重构
- 建议为不可能发生的场景添加错误处理
- 评论 diff 未触及的代码且不涉及架构问题

**以下不是 nitpicking（必须执行）：**
- 本指南 15 个审查维度中严重程度映射为 abandon 的任何一项
- 破坏测试或 API 不匹配
- 正确性 bug
- 安全漏洞
- 本指南 15 个审查维度中明确定义的严重程度映射

**关键原则：**
- 本指南的严重程度映射是最终的 — 不要把风格偏好升级为 abandon，不要把 abandon 标准降级为 needs-refinement
- 如果一个发现不能映射到本指南 15 个审查维度中的任何一个，它大概率是 nitpicking
- early return 始终优于嵌套条件 — 这不是风格偏好

## 输出格式

### 详细分析

按维度组织，每个问题包含：
- **文件路径和行号**
- **问题描述**
- **严重程度**（critical🔥 / high / medium / low🧘）
- **具体建议**

### 最终结论

最后一行必须是以下之一：

- `Ready` — 可以合并
- `Needs Refinement` — 可以合并，有改进建议（最后一行之前列出所有建议）
- `Abandon` — 不应合并（最后一行之前列出所有阻断原因）

输出以结论行结束，后面不追加内容。

## 补充资源

项目内部指南：

- **命名规范**: `guides/naming-guide.md` — 模块/文件/类/函数/测试命名约定
- **术语词典**: `guides/dictionary.md` — 项目术语定义

审查 agent 可以使用 WebSearch/WebFetch 按需查阅以下官方文档：

- **Kotlin**: https://kotlinlang.org/docs/coding-conventions.html
- **Swift**: https://www.swift.org/documentation/api-design-guidelines/
- **Jetpack Compose**: https://developer.android.com/develop/ui/compose/documentation
- **SwiftUI**: https://developer.apple.com/documentation/swiftui
