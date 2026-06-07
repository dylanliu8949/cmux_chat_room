# 术语词典

本文档定义项目中常用术语的含义，确保 AI Agent 和开发者对同一个词有一致的理解。

## 架构术语

### Service
封装好的业务逻辑模块，提供明确的公开 API，隐藏内部实现细节（如平台特定支持）。Service 是可复用逻辑的归属地——如果一段逻辑可能被多个调用方使用，它属于 Service 层。

### ViewModel
UI 状态机，负责管理界面状态（如显示/隐藏组件、动画触发等）。ViewModel 不包含可复用的业务逻辑——那些属于 Service。

### View
严格关注 UI 布局和视觉呈现。View 只描述界面上元素如何排列、如何显示，不包含状态管理或业务逻辑。

### Protocol
JSON 与对象之间序列化/反序列化的实现层。负责数据的编码和解码。

### Factory
UI 模块中管理页面或大型组件变体的文件（`*Factory.kt` / `*Factory.swift`）。通过多个 create 函数为实验、多平台适配、大规模迁移等场景创建不同的 ViewModel 和 View 组合。变体之间保持代码独立以便干净删除，不受 DRY、YAGNI、KISS 约束。详见 `guides/factory-pattern-guide.md`。

## 文档术语

### Architecture（架构文档）
`docs/architecture.md`——描述模块**是什么、怎么设计的**。每个模块在 `docs/` 下放一份。不使用 `README.md`。

### How To（使用指南）
`how_to.md`——描述基础设施脚本**怎么用**，列出所有参数、参数含义、用法示例和退出码。主要用于 lint、ui-test、ralph 等工具目录。

### Guide（指南）
`guides/*-guide.md`——描述**指导原则**。经验法则、设计原则、附少量示例，不是操作清单。

### Plan（计划文档）
`plans/` 下的文件——由 agent 执行转化为代码和功能的实施计划。文件名使用 kebab-case 描述任务，不需要 `-plan` 后缀（目录本身已表明是计划）。

### Project（产品设计文档）
`projects/` 下的文件——产品设计/需求文档，描述产品**要做什么、为什么做**，面向产品层面而非实现层面。

### Template（生成模板）
`templates/` 下的文件——agent 用来生成计划、PR 等产物的模板，包含格式规范和 agent 必须遵守的规则。

### Encyclopedia（百科索引）
`guides/encyclopedia.md`——仓库中所有 Markdown 文件的索引，附简要说明。用于快速定位文档。

### Dictionary（术语词典）
本文档。定义项目术语的含义，消除歧义。

## 计划术语

### Plan（计划）
对 App 代码修改的实施计划，可以是功能计划（feature plan）、重构计划（refactor plan）、修复计划（bug fix plan）等。计划描述要改什么、怎么改、改完怎么验证。

### UI Test Plan（UI 测试计划）
专门为某个功能编写 UI 自动化测试的计划。通常关联一个主计划（feature plan），在主计划的代码实现完成后执行。

### Review（审查）
审查是"把关 + 完善"的组合过程，最终目标是对某个产物的就绪状态做出明确判断。例如：代码审查（code review）判断代码是否可以合并，计划审查（plan review）判断计划是否可以执行。审查可以输出多种状态（如可执行、需要完善、废弃），而非简单的通过/不通过。

## Ralph 术语

### Ralph
Agentic 脚本框架——在 Python 脚本内调用 coding agent（如 Claude Code）来实现传统软件无法做到的事情，例如自动调试编译错误、自动修复测试失败、从计划文档生成代码。核心思想：用 AI agent 作为子进程，让脚本具备"理解代码并修复问题"的能力。

### Full Send
全自动、非交互式、端到端的流水线。从计划审查开始，经过代码生成、调试循环、代码打磨、Lint 修复，到最终创建 PR，全程无需人工介入。

### Skill
Ralph 中的一个 Python 脚本，调用 AI Agent 执行单次任务（如计划审查、代码打磨、创建 PR）。Skill 可以独立运行，也可以被 `max_full_send` 编排调用。

### Loop（循环）
反复调用 AI Agent 直到满足预定终止条件（如测试全部通过、达到最大迭代次数、连续无进展）的自动化流程。例如 Code Loop 循环修复编译和单元测试错误，UI Loop 循环修复 UI 测试失败。

### Agent
AI 模型的封装抽象（如 Claude Code、Codex CLI），提供统一的调用接口。Ralph 通过 Agent 抽象层调用不同的 AI 后端。

## 状态同步术语

### State Sync
CLI 编辑器（agent 端）与手机 App（用户端）之间的直连 WebSocket 状态同步机制。由 3 个模块组成：`state-sync-protocol`（wire 协议类型）、`state-sync-server`（CLI daemon 侧 WebSocket 服务端，JVM only）、`state-sync-client`（手机 App 侧 WebSocket 客户端，KMP）。同步策略为全量状态推送，由 agent 通过 CLI 显式发起 `pull`/`push`，手机 App 纯被动响应。

### ApplyRemoteStateCommand
`HistoryCommand` 实现，用于将 agent push 过来的画布快照应用到手机 App。整个 agent 会话在 App 的 undo 栈中占一条记录，用户一次 Ctrl+Z 即可回退 push 之前的状态。

## 日志术语

### Renderer Tag
渲染组件日志使用的统一前缀 `Renderer/`（如 `Renderer/ImageCache`、`Renderer/RenderPipeline`、`Renderer/SkiaRenderEngine`、`Renderer/ImageLoader`、`Renderer/TextCache`）。用于在 app log 中区分渲染日志和应用日志，支持通过 `grep "Renderer/"` 提取独立的 renderer log 文件。

### Assert
`Assert.that(condition) { msg }` / `Assert.notNull(value) { msg }` / `Assert.unreachable() { msg }`——`shared-services/assertion` 模块提供的运行时不变量检测。语义对齐 iOS Swift `assert(_:_:)` 与 Kotlin `assert(-ea)`：**debug 抛 `AssertionError` 终止进程**（iOS 写 `.ips`、Android 触发 logcat FATAL EXCEPTION + tombstone）；**release 退化为 `Logger.logError`** 落 `[ASSERT_FAILED]` 前缀日志，调用方按返回值（`Boolean` / `T?`）走 release 兜底。`unreachable` 双构建均终止（`Nothing` 返回与 release-继续 不可调和）。详见 `shared-services/assertion/docs/`。

### Watchdog
`ui-test/framework/utilities/watchdog.py`——UI 测试中的后台线程，做设备日志的滚动轮转（默认 100MB cap）+ 实时 grep `[ASSERT_FAILED]` 中断测试。源码在本次 assertion 迁移中**未修改**，grep 链路仍然存在；但与 `Assert.*` 的覆盖关系是**不对称的**：

- **release 构建**：`Assert.that` / `Assert.notNull` 走 `Logger.logError` 落 `[ASSERT_FAILED]` 前缀日志，Watchdog grep 仍然捕获。
- **debug 构建**（UI 测试默认）：`Assert.*` 抛 `AssertionError` 后进程终止，根本不写日志，Watchdog grep 永远命中不到；真正的失败信号是 App 进程死亡 + 平台 crash report（`.ips` / logcat tombstone）。Watchdog 当前**没有**进程死亡探测能力。

把 Watchdog 改造为同时观察「日志 grep + 进程死亡」是独立后续任务，本 PR 不修改其源码。

## 共享服务术语

### Bridge
`apps/phone/{ios,android}/.../services/*Bridge.{swift,kt}` 中的原生代码层。所有调用平台 API（PHAsset / UIKit / MediaStore / ContentResolver / CoreML / StoreKit 等）的代码**必须**写在 Bridge——禁止出现在 `shared-services` 的 `iosMain` / `androidMain` 源集，后者只做接口声明、类型翻译和 callback 桥接。详见 `shared-services/docs/architecture.md` 规则 4。

### Port
端口模式：在跨平台共享代码中以 interface 声明能力，由可选模块（通常是 phone 形态特定）提供实现并通过 Koin 注册；运行时用 `Koin.getOrNull<Port>()` 查询，缺失则降级。典型例子：`PhotoLibraryAssetSource`（image-loader 定义、photo-library 实现）、`EditorDocumentSaver`（editor-service 定义、document-service 实现）。

### Callbacks（回调桥接）
`*Callbacks` 单例（如 `LocalStorageCallbacks`、`PhotoLibraryCallbacks`、`LoggerCallbacks`）—— KMP 层向原生层暴露的 `var` 函数槽位。App 启动时由 Bridge 注册回调，KMP 侧通过 `suspendCancellableCoroutine` 把 callback 包装为 suspend。`shared-services` 三种平台集成模式中的"模式 3"。

### Umbrella
`shared-services/umbrella`——iOS 专用的 XCFramework 聚合模块，通过 `export(project(...))` 把所有 shared-services + canvas-editor 模块打包为单一 `Shared.xcframework` 供 Swift 代码使用。

### Asset
`common-models/Asset`——图片来源元数据：含 `remoteUrl` / `localFileUrl` / `localMediaId` / `sourceWidth` / `sourceHeight` 等字段，三条来源路径互斥地非空。`ImageLoader` 按字段选择加载路径，**Asset 本身不携带像素数据**。

## 画布与渲染术语

### EditorService
编辑器业务逻辑的中心入口（`canvas-editor/editor-service`），持有 `CanvasState` + 历史 + 会话管理。20+ 个扩展函数（`applyMove` / `applyRotation` / `enterTextEditMode` 等）按职责分文件。**不依赖 editor-renderer**——两者通过 `StateFlow` 间接通信。

### CanvasState
文档状态唯一来源——所有元素的容器（`canvas-editor/editor-models`），提供元素 CRUD + 空间查询。变换操作（`applyMove` / `applyRotation` / `applyResize`）作为扩展函数定义。EditorService 持有它，所有参与者（本地用户、AI 代理、远程用户）共享同一份。

### SessionManager / LocalSessionState
选中状态和交互状态的唯一管理者（`canvas-editor/editor-service`）。`LocalSessionState = sessionId + InteractionMode + GestureState + Viewport`。重构前选中存在双写问题，重构后 SessionManager 是单一真源。

### InteractionMode
编辑器交互模式 sealed class：`Idle` / `ElementSelection` / `TextEditing` / `ImageCropping` / `TableCellSelection`。每个变体携带该模式所需的关联数据（选中元素、Handles、cursor、cellRange 等）。手势识别和模式守卫的核心分发依据。

### Handles
元素选中后的变换手柄统称：`DragHandle`（边角缩放，8 个）+ `RotateHandle`（旋转）。挂在 `InteractionMode.ElementSelection.handles` 上。**不要与"句柄"泛义混用**——本项目中 Handle 特指 UI 上的可拖动控件。

### Live renderer / Export renderer
`editor-renderer`（live 交互式渲染，含分辨率分层缓存 / 手势 UI 叠加）和 `export-renderer`（headless PNG 导出，commonMain 跨平台）是兄弟模块，**不互相依赖**。Live 含屏幕绑定的 Compose interop，无法跨到 JVM；Export 跨 android+iOS+jvm，供 editor-cli 消费。

### RenderEngine / RenderPipeline / DrawCommand
渲染三层：`RenderEngine`（每帧入口，commonMain 接口 + 平台 Skia 实现）→ `RenderPipeline`（生成 `DrawCommand` 列表，跨平台逻辑）→ `DrawCommand` 执行（Skia API 调用）。命令模式，便于测试和跨平台。

### Skia / Skiko
渲染后端：Skia 是 Google 的 2D 图形库；Skiko 是 JetBrains 的 Kotlin Multiplatform 封装。本项目通过 Skiko 在 commonMain 写一份渲染代码，Android / iOS / JVM 共享 API。

### DRT（Discrete Resolution Tier）
离散分辨率层级——`editor-renderer/ImageCache` 用的缓存键策略。把图片所需分辨率量化到 64/128/256/.../8192 的指数层级，避免微小缩放变化导致缓存抖动。容差 2px 或 1%。

## 文本与元素术语

### CanvasElement
画布元素 sealed interface，6 个子类型：`TextElement` / `ImageElement` / `ShapeElement` / `TableElement` / `WebElement` / `CanvasGroup`。所有元素共享 `id` / `center` / `width` / `height` / `zIndex` / `rotationAngle` / `margin` / `bounds` / `displayName` 字段。

### CanvasGroup
嵌套分组元素：`children: List<CanvasElement>` 可含其他 CanvasGroup（深度无限制）。`flattenElements()` 递归展平后渲染层和命中检测看到的是平的列表。

### ContentFlow / ContentBlock / InlineRun
富文本统一承载模型（决策 #19/#23）。`ContentFlow = blocks + defaultTextStyle + horizontalSpacing + verticalSpacing + lineHeight`（`lineHeight: Scale` 是 multiplier-form，`horizontalSpacing/verticalSpacing: TextSpacing` 是 pt-量化字段；HTML / RTF importer 把首块 line-height / letter-spacing 提升到 flow 间距三元组）。6 类 ContentBlock：`Paragraph` / `Heading` / `Code` / `HorizontalRule` / `EmbeddedImage` / `EmbeddedTable`；5 类 InlineRun：`Text` / `Link` / `Code` / `InlineImage` / `LineBreak`。新代码统一用 ContentFlow，不要回退到 AttributedText。

### Importer
`canvas-editor/editor-importer`——把外部文本格式（HTML / RTF / 后续 Markdown）解析成模型层的 `ContentFlow` / `TableContent`。**只产 model-only 内容数据**——id 分配、`center` / `zIndex` / `displayName` / 总宽高等 element 维度由 caller（editor-cli / 移动端 paste）自己拼装。模块依赖白名单：`editor-models` / `editor-text` / `logger-service`；禁止依赖 `editor-service` / `editor-renderer` / `editor-cli`——保持模块方向单调，让 `editor-service` 的 `commonTest` 可以反向 testImplementation-依赖它做 oracle，而生产代码不引入。KMP 目标：`androidTarget` + `iosArm64` + `iosSimulatorArm64` + `jvm`；所有解析器（HTML / RTF / 后续 Markdown）都住 `commonMain`，HTML 走 `com.fleeksoft.ksoup:ksoup`（KMP 友好的 Jsoup 移植），让移动端可以直接从系统剪贴板（iOS `UIPasteboard "public.html"` / Android `ClipData.htmlText`）粘贴 Safari / Notes / Pages 富文本。`HtmlFeatureNotSupportedException` + `TextHtmlErrorCodes` 是 wire-protocol 契约（CLI 透传错误码给 agent，`commands.md` 依赖名稳定）。详见 `canvas-editor/editor-importer/docs/architecture.md`。

### Stable ID（StableRowId / StableColumnId / StableCellId）
表格行/列稳定 id（value class），用于在插入/删除行列时保持引用稳定，**不像下标会漂移**。`StableCellId` 是行+列的复合 key。`TableElement.cells` 用 StableCellId 索引，`rowOrder` / `columnOrder` 用稳定 id 列表定义展示顺序。

### Merges（表格合并）
`TableElement.merges: List<CellRange>` 表达合并单元格。**核心不变量**：merge 内只有锚点 cell（`(rowStart, columnStart)`）的 textBlock 是真值源，非锚点 cell 必须空文本。所有"产生 cell range"的代码入口必须经过 `expandedToMerge(rowIdx, colIdx)` 或 `expandedToCoverMerges(range)`，保证 range 永不切半合并单元。

## 坐标系术语

### 4 层坐标系
`LocalPoint`（Compose 组件本地）/ `ViewportPoint`（屏幕像素）/ `CanvasPoint`（画布逻辑，缩放无关）/ `ElementPoint`（元素内容，元素左上为原点）。4 组 Point + 4 组 Distance 类型在编译期防止坐标混用。详见 `canvas-editor/editor-models/docs/coordinate-system.md`。

### CoordinateTransformer
`canvas-editor/editor-models` 的坐标变换器，依赖 `ViewportProvider` 接口。所有跨坐标系转换**必须**经过它显式完成（`localToCanvas` / `canvasToViewport` 等），禁止手动算变换矩阵。

### ViewportProvider
只读视口端口：`val viewport: Viewport` + `val screenMetrics: ScreenMetrics`。`ViewportManager` 实现它，但 renderer / coordinate transformer 只通过此接口读访问——依赖倒置原则，让 editor-models / editor-renderer 不依赖 editor-service。

## 类型安全

### Value class 包装（项目硬性约定）
本项目对**每个数值域**都用 `value class` / `data class` 包装裸 `Float` / `Int`——不止是坐标。**裸 `Float` / `Double` 不允许出现在 API 边界（函数参数、data class 字段）**，由 `lint_float_in_editor` 强制执行。已有的包装类型（按域分组）：

- **坐标 / 距离**：`CanvasPoint` / `ViewportPoint` / `LocalPoint` / `ElementPoint` + 对应 4 组 Distance
- **角度**：`Degrees` / `Radians`（通过 `toRadians()` / `toDegrees()` 显式转换）
- **缩放与比例**：`Scale`（非负）、`Fraction`（0..1）、`Opacity`（Fraction 的语义别名）
- **文本度量**：`FontSize`（1..250 自动 clamp）、`TextSpacing`、`PixelDensity`（> 0）
- **颜色**：`CanvasColor`（画布域，Long ARGB）/ `SkiaColor`（Skia API 边界）/ `ComposeColor`（typealias 到 Compose Color）
- **变换矩阵**：`AffineMatrix`（替代手写 sin/cos 旋转算式）

新增字段 / 参数前**先查 `canvas-editor/editor-models/docs/type-safety.md`**——里面已经覆盖的域不要再发明新类型。需要在内部数学（矩阵乘法、动画插值）里临时用裸 `Float` 时用 `@Suppress("RawFloat")` 局部豁免。

## 代码生成

### Wire schema codegen
`canvas-editor/editor-protocol-codegen`——离线 JVM 工具，从 `editor-protocol` 的 `KSerializer` / `SerialDescriptor` 反射生成 Python 镜像 `ui-test/framework/utilities/_generated_wire_types.py`，供 ui-test 框架直接消费 wire 类型。**工作流**：改 Kotlin `Serializable*` 类型 / 字段 / `@SerialName` 后，跑 `./gradlew :editor-protocol-codegen:run --args="--output ui-test/framework/utilities/_generated_wire_types.py"` 重新生成并**与 Kotlin 改动一起 commit**。`lint/lint_codegen_consistency.sh` 在 CI 跑 codegen → diff 已 commit 文件，漂移则 fail。新增 sealed 子类时还要在 `Main.kt` 的 `SERIAL_NAME_TO_PYTHON_CLASS` 追加一行。详见 `canvas-editor/editor-protocol-codegen/docs/architecture.md`。

## 工作流术语

### Pull Request / PR
将功能分支的代码变更合并到 main 分支的流程。PR 包含变更描述、测试说明、检查清单，需要经过审查后合并。

### Rebase
将当前分支的提交重新应用到最新的 main 分支之上，保持线性历史。合并 PR 前通常需要 rebase。

### Worktree
Git 的多工作目录功能。可以在不影响主工作区的情况下，在另一个目录中检出不同的分支。推荐在 worktree 中运行 Full Send，这样可以继续在主工作区做其他事情。
