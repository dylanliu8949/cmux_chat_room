**作者**：dylanliu8949
**大小**：XXXL（审查后拆成 18 个独立 PR / phase：-1、0、1、1A、1B、2、3、4、5、6、7、8a、8b、8c、9、10、11、12；多数为机械删除，单 phase 多为 XS–M（按机械性降级规则，如删 `web/` 65k LOC 实为 XS 审查复杂度），整体按 XXXL 计——跨模块 + 持久化恢复契约 + remote 解耦）
**base commit hash**：961cc2b5157b1388e253734bfe37389b3492be32
**branch name**：feat/chat-room
**创建日期**：2026-06-07
**状态**：review-plan-in-progress
**前置任务（如适用）**：聊天室核心（rooms + agent tabs + 回复路由 + 会话恢复）**须在 Phase -1 先证实可用**——审查指出 dogfood 曾出现 agent 完成却 `0 / N replied`，且本计划每个 phase 都以「聊天回复仍正常」为门控，故删除前必须先证明 `@all` 回复路由 + reload/会话恢复工作（原始设计：`plans/2026-06-06-cmux-ai-chat-room-design.md`）
**后续任务（如适用）**：内部标识符全量 `cmux→bus` 重命名（仅在采纳「完整重命名」决策时，作为独立 XXXL 计划）

> **大小说明**：
> - `XS`: 超小任务（代码变更行数 < 50，涉及文件数 < 3，新增抽象数 0）
> - `S`: 小任务（代码变更行数 50-200，涉及文件数 3-5，新增抽象数 0-1）
> - `M`: 中等任务（代码变更行数 200-500，涉及文件数 5-10，新增抽象数 1-3）
> - `L`: 大任务（代码变更行数 500-1000，涉及文件数 10-20，新增抽象数 3-5）
> - `XL`: 超大任务（代码变更行数 > 1000，涉及文件数 > 20，新增抽象数 > 5）
> - `XXL`: 特大任务（代码变更行数 > 3000，涉及文件数 > 50，跨多个模块的架构变更）— 适合由 AI Agent 主导执行、有完整单元测试和 UI 测试覆盖的场景
> - `XXXL`: 巨型任务（代码变更行数 > 5000，涉及文件数 > 100，系统级架构重构）— 仅适用于 AI Agent 全程执行 + 完整自动化测试套件可兜底的 yolo 场景
>
> **机械性变更降级规则**：
> 上述大小阈值衡量的是**设计/审查复杂度**，不是 diff 行数或文件数。如果绝大部分变更是纯机械操作——每处都遵循同一条可机械验证的规则、不涉及业务逻辑或设计判断——应将大小**至少降一档，必要时大幅降级**（例如：100 文件的方法重命名实际复杂度可能只是 XS/S，因为审查者抽样 3-5 处确认替换规则一致即可，不需要逐文件思考）。
>
> 典型机械性变更：
> - 重命名 public 方法 / 类 / 字段，导致全仓库 N 个调用点跟改
> - 修改某个广泛使用的函数签名（增删参数、改返回类型），所有调用点机械跟改
> - 模块拆分 / 重组，大量文件移动 + import 路径调整
> - 批量修复新增 lint 规则触发的全仓库违规（参考 PR #332）
> - 按 codemod 规则批量替换 API（旧 API → 新 API 迁移）
> - 统一 import 顺序 / 路径 / 别名
> - 目录重组、按规范批量重命名文件
> - 给已有未标注的代码批量加类型注解
>
> 判断准则：
> - 审查者是否需要逐文件思考？如果只需抽样核对"是否都按同一规则改"，就是机械性变更
> - 仍按原始复杂度计大小的部分：触发机械变更的"源头"本身（新增的 lint 规则、codemod 脚本、新 API 接口、新签名的方法声明）不参与降级

> **状态说明**：
> 状态值为 `<phase>-<phase-state>` 的组合：7 个 phase 按下表顺序线性推进；前 6 个 phase 各有 `in-progress` 和 `complete` 两个 phase-state，第 7 个 phase `merge` 只有 `merge-complete`（合并是瞬时操作，没有"进行中"的中间态——`code-review-complete` 之后下一个状态就是 `merge-complete`）。完整枚举共 14 值：`<phase>-in-progress` / `<phase>-complete` × 6 + `merge-complete` + 特殊终态 `abandoned`（任意阶段可手动写入，表示计划废弃）。该字段是机器可读的工作流门控，请勿引入此列表以外的值。
>
> | # | phase | 含义 | `in-progress` 写入时机 | `complete` 写入时机 |
> |---|-------|------|-----------------------|---------------------|
> | 1 | `create-plan` | 计划文档撰写 | `/create-plan` 启动 | 落盘等待审查 |
> | 2 | `review-plan` | 计划审查 | `/review-plan` 启动 | 审查通过（`/execute-plan` 的最低门槛） |
> | 3 | `plan-execution` | 代码生成 | `/execute-plan` 启动 | 全部步骤完成 |
> | 4 | `manual-test` | 人工手动测试 | 开发者手动 | 开发者手动 |
> | 5 | `automated-ui-test` | 自动化 UI 测试 | 开发者 / 脚本 | 开发者 / 脚本 |
> | 6 | `code-review` | PR 代码审查 | PR 开启 | 审查通过 |
> | 7 | `merge` | 合并到 main | — （无 in-progress） | 合并完成；通常由下一次 `/pr` 在 agent 确认 PR 已合并后写入（终态） |
>
> **门控规则**：
> - `/execute-plan` 仅当状态为 `review-plan-complete` 或 `plan-execution-in-progress` 时允许执行；其他状态一律拒绝
> - `pr-checklist.yml` 校验：PR 引用的计划文档必须是本 PR diff 中新增的文件，或者 main 上已存在但状态 ≤ `plan-execution-in-progress` 的文件；任何 `plan-execution-complete` 及之后的 main 端状态都视为已用，禁止复用

# 将 cmux 精简为「Bus」：删除聊天室不需要的原 cmux 包袱

> 产品更名：本 fork 的产品对外名称定为 **Bus**（取自并行编程中的 *message bus*——契合「@mention 把 prompt 发到 room、agent 的最终回复回到 room」的总线语义）。更名的**范围**是一项需要决策的事项（见决策 D1），本计划默认推荐「仅对外展示名」的最小范围。

## 当前状态分析

本仓库是 cmux（原生 macOS 终端 app）的 fork，已改造为「AI 聊天室」：侧边栏顶部是多个 chat room，底部是按 room 分组的 agent 终端 tab；`@mention` 把 prompt 发给 room 内 agent，agent 的最终回复回到该 room。目标产品 = **agent 终端 tab + 聊天室协调层**，其余皆为原 cmux 的通用终端 / 浏览器 / 云 / 移动端产品面，属于可删除的包袱。

### 必须保留的「脊柱」（执行删除时不得触碰）

这些是 agent tab、终端注入、分屏、多 tab、reload/dogfood、会话恢复的承载组件，五个探针一致要求保留：

- 终端渲染与输入：`ghostty/`、`GhosttyKit.xcframework/`、`Sources/GhosttyTerminalView.swift`、`Sources/Panels/TerminalPanel.swift`、`PanelType.terminal`（`Sources/Panels/Panel.swift:7`）
- 分屏 / 多 tab（你说的未来横竖分屏 + 多 tab——**已存在，无需新代码，只需别删**）：`vendor/bonsplit/`、`Sources/TabManager.swift`、`Sources/Workspace.swift`、`Sources/ContentView.swift`
- 终端 socket / 输入 / 事件 API：`Sources/TerminalController.swift` 的 socket/input 路径、`Packages/CmuxControlSocket`、`Packages/CmuxSocketControl`
- agent 启动 / 恢复 / hook：`Packages/CMUXAgentLaunch`、`Packages/CMUXAgentVault`、`Sources/AgentHibernation/`、CLI hook 路由（`CLI/cmux.swift` 的 claude/codex/cursor hook 路径）
- 事件管道（聊天桥依赖）：`Packages/CMUXWorkstream`、`Sources/Feed/FeedCoordinator.swift` 的 `ingestBlocking()`/`deliverReply()` 核心、`Sources/ChatRoomController.swift`
- 会话持久化：`Sources/SessionPersistence.swift`、`Sources/Workspace.swift` 的 snapshot/restore
- 聊天室三件套：`Packages/CmuxChatRoomCore`、`Packages/CmuxChatRoom`、`Packages/CmuxChatRoomUI`、`Sources/ChatRoom*.swift`
- 侧边栏 git 分支行：`Packages/CmuxGit`
- 终端查找（保留，勿与右侧栏 Find 混淆）：`SurfaceSearchOverlay`（`Sources/GhosttyTerminalView.swift` 内承载，见 CLAUDE.md「Terminal find layering contract」）、`Packages/CmuxTerminalCopyMode`、`Packages/CMUXPasteboardFidelity`
- **Markdown + Mermaid 渲染（保留——开发者用它与 agent 沟通）**：`Sources/Panels/Markdown*.swift`（全部 13 文件，含 `MarkdownPanel`/`MarkdownPanelView`/`MarkdownWebRenderer`/`MarkdownViewerAssets`/`MarkdownRemoteImageLoader` 等）、`PanelType.markdown`、`Resources/markdown-viewer/` 的**渲染资产**（`marked.min.js`/`highlight*.{js,css}`/`mermaid.min.js`/`vega*.min.js`/`github-markdown.css`/`shell.html`）。markdown 经 `WKWebView` 渲染，mermaid/vega 图表是其一部分。**注意**：markdown 依赖 `FilePreviewTextEditingPanel`（定义于 `Sources/Panels/FilePreviewTextEditor.swift`）——删 filePreview 时必须保留这个协议 seam。`MarkdownRemoteImageLoader` 是纯 HTTPS 图片取数器（SSRF 受限），与 SSH-remote 无关。
- 基础设施：`Packages/CmuxFoundation`、`Packages/CmuxProcess`、`Packages/CmuxFileWatch`、`Packages/CMUXDebugLog`、设置/快捷键/本地化（`Packages/CmuxSettings(UI)`、`Resources/Localizable.xcstrings`）

### 删除候选总表（五个探针的「加法式」合并，按置信度分级）

置信度图例：✅ 已确认可删（探针一致、独立目录、≤少量改动） · ⚠️ 需配套改动（耦合但有界） · 🔶 需产品决策（取决于决策项答案） · 🔍 删前需核实（探针存在分歧或有 caveat）

| 子系统 | 文件 / 包 | 体量 | 耦合点 / 改动 | 级别 |
|---|---|---|---|---|
| **Web 云端前后端** | `web/`（Next.js + docs + Postgres/Stack/E2B/Freestyle + `web/public` 41M） | 52 MB / ~65k LOC | app 不 import，但 ⚠️ **CI/workflow 耦合**：`ci.yml:107` web-typecheck、`:161` web-db-migrations（`working-directory: web`）、`cloud-vm-migrate.yml:28`、`cloud-vm-smoke.yml:46` 在 web 下跑、`scripts/verify-cmd-click-file-previews.sh:165` 从 `web/public` 取 fixture。→ **移至 Phase 8a**（与 Cloud/Auth 同 PR，cloud-vm workflow 本就属 auth/cloud） | ⚠️ |
| **独立工具 / 原型** | `experiments/`、`Prototypes/`、`dogfood/` | — | 未编入 app target、无 CI 引用 | ✅ |
| **diff-viewer** | `diff-viewer/` + `Resources/markdown-viewer/diff-viewer-app`（构建产物） | — | ⚠️ **非纯独立**：CI 有专用 job（`ci.yml:140` `build-diff-viewer-app.sh --check`、`:146-158` typecheck/test/lint）、`Resources/markdown-viewer/` 内嵌其构建产物——与 markdown viewer 同生命周期。→ **移至 Phase 3**（连 CI job + `scripts/build-diff-viewer-app.sh`/`check-diff-viewer-react-compiler.mjs` 一并删） | ⚠️ |
| **`design/`** | `design/`（980K） | — | 🔍 可能是 AppIcon 源——**保留待核实**，本计划不删；如核实非源再单独 verify-then-delete | 保留 |
| **扩展样例（非独立）** | `Examples/`（含 `CmuxExtensionSidebarExamples`） | — | ⚠️ 审查指正：被 `ContentView.swift:7` import + pbxproj 链接——**非独立**，随扩展平台在 **Phase 5** 删 | ⚠️ |
| **遗留 python 测试（部分）** | `tests/` 中的 feature socket 测试（被 `tests_v2/` 取代） | — | ⚠️ **不可整目录删**：`tests/` 还含**活跃 CI 守卫脚本** `tests/test_ci_*.sh/.py`（`ci.yml:26-56` 直接跑、`run-tests-v1.sh:224` 迭代 `tests/test_*.py`）——这些守的是构建/发布流水线，与被删 feature 无关。→ **从 Phase 1 移除**：仅随各 feature 删除时移走其专属 socket 测试，`test_ci_*` 基础设施守卫**全部保留** | ⚠️ |
| **AppleScript 自动化面** | `Sources/AppleScriptSupport.swift` + `Resources/cmux.sdef` + Info.plist 脚本键 | 714 LOC | ⚠️ 审查指正：**非死代码**——编入 app target（pbxproj:35/1737）、经 `.sdef` 由 ObjC runtime 实例化（无 Swift import ≠ dead）、`Info.plist:127-130` 声明。→ **Phase 1A** | ⚠️ |
| **iOS / 移动端（12 包）** | `ios/`、12 × `Packages/CmuxMobile*`、`scripts/mobile-*` | ~2.4 MB / ~20k LOC，165 文件 | app target 不 link 这 12 个包 | ✅ |
| **配对 Mac 移动主机** | `Packages/CMUXMobileCore`、`Sources/Mobile/` | ~3k LOC + 120K | **app 链接**：`TerminalController`/`AppDelegate`/`GhosttyTerminalView` 流式推送终端字节 + **`TabManager` 7 处 `MobileHostRequestActivity` 节流（审查 R1.2）** + Mobile 设置面（`MobileSection`/`iOSPairingHost`）；需先去 TabManager 节流 + 删设置面 + 抽出共享值类型再删 | ⚠️🔶 |
| **侧边栏扩展 / 自定义渲染平台** | `Packages/CmuxExtensionKit`、`CMUXExtensionHostSupport`、`CmuxSidebarProviderKit`、`CmuxSidebarInterpreterService`、`CmuxSwiftRender(UI)`、`Examples/*Sidebar*`、`Sources/CMUXSidebarExtensionBrowserPanel.swift` | ~12k LOC + 样例 | 删 `extensionSidebarScrollArea()` + 设置开关，**并须同 PR 删整条 `PanelType.extensionBrowser` panel surface（审查 R1.1/R2.2：`Panel.swift:13`/`Workspace.swift:15030`/`AppDelegate:13732`/`UpdateTitlebarAccessory:943` + 4 个 ExtensionSidebar/Browser 文件）**，否则 Phase 5 不编译；保留内置 `workspaceScrollArea()` | ⚠️🔍 |
| **应用内浏览器** | `Sources/Panels/Browser*`、`CmuxWebView*`、`Sources/Find/Browser*`、浏览器 CLI verbs、10 测试 | **~33–40k LOC，23 文件** | 删 `PanelType.browser` + ~10 处 switch（Workspace/PanelContentView/ContentView/SessionPersistence/快捷键）；浏览器是正交 Panel，**app 内最大单笔 LOC 收益** | ⚠️ |
| **Feed 面板 UI（保留管道）** | `Sources/Feed/FeedPanelView*`、`FeedPanelViewModel`、Feed 调试窗 | ~5k LOC | **保留** `FeedCoordinator` 核心 + `CMUXWorkstream`（聊天桥读原始事件）；只删面板视图 | ⚠️ |
| **非终端 Panel 类型（**markdown 除外，保留**）** | `Sources/Panels/FilePreview*`、`Project*`、`Packages/CMUXProjectModel`、`Resources/markdown-viewer/diff-viewer*` | — | 删 `PanelType.filePreview/.project` 及 Workspace 创建路径。**保留 `Markdown*`/`PanelType.markdown`/markdown 渲染资产（mermaid/vega）+ `FilePreviewTextEditingPanel` 协议（markdown 依赖）** | ⚠️ |
| **旧右侧栏工具** | `Sources/RightSidebar*`、`Sources/FileExplorer*`、`Sources/Search/`（全局搜索；browser 分支在 Phase 2 先剥）、`DockPanelView`/`DockEmptyView` | — | 右侧栏旧 modes（files/find/sessions/feed/dock）非聊天室 UI；**`Sources/Find/` 不在此列——browser-find 两文件在 Phase 2 删，终端查找三文件（`SurfaceSearchOverlay`/`TerminalSearchOverlayHostingView`/`FindTextFieldSupport`）保留** | ⚠️🔶 |
| **未用 agent 集成（hook 安装器）** | `Packages/CMUXAgentLaunch/.../{RovoDevHookConfig,HermesAgentHookConfig}.swift`、`CLI/CMUXCLI+{HermesAgentHooks,AmpExtension}.swift` **+ 各自 `AgentHookDef` 行 + install/uninstall dispatch** | — | **全有全无**（见 Phase 7）：删 config/extension 文件**必须同删** `AgentHookDef` 的 rovodev/hermes-agent/amp 行 + `cmux.swift` 的 install/uninstall dispatch（`:26241/26245/26602/26606`）+ `cmux hooks setup/uninstall <name>` 入口，否则 `cmux.swift` 引用已删符号、无法编译。**保留（非本行，勿删）**：`CMUXAgentVault/Providers/{RovoDev,HermesAgent}/*Index.swift`（会话索引）、`RestorableAgentKind`(18 cases)、`SessionAgentPresentation`/`SessionIndexStore/View` 的 rovo/hermes 分支 | ⚠️ |
| **OMP 扩展（claude wrapper？）** | `CLI/CMUXCLI+OmpExtension.swift` | — | 🔍 **冲突**：探针 1 列为可删，但设计文档 §2 称「Claude 经 OMP wrapper 运行」、本 fork claude 启动用 `bin/claude` wrapper 注入 `--session-id/--settings`——**删前必须确认 claude hook 路径不依赖 OMP** | 🔍 |
| **`cmux top` 监控** | `cmux top` 命令 / UI；`Sources/CmuxTop*` | — | 🔍 **冲突**：命令/UI 可删，但 `CmuxTopProcess*` 进程枚举被 `RestorableAgentSession` + vault scanner 复用——**只删命令/UI，保留枚举** | 🔍 |
| **`cmux claude-teams`** | claude-teams CLI | — | ⚠️ 审查指正：**不独立**——`AgentResumeArgv:46`/`RestorableAgentSession:471` 据它生成 resume/fork argv（恢复脊柱）。→ **Phase 1B / 默认保留** | ⚠️ |
| **更新 / 分发** | `Sources/Update/`、`Packages/CmuxUpdater`、`CmuxUpdaterUI`、Sparkle、`homebrew-cmux/` | ~7k LOC | `AppDelegate` 的 `UpdateActionDelegate/Host`、侧边栏 update pill | 🔶 |
| **命令面板** | `Sources/CommandPalette/`、`Native/CommandPaletteNucleoFFI`(🔍 backing 模糊搜索) | ~3k LOC | 🔶 设计 §3.3 用「命令面板 → Rename Tab」——**保留还是删是决策项** | 🔶 |
| **分析 / 崩溃** | `PostHogAnalytics.swift`、`SentryHelper.swift` + Sentry import | — | 私有 fork 是否需要遥测/崩溃上报 | 🔶 |
| **远程 SSH / 云 VM / Auth / 守护进程** | `Sources/Cloud/`、`CloudVMActionLauncher`、`Sources/Auth/`、`Packages/CMUXAuthCore`、`CmuxAuthRuntime`、`vendor/stack-auth-*`、`WorkspaceRemoteConfiguration`、`Remote*`、`WorkspaceRemoteSessionController`(~3.5k LOC in Workspace)、`daemon/`(cmuxd，与 remote 绑定) | ~6k 专属 + ~3.5k 编织进 Workspace + cmuxd | 🔶**最深耦合**：`isRemoteWorkspace` guard 遍布、PTY/RPC、会话 snapshot codec、需要 snapshot 迁移；~30–45 处改动；**放在最后做** | 🔶⚠️ |
| **WorkspaceGroup（旧分组模型）** | `WorkspaceGroup`、`groupId`、`deleteWorkspaceGroup`、ungroup/dissolve 路径 | — | 设计明确弃用 group 作为 room 模型，但仍与侧边栏排序/恢复/关闭/命令路径纠缠；**仅在 roomID 侧边栏完全稳定后删** | 🔶 |

> 体量与耦合数据来自本 fork 上五个并行只读探针（mobile / web+cloud+auth / browser+remote / feed+palette+update+extensions / 全量产品面），互相交叉印证。

### 删除顺序的指导原则（来自探针共识）

所有探针一致强调同一条安全模式，本计划据此设计 phase（实际 phase 列表见「实施步骤」，待决策后填充）：

1. **先断入口，再删实现**：先从菜单 / 命令面板 / 设置行 / socket verb 移除入口并编译通过，再删 model/storage 分支与文件。
2. **垂直切片、逐 feature 推进**：每个 feature（含其 CLI verbs、设置、测试、pbxproj 与 CI `PACKAGES=(…)` 条目）作为**一个独立 PR / phase**，phase 间用 `./scripts/reload.sh --tag prune-bus` + `xcodebuild -scheme cmux-unit` 验证。
3. **不要先动 `Workspace.swift` / `TabManager.swift` / `TerminalController.swift` 的内部**：很多被删 feature 硬接在这里，先让旧分支不可达，最后再收缩这三个文件。
4. **`WorkspaceGroup` 与内部 `cmux→bus` 全量重命名留到最后**（前者待 roomID 侧边栏稳定，后者见 D1）。

### 删除方法：架构决策手写、二级清理靠工具发现（开发者指定，2026-06-08）

本计划**不**逐一手写每个 feature 的全部 stranded Swift caller / helper 文件。每个 phase 的工作是：**①** 删 feature 的主体文件 + 移除其入口（菜单/命令面板/socket verb/CLI/PanelType），把对已删类型的 live 引用清到**编译通过**；**②** 编译通过后，对本 phase 触及的范围跑 **Periphery**（scoped），人工核对归属，把确认为「仅服务本 feature、现已无引用」的声明/文件**在同一 PR**删掉。

**三类工具各司其职（决定哪些细节可省、哪些必须手写）**：
- **编译器**（gate G ③④ `xcodebuild cmux` + `cmux-unit`）捕获**对已删符号的 live 引用**——这是历轮 review 绝大多数 blocker 的真身（`MinimalModeSidebarControls`→`CmuxExtensionSidebarSelection`、`right_sidebar` CLI/socket→`RightSidebarRemoteRequest` 等）。Periphery **不**报这类（它们是被引用的，不是 dead）。**故本计划各 phase 里逐条列出的 Swift caller 锚点是「示例性」的——以编译器为准，不必穷举。**
- **Periphery**（gate G 新增 ⑦）捕获**移除入口后变成 transitively-dead 的代码**（只被已删 feature 用的 helper struct/view/文件，如 `SidebarWorkspaceGroup*`、孤立 automation 类型）——这是工具相对手写清单的**净增价值**，无需手列。
- **编译器与 Periphery 都看不见的层 → 必须在计划里保持显式手写**：shell/release 脚本（如 Sparkle `sign-cmux-bundle.sh` 调用）、`tests_v2/*.py`、CI workflow 路径触发、字符串字面量引用（`web/data/*.schema.json` URL）、运行时 session-snapshot 解码（**Phase 0 drop-set**）。这些 phase 的细节**不**降级。

**两条硬护栏（不可放宽）**：
1. **Periphery 只 scoped 到本 phase 触及范围 + 人工核对归属，绝不 repo-wide**。半精简的仓库里 Periphery 会把「仅因后续 phase 未跑而暂时无引用」的代码全报成 dead，盲删会越界扩大范围。
2. **Periphery 对动态派发有假阳性，本仓库有真实地雷**：它看不见 `@objc`/Obj-C runtime/反射/`NSClassFromString`/IBAction/**sdef 实例化**的代码。典型：`AppleScriptSupport.swift` 无 Swift 引用、仅经 `cmux.sdef` 由 Obj-C runtime 实例化——Periphery 会判它 dead，盲删即杀掉 AppleScript 自动化。**删前人工核对归属是强制项**；Periphery 跑用 `--retain-objc-accessible` 等保留 + 对 sdef/IBAction 显式 retain。

**保持完全显式（工具找不到/保护不了）**：**Phase 0 迁移 drop-set**、**非-Swift 消费者**（脚本/CI/release/`tests_v2`/schema 迁移/docs topic）、**保留例外**（markdown+mermaid、终端查找、markdown 依赖的 `FilePreviewTextEditingPanel` seam）。

## 参考资料

> **重要**：
> - 使用 **context7** 获取文档和参考资料
> - 如果 **context7** 没有相关文档，必须在此部分提供文档链接
> - 如果任务需要使用现有服务，应包含该服务的 README 文件路径
> - 如果任务涉及第三方 SDK，应包含以下链接：
>   - SDK 集成文档
>   - 如何启用 XX 功能的文档
> - 必须包含 `guides/encyclopedia.md`，并在创建计划时先使用该文件查找相关指南与文档
> - 必须包含 `guides/naming-guide.md`，确保新增的模块、文件、类、函数命名符合项目规范
> - 如果计划包含单元测试，必须包含 `unit-test/docs/how_to_write_stable_unit_test.md`
> - 如果计划涉及日志输出或运行时断言检测，必须包含 `shared-services/logger-service/docs/how_to.md`
> - 如果此任务基于另一个任务，或未来任务依赖此任务，应包含相关任务计划文档的路径
> - 如果找不到或未提供所有相关文档，AI 应停止计划生成并通知开发者

**说明**：模板「重要」块中的 `unit-test/docs/...`、`shared-services/...` 路径源自模板原始仓库（canvas-editor），本仓库无对应；但 **`guides/` 目录现已存在**（审查指正，原稿误称不存在），执行前必须先读。本仓库约束性文档：

- **`guides/encyclopedia.md`**、**`guides/code-review-guide.md`**、**`guides/dictionary.md`**（现存于仓库根 `guides/`，先读）；其余 `guides/*-guide.md` 多为 Kotlin/Android 模式指南，与本 Swift 仓库不直接相关，按需取用。
- **`CLAUDE.md`**（约束性，先读）：包架构（DAG、Coordinator/Service/Repository、依赖倒置）、Swift 6 并发原语、一类型一文件、本地化审计、**测试需写入 `project.pbxproj`**、`scripts/normalize-pbxproj.py` + `scripts/check-pbxproj.sh`、socket 线程/焦点策略、`reload.sh --tag` 构建流程、**Terminal find layering contract**、**测试质量政策**（禁源码文本断言）。
- **原始设计文档**：`plans/2026-06-06-cmux-ai-chat-room-design.md`（路径已随移动更新；§2 标注「Claude 经 OMP wrapper」是**过时描述**——本 fork Claude 实际经 `bin/claude` wrapper 启动，见 `Sources/TabManager+ChatRoom.swift:170`，OMP 是独立未用 agent，见 `Sources/VaultAgentRegistry.swift:129`）。
- **关键源文件锚点**：`Sources/Panels/Panel.swift:6/272`（`PanelType` 是**运行时枚举**，经 `Panel.panelType` 暴露，遍布渲染/焦点/路由/命令面板/socket 解析 switch——**不可**塞迁移用的 `.unknown`）；`Sources/SessionPersistence.swift:1694`（真实持久化模型是 `SessionPanelSnapshot`，非 `SessionTerminalPanelSnapshot`）；`Sources/Workspace.swift:266`（`restoreSessionSnapshot` 用 layout panel id 重建分屏——丢 panel 必须同步清理 layout/focus/selected id）；`cmux.xcodeproj/project.pbxproj`、CI `.github/workflows/{ci,test-ios}.yml`（删包/删 ios 必须同步）。
- **更名参考**：产品名 **Bus** = 并行编程 message bus 语义；无外部 SDK。Sparkle（`Packages/CmuxUpdater`）若保留则更名需同步 appcast/displayName。
- **死代码工具**：**Periphery**（https://github.com/peripheryapp/periphery）——Swift 未引用代码扫描，支持 macOS Xcode project。用法见「删除方法：架构决策手写、二级清理靠工具发现」节与 gate G ⑦。**仅作每 phase 垂直切片后的 scoped 清理，非 repo-wide 强制**；对 `@objc`/反射/sdef/IBAction 有假阳性，删前人工核对归属。

## 需要决策的事项

列出所有未解决的选择项和问题，并提供推荐选项。在开发者解决这些事项之前，不要执行计划。

**当前计划完整程度**：90%

> **注意**：初始生成计划时，此完整程度应留空。随着开发者做出更多决策，AI 应更新此百分比。

> **重要**：
> - 只有当计划完整程度达到或超过 95%（AI 有 95%+ 把握能完成任务）时，开发者才可以执行计划
> - 任何不清楚、缺失或可以用不同解决方案实现的事项都应列在此部分
> - AI 不应猜测，应在计划执行前始终询问相关信息
> - 如果 AI 无法推断出可用选项，可以提出开放性问题
> - 每个决策项可以有多个选项（不限于两个），根据实际情况列出所有可行的选择
> - 每个选项的描述应列出优缺点（pros and cons）
> - 在做出大的方向性决策后，AI 应继续提出后续问题并更新此部分
> - 开发者做出决策后，应更新此完整程度百分比。

_（空）本计划 D1–D10 已全部决策并归档于下方「已归档的决策」（含 D8 探针默认判定、D4/D7 默认删除、D10 AppleScript 默认）。**无任何待决项。**_

> **关于 90% 与 ≥95% 执行门槛（审查指出的表面矛盾，此处澄清，非待决项）**：90% **不是**因为还有开放决策，而是因为「需要修改/添加的文件」的复选框尚未被开发者逐项勾选——按「计划生成规则」，完整程度达 100% 需「无开放决策 **且** 所有文件复选框已勾选」。当前状态 `review-plan-in-progress`，本就**不应**执行（<95% 即此意）；勾选文件 + 跑通 Phase -1 回归后，由人工 `/review-plan` 决定是否升至 ≥95% 并置 `review-plan-complete`。

## 已归档的决策

记录在实施过程中已做出的决策，包括提供给用户的选项（简短描述）和用户的选择。

> 决策方法：开发者给出 D1–D8 的初步字母答案后，启动**四路独立审查 agent**对每个决策再评估；下方为 best-of-N 收敛结论（四路一致 = A across D1–D7、D8 留作探针），并吸收四路一致提出的**排序 / 拆分细化**。

1. **产品命名**
   - **已选择**：新名 **Bus**（取自并行编程 *message bus*）。

2. **删除候选的「零风险 Tier-1」基线**（探针一致、独立目录、不被 app target 链接）
   - **已选择**：Phase 1 直接删（**审查修正后**，仅真正独立项）：`ios/`、12 × `Packages/CmuxMobile*`（不含 `CMUXMobileCore`）、`experiments/`、`Prototypes/`、`dogfood/`、`scripts/mobile-*`。**移出 Phase 1**：`Examples/`→Phase 5（被 ContentView import）、`AppleScriptSupport.swift`→Phase 1A（pbxproj 链接 + 活跃 sdef）、`cmux claude-teams`→Phase 1B/保留（接在 resume/fork argv 脊柱上）、`web/`→Phase 8a（CI web job + cloud-vm workflow + fixture 脚本耦合）、`diff-viewer/`→Phase 3（CI job + markdown-viewer 内嵌产物）、`tests/`→不整删（含活跃 `test_ci_*` CI 守卫，仅按 feature 移走专属 socket 测试）。

3. **不先删的内部**
   - **已选择**：晚删——先断入口编译通过，待 roomID 侧边栏稳定后再收缩 `WorkspaceGroup` 与 `Workspace`/`TabManager`/`TerminalController` 内部。

4. **D1 — 「Bus」更名范围**
   - **选项**：A 仅对外展示名 / B 中等（含 bundle id） / C 完整内部重命名
   - **已选择**：**A**，附四路一致的硬约束：(a) **`cmux` CLI 二进制名绝对不可改**——agent 经 `cmux hooks <agent>` shell-out、`bin/claude`/`bin/codex` wrapper 与 `CMUX_*` 环境变量全部以它为键，改名静默破坏所有 hook；(b) 内部 CLI/env/socket/bundle-id/包名/脚本/debug-tag 全部保留 cmux；(c) **更名放最后一个 phase（Phase 9）**，不放 Phase 0——否则给即将删除的 About/README/strings 白白重命名；(d) 可选后续：薄 `bus` CLI alias 转发到 `cmux`，但现在不改协议/env。选项 C（完整内部重命名）另开独立 XXXL 计划。

5. **D2 — 远程 SSH / 云 VM / Auth / cmuxd**
   - **选项**：A 全删 / B 保留 SSH 仅删 cloud+auth
   - **已选择**：**A，但拆 3 步且最后做**：① 先删 cloud/auth/`vendor/stack-auth-*`；② 再删 remote SSH（含会话 snapshot 迁移）；③ 最后删 `cmuxd`（先证其 remote-only、不承载本地运行/打包）。已核实 `cmuxd`+`Remote*` 仅被 `Workspace.swift`/`WorkspaceRemoteConfiguration.swift`/SSH builder 引用，**不**被 `SessionPersistence`/`AgentHibernation` 引用——本地持久化不受影响。**前置**：先以独立 commit 落地宽松会话解码器并用真实旧 `session-*.json` 回归（见 D8 前置 commit）。

6. **D3 — 配对 Mac 移动主机**
   - **选项**：A 删 / B 保留
   - **已选择**：**A，拆 2 步**：Phase 1 删零风险部分（`ios/`、12 个 `CmuxMobile*` 包、`scripts/mobile-*`）；后续独立 phase 把 `GhosttyTerminalView`/`TerminalController` 仍需的小型终端 DTO/流式类型**抽到非移动包**（不把 `CMUXMobileCore` 留作 "shared core"），再删 `CMUXMobileCore`+`Sources/Mobile/`。**caveat**：byte-tee 在打字延迟热路径（CLAUDE.md），删除应只**减**负载，需 diff 确认无渲染网格帧依赖该 tee。

7. **D4 — 更新 / Sparkle 分发**
   - **选项**：A 删 / B 保留
   - **已选择**：**A（删 `Sources/Update/`+`CmuxUpdater(UI)`+`homebrew-cmux/`），但低优先**：它隔离、不挡路，放后期或随手做，不占早期 phase。`reload.sh --tag` dogfood 链路保持不动。**条件**：若可能很快把 Bus 分发给他人则改为保留。

8. **D5 — 命令面板**
   - **选项**：A 保留 / B 删
   - **已选择**：**A（保留），并随各删除 phase 同步清理命令目录**——移除指向已删面（browser/updater/mobile/右侧栏工具/project/filePreview/remote/扩展侧边栏）的命令条目，而非单列一步。

9. **D6 — 旧右侧栏 + 非终端 Panel**
   - **选项**：A 删（保留终端查找）/ B 仅删 Feed UI
   - **已选择**：**A，拆 2 phase**：① 先删非终端 Panel（browser/filePreview/project）；② 再删旧右侧栏 modes（files/find/sessions/feed/dock）。**保留** `SurfaceSearchOverlay`（终端查找，勿与右侧栏全局 Find 混淆）与 `FeedCoordinator`+`CMUXWorkstream` 管道，只删 `FeedPanelView*`。
   - **补充决策（开发者指定，2026-06-08）**：**markdown + mermaid 渲染保留**——开发者用 markdown/mermaid 与 agent 沟通。`PanelType.markdown` + `Sources/Panels/Markdown*.swift` + `Resources/markdown-viewer/` 渲染资产不删；删 filePreview 时保留 `FilePreviewTextEditingPanel` 协议 seam。markdown 不进 Phase 0 drop 集（旧 markdown 快照须正常恢复）。

10. **D7 — 分析 / 崩溃上报**
    - **选项**：A 删 PostHog+Sentry / B 保留 Sentry
    - **已选择**：**A（删两者），保留 `CMUXDebugLog`**（dogfood 确定性本地日志 > 远程遥测）。日后 Bus 对外分发再考虑重加崩溃上报。

11. **D9 — Feed 管道 vs Feed UI**（审查新增）
    - **选项**：连管道一起删 / 只删 UI 保留管道
    - **已选择**：**只删 Feed 面板 UI**；保留 `CMUXWorkstream` + 最小 `FeedCoordinator` ingestion/reply 管道，直到聊天室回复路由完全独立——避免误删聊天室仍依赖的 hook 事件路径。

12. **D8 — 删前硬核实（已由代码审查核实，转为 Phase 内具体动作）**
    - **a（OMP）— 已解决：可删**。审查核实：本 fork Claude 经 `bin/claude` wrapper 启动（`Sources/TabManager+ChatRoom.swift:170-179`），OMP 是独立未用 agent（`Sources/VaultAgentRegistry.swift:129`，id `omp`），Claude hook 路径不依赖 `CMUXCLI+OmpExtension.swift`。→ Phase 7 删 OMP 扩展，并同 PR 修正 `Packages/CmuxChatRoomCore/.../AgentKind.swift:3` 过时注释「via the OMP wrapper」。
    - **b（CmuxTop）— 已解决：split 须文件级显式**。审查核实 `CmuxTopProcess*` 被 `RestorableAgentSession.swift`、`VaultAgentProcessScanner.swift`、`Sources/App/AgentHibernationController.swift` 复用。→ Phase 7 **删除集** = `cmux top` 命令 + 其 UI；**保留集** = `CmuxTopProcess*.swift`、`CmuxTopSnapshot*.swift`、`TerminalControllerTopSupport.swift`（见 Phase 7 文件清单）。
    - **c（SwiftRender/SidebarProvider）— 已解决：seam 已定位**。审查核实 `CmuxSwiftRenderUI` 只喂 `extensionSidebarScrollArea()`（`ContentView.swift:11220`），不喂聊天侧边栏 `workspaceScrollArea()`（`:11056`），二者在 `:10960-10962` 切换。→ Phase 5 删 `extensionSidebarScrollArea()` + provider 切换开关 + `Sources/CmuxSidebarActionDispatch.swift`，**保留** `workspaceScrollArea()`。
    - **D4 / D7 默认**：均按 A **删除**（私有 dogfood，无近期对外分发）；审查指出二者是**活跃链接系统**（非"随手 commit"），故各给**独立 phase**（Phase 11 更新器/分发、Phase 12 遥测/崩溃），含 app 文件 + workflow + pbxproj + 本地化全面清理；若日后分发，按归档备注回滚。

13. **D10 — AppleScript 删除默认（审查指出 Phase 1A 内嵌运行时决策，此处定默认）**
    - **选项**：删 / 保留（取决于是否有外部脚本依赖本 app 自动化）
    - **已选择**：**默认删除**（私有 fork，无已知外部 AppleScript 依赖）。Phase 1A 执行时若实际发现外部依赖，则就地改保留——此为执行期事实核查，非开放决策。

## 功能控制/实验（如适用）

N/A — 本计划为删除 / 重构，不引入用户可见的 A/B 实验，无 feature flag。

## 需要修改/添加的文件

> **重要**：
> - 开发者必须审查所有新增和修改的文件
> - 当引入新的类、文件、函数或结构时，包含简洁的**高级概念代码片段**：
> - 显示高级概念，包括公共类型、方法签名和结构信息
> - **不要在代码片段中包含 import 语句**——import 是实现细节，不传达设计意图
> - 对于关键的实现细节，可以添加代码片段，但不需要完整实现
> - 除了代码片段，也可以在代码中使用注释来说明需要在何处添加或修改什么内容
> - 使用 mindpilot MCP 绘制图表，描述新组件和服务如何融入现有架构
> - 此部分应详尽，应包含所有将被添加或修改的文件。
> - 应包含文件路径
> - **注意**：开发者应在审查每个文件时勾选对应的复选框
> - **例外**：以下类型的文件无需在此部分列出，可直接修改：
>   - Gradle 配置文件（如 `build.gradle.kts`、`settings.gradle.kts`、`gradle.properties` 等）
>   - Swift 包管理文件（如 `Package.swift`）
>   - 项目配置文件（如 `.xcodeproj`、`.xcworkspace`、`Info.plist`、`.idea` 配置等）
>   - 文档文件（如 `.md`、`.txt`、`.rst` 等）
>   - Python 包标识文件（`__init__.py`）
>   - 仅涉及 import 语句变更的文件（如新增/修改 import 行）

> 约定：本计划绝大多数变更是**删除整目录/整文件**（纯机械、审查时抽样核对 import/引用已清零即可）。按模板「例外」条款，`project.pbxproj`、`Package.swift`、`*.xcconfig`、`Info.plist`、CI yml、纯 import 行变更**不在此逐一列出**，但每个 phase 都隐含「同步 `cmux.xcodeproj/project.pbxproj` 包/target/Frameworks 引用 + CI `.github/workflows/ci.yml` 的 `PACKAGES=(…)`，并跑 `scripts/normalize-pbxproj.py` / `scripts/check-pbxproj.sh`」。删除文件用 🗑️ 标注、修改文件给出**移除的符号**（删除无需高层片段）、新增代码给出高层片段。

> **审查修正（重要）**：原稿在**运行时枚举** `PanelType`（`Sources/Panels/Panel.swift:6`，经 `Panel.panelType` 暴露给渲染/焦点/路由/命令面板/socket 解析）上加 `.unknown`，会把迁移用的「不可能态」泄漏进活跃 UI。**改为：宽松解码完全发生在持久化边界，绝不进入 `PanelType` 运行时枚举。** 真实模型是 `SessionPanelSnapshot`（非 `SessionTerminalPanelSnapshot`）。且 `restoreSessionSnapshot` 用 layout panel id 重建分屏（`Sources/Workspace.swift:266`）——丢 panel 必须同步净化 layout / `focusedPanelId` / selected id，否则旧会话会恢复成空白 pane、坏分屏、丢失焦点 tab。

### Phase -1 — 前提回归门控（不删任何东西；先证脊柱可用）

- [ ] **（运行验证，非文件改动）** 起 tagged app，新建 room + 一个 claude + 一个 codex agent，`@all` 发 prompt，确认**两者最终回复都回到 room channel**（非 `0 / N replied`）、终端查找可用；退出重开确认 room/agent 恢复、claude 恢复为已 resume 会话。**全绿才允许进入 Phase 0**——此前的 dogfood 显示回复路由曾失败，而后续每个 phase 都以「回复仍正常」为门控。

### Phase 0 — 安全网（持久化边界宽松解码 + 恢复契约；唯一含新代码的 phase）

- [ ] **新增**：`Sources/SessionPanelSnapshotLenientDecoding.swift`（或就近置于 `SessionPersistence.swift`）—— **仅在持久化层**对 `SessionPanelSnapshot` 用私有「raw kind」字符串解码：遇已删类型字符串（`browser`/`filepreview`/`project`/`rightSidebarTool`/`extensionBrowser`/remote）时**丢弃该 panel**并记 debug 日志，不抛错、不引入运行时 `PanelType.unknown`。**`markdown` 不在 drop 集——markdown 渲染保留**（见脊柱），旧 markdown 快照须正常恢复。**已删 PanelType 全清单（删它的 phase）**：`browser`(P2)、`filePreview`/`project`(P3——**`markdown` 保留**)、`rightSidebarTool`(P4，审查 R2.1——持久化于 `SessionPersistence.swift:1712`/`Panel.swift:11`/`Workspace.swift:668`)、`extensionBrowser`(P5，审查 R2.2——`Panel.swift:13`/`Workspace.swift:15030`)、remote 字段(P8b)。**每删一个 PanelType，其 raw 字符串必须在此 drop 集合中，且 fixture 覆盖；保留的 `markdown` 反之须有「正常恢复」回归。****逐元素捕获粒度（审查 F3）**：`PanelType` 解码本身会 throw（`Panel.swift:30`），故必须从 unkeyed container **逐个 panel** decode、单个 throw 只跳过该 panel，**不可**整数组一次性 decode（否则一个坏 panel 拖垮整个 workspace）。注意：throw 只在对应 enum case 被实际删除后（Phase 2/3/8b）才发生，Phase 0 先把容错装好。
  ```swift
  // 持久化层私有；不污染运行时 PanelType
  extension SessionWorkspaceSnapshot {
      // 逐元素：var c = try container.nestedUnkeyedContainer(forKey: .panels)
      //   while !c.isAtEnd { do { panels.append(try c.decode(SessionPanelSnapshot.self)) }
      //                      catch { _ = try? c.decode(Discard.self); cmuxDebugLog(...) } }
      // 返回 survivingPanelIds 供下方 layout 净化
  }
  ```
- [ ] **修改**：`Sources/Workspace.swift` 的 `restoreSessionSnapshot(_:)`（`:266`）—— **恢复契约**：以幸存 panel id 净化 layout（删除指向已丢 panel 的 leaf、坍缩单边分屏）、把 `focusedPanelId` / selected panel id 重映射或清空到幸存集合；定义兜底——pane 丢光所有 panel → 移除该 pane；workspace 丢光所有 panel → 该 workspace 回退为一个新建空终端（不留空白窗）。
- [ ] **（探针，无文件改动）** 复核 D8 a/b/c 的代码锚点（已在「已归档的决策 / D8」记录）：OMP `bin/claude` vs `VaultAgentRegistry:129`、`CmuxTopProcess*` 复用方、`extensionSidebarScrollArea` vs `workspaceScrollArea`。

### Phase 1 — 真正独立、不被 app target 链接的目录删除

> 审查修正：原稿把 `Examples/`、`AppleScriptSupport.swift`、`claude-teams` 误列为零风险——它们**都被保留代码链接/依赖**，已从本 phase 移出（见下）。

- [ ] 🗑️ `ios/`、`experiments/`、`Prototypes/`、`dogfood/`、`scripts/mobile-*`
- [ ] **不在本 phase 删（审查指出 CI 耦合）**：
  - `web/` → **移至 Phase 8a**：CI 有 web-typecheck/web-db-migrations job + cloud-vm workflow 在 `web/` 下跑 + 本地 fixture 脚本读 `web/public`，须与 Cloud/Auth 同 PR 清理。
  - `diff-viewer/` → **移至 Phase 3**：CI 有专用 job（`ci.yml:140-158`）、`Resources/markdown-viewer/diff-viewer-app` 内嵌其产物，须与 markdown viewer + CI job 同删。
  - `tests/`（整目录）→ **不删**：含活跃 CI 守卫 `tests/test_ci_*.sh/.py`（`ci.yml:26-56`/`run-tests-v1.sh:224`）；仅随各 feature 删除时移走其专属 socket 测试，`test_ci_*` 守卫保留。
- [ ] 🗑️ 12 个 iOS-only 包：`Packages/CmuxMobile{Camera,Diagnostics,PairedMac,RPC,Shell,ShellModel,ShellUI,Support,Terminal,TerminalKit,Transport,Workspace}`（app target 不 link；**保留** `CMUXMobileCore` 至 Phase 6）
- [ ] **修改/删除**：`.github/workflows/test-ios.yml`（`paths:` 监听 `ios/**`/`CMUXMobileCore/**`/`CMUXAuthCore/**`，`:7`）**和** `.github/workflows/ios-testflight.yml`（`:13` 触发于 `ios/**`、`Packages/**`，`:188` 调 `./ios/scripts/upload-testflight.sh`，审查指出）——删 `ios/`/mobile 包后二者失参；**与删除同 PR**删除或 no-op，避免 scheduled/manual/main CI 红。
- [ ] **不在本 phase 删（审查指出耦合，已移走）**：
  - `Examples/` → **移至 Phase 5**：`Sources/ContentView.swift:7` `import CmuxExtensionSidebarExamples`，pbxproj 链接它（9 处）；现在删会编译失败。
  - `Sources/AppleScriptSupport.swift` → **移至新增的 Phase 1A**：它**非死代码**，已编入 app target（`project.pbxproj:35/2490`），且 app 经 `Resources/cmux.sdef` + `Info.plist` `NSAppleScriptEnabled`/`OSAScriptingDefinition`（`:127/129`）声明 AppleScript 自动化。
  - `cmux claude-teams` → **移至新增的 Phase 1B / 或保留**：它**不孤立**——`Packages/CMUXAgentLaunch/.../AgentResumeArgv.swift:46` 与 `Sources/RestorableAgentSession.swift:471` 据 `claude-teams`/`codex-teams` 生成 **resume/fork argv**（属保留的会话恢复脊柱）。

### Phase 1A — AppleScript 自动化面删除（审查新增；含用户可见行为变更）

- [ ] **决策确认（手动）(需要手动操作)**：确认无外部脚本/工作流依赖本 app 的 AppleScript 自动化；若有则保留本 phase。
- [ ] 🗑️ `Sources/AppleScriptSupport.swift`、`Resources/cmux.sdef`；**修改** `Resources/Info.plist` 删 `NSAppleScriptEnabled`/`OSAScriptingDefinition` 键（按例外条款可直接改）；删 `Resources/Localizable.xcstrings` 中 AppleScript 相关字符串、对应 docs/tests；同步 pbxproj 的 source/resource 条目。

### Phase 1B — `claude-teams`/`codex-teams` 退役（审查新增；**默认不做**，需迁移恢复路径）

- [ ] **默认：保留**——teams wrapper 接在会话 resume/fork argv 上，贸然删会破坏保留的恢复脊柱。仅当确需退役时，本 phase 一并迁移 `AgentLaunchSanitizer`、`AgentResumeArgv.swift`、`RestorableAgentSession.swift:471`、相关测试与**已存旧会话兼容**后再删 CLI 子命令。

### Phase 2 — 应用内浏览器垂直切片（app 内最大 LOC 收益）

- [ ] 🗑️ `Sources/Panels/Browser*.swift`（~23 文件：BrowserPanel(+View/+扩展)、BrowserWindow*、BrowserScreenshot*、BrowserOmnibar*、BrowserWebAuthn*、BrowserAutomation、BrowserMedia*、BrowserHidden*、BrowserChrome*）、`Sources/Panels/CmuxWebView*.swift`、`Sources/BrowserPaneDropTargetView.swift`、`Sources/Find/Browser{SearchOverlay,FindJavaScript}.swift`（**仅这两个 browser-find 文件**——`Sources/Find/` 其余三个是终端查找，保留至 Phase 4 仍不删，见下）、`cmuxTests/Browser*Tests.swift`、`cmuxUITests/Browser*.swift`、`tests/` 中 browser 专属 socket 测试（feature 专属，随浏览器删；非 `test_ci_*` 守卫）、**`tests_v2/` 的 browser 套件（审查 R2.2：`scripts/run-tests-v2.sh:224` glob 全部 `test_*.py`，留则全量 v2 永久红）——`tests_v2/test_browser_*.py`、`test_cli_browser_*.py`、`test_ssh_remote_browser_*.py`（browser-over-remote，浏览器删后即失效）**
- [ ] **修改（审查指出：删 BrowserPanel 会断 Phase 2 编译，须同 PR 清理引用 BrowserPanel 的全局搜索/查找支持）**：
  - `Sources/Search/GlobalSearchCoordinator.swift`（`:104` `captureBrowserPanel`）、`Sources/Search/GlobalSearchPanelCaptureManager.swift`（`:39/:44/:204` `as? BrowserPanel`/`captureBrowserPanel`/`indexBrowserPanel`）、`Sources/Search/AppDelegate+GlobalSearch.swift`（`:186/:194` `browserPanel(for:)`/`applyBrowserInlineSearch`）—— **剥除 browser 分支**使其在 BrowserPanel 删除后仍编译（`Sources/Search/` 整体在 Phase 4 删，但本 phase 必须先去 browser 耦合）。
  - `Sources/Find/FindTextFieldSupport.swift`（`:104` `workspace.browserPanel(for:)?.searchState` fallback）—— 仅删 browser fallback 分支，**保留**该文件（终端查找依赖它，见 Phase 4）。
- [ ] **修改**：`Sources/Panels/Panel.swift` — 移除 `PanelType.browser`（line 8）与 `PanelFocusIntent.browser(BrowserPanelFocusIntent)`（line 72）
- [ ] **修改**：`Sources/Workspace.swift` — 删 `newBrowserSurface()`/`newBrowserSplit()`/`configureBrowserPanel()`；移除 `createPanel()`/`sessionSnapshot()`/`surfaceKind(for:)` 中的 `case .browser:`（5 处）；`remoteProxyEndpoint`（浏览器专用）标记延至 Phase 8 删（remote 一并）
- [ ] **修改**：`Sources/Panels/PanelContentView.swift` — 移除 browser 视图分支
- [ ] **修改**：`Sources/ContentView.swift` — 移除 `palette.newBrowserTab` 命令注册、`case let browser as BrowserPanel:` 焦点路由、browser omnibar/devtools 观察
- [ ] **修改**：`Sources/KeyboardShortcutContext.swift` — 删 `shortcutEventBrowserPanel()`/`shortcutFocusedBrowserPanel()` 及 browser 专属快捷键
- [ ] **修改**：`Sources/SessionPersistence.swift` — 删 `SessionBrowserPanelSnapshot` 结构与 panel snapshot 的 `browser` 字段（Phase 0 解码器已兜底旧快照）
- [ ] **修改**：`Sources/TabManager.swift` — 移除 tab snapshot 的 browser kind 与 loading/title/favicon/muted 更新
- [ ] **修改（审查 R1.1：`browser.profiles.*`/`browser.import.cookies` 的 backing `BrowserProfileAutomation`/`BrowserImportAutomation` 在 `Sources/Panels/BrowserAutomation.swift:183`，本 phase 随 `Browser*` 删除——故这两组 verb 必须在 Phase 2 一起删，不可留至 Phase 8a，否则删 backing 文件后 `TerminalController` 引用已删类型、Phase 2 不编译）**：
  - `Sources/TerminalController.swift`：删 `browser.profiles.{list,create,rename,clear,delete}` + `browser.import.cookies` 的注册（`:897-902`）+ dispatch（`:1048+`，经 `BrowserProfileAutomation`/`BrowserImportAutomation`）
  - `CLI/cmux.swift`：移除 browser 相关 socket verbs 与 automation 命令、`browser.profiles.*`/`browser.import.cookies` CLI 子命令、browser 设置/help 别名 + 本地化
- [ ] **修改**：`Sources/AppDelegate.swift`、`Sources/AppDelegate+ClosedItemHistory.swift`、`Sources/AppDelegate+MoveTabToNewWorkspace.swift` — 移除 "New Browser Tab" 菜单、browser 的 closed-history / move-to-workspace 分支

### Phase 3 — 其余非终端 Panel 类型（D6①）

> **保留 Markdown + Mermaid（开发者用于与 agent 沟通）**：本 phase **不删** `Sources/Panels/Markdown*.swift`（含 `MarkdownRemoteImageLoader.swift`）、`PanelType.markdown`、`Resources/markdown-viewer/` 的渲染资产（`marked`/`highlight`/`mermaid`/`vega`/`github-markdown.css`/`shell.html`）。R2.3 的 Phase 3/8b 双重归属随 markdown 保留而消失（两边都不删它）。
- [ ] 🗑️ `Sources/Panels/FilePreview*.swift`（**保留 `Sources/Panels/FilePreviewTextEditor.swift` 的 `FilePreviewTextEditingPanel` 协议——`MarkdownPanel` 仍 conform 它；删 filePreview 其余文件时把该协议 seam 留下，或下沉到 markdown 自有文件**）、`Sources/Panels/Project*.swift`、`Packages/CMUXProjectModel`
- [ ] 🗑️ **仅 `Resources/markdown-viewer/` 的 diff-viewer 子目录**：`Resources/markdown-viewer/diff-viewer/`、`Resources/markdown-viewer/diff-viewer-app/`（**不删**同目录的 markdown 渲染资产）；先确认 `shell.html` 不引用 diff-viewer 子目录（已核实 `Markdown*.swift` 无 diff-viewer 引用）
- [ ] 🗑️ **`diff-viewer/`（从 Phase 1 移入——与 markdown viewer 同生命周期、有专用 CI）**：删 `diff-viewer/` 目录 + `scripts/build-diff-viewer-app.sh`、`scripts/check-diff-viewer-react-compiler.mjs`、`scripts/open-diff-viewer-stress-samples.sh`；**同 PR 删 CI 的 diff-viewer job**（`.github/workflows/ci.yml:139-159` 的 build/typecheck/test/lint 步骤），否则 CI 指向已删目录而红。
- [ ] **修改 — diff-viewer CLI/runtime（审查指出：删资产却留服务这些资产的 CLI 命令，会指向已删文件）**：`CLI/cmux.swift:2991` 删 `diff-viewer-server` 命令分发 + `runDiffViewerServerCommand`；`CLI/cmux_open.swift` 删 `cmux-diff-viewer` scheme/HTTP server/asset 服务（`:310-311/:385+`、`:4149` 服务、`:5581` 拷贝 `markdown-viewer/diff-viewer`/`diff-viewer-app`）及 `CMUXDiffViewerLocalization` 串；删 diff-viewer 相关快捷键/设置/测试引用。
- [ ] **修改**：`Sources/Panels/Panel.swift` — 移除 `PanelType.{filePreview,project}`（line 10/12）与对应 `PanelFocusIntent.{filePreview,project}`（line 73/74）。**保留 `PanelType.markdown`（line 9）**
- [ ] **修改**：`Sources/Workspace.swift` — 移除这三类的创建路径与 `createPanel()`/`sessionSnapshot()` 中的 `case`
- [ ] **修改**：`Sources/Panels/PanelContentView.swift`、`Sources/ContentView.swift`、`Sources/KeyboardShortcutContext.swift`、`Sources/SessionPersistence.swift` — 移除 **filePreview/project 两类** panel 的视图分支、命令、快捷键、snapshot 字段（**保留 markdown 的视图分支/命令/snapshot**）
- [ ] **修改**：`Sources/CommandPalette/*`（随手清理，D5）— 删 project/filePreview 命令条目（**保留 markdown 命令**）

### Phase 4 — 旧右侧栏 modes（D6②）+ Feed 面板 UI（D9）

- [ ] 🗑️ `Sources/RightSidebar*.swift`（**含 `RightSidebarRemoteCommand.swift`——本 phase 拥有，已从 Phase 8b 移除以消除归属冲突**）、`Sources/FileExplorer*.swift`、`Sources/Search/`（Phase 2 已剥除其 browser 分支，此时可整删）、`Sources/DockPanelView.swift`、`Sources/DockEmptyView.swift`、`cmuxTests/SearchIndexTests.swift`
- [ ] **修改（审查指出：右侧栏/文件浏览器/全局搜索接在 app 脊柱上，glob 删文件不够，须同 PR 清引用否则编译失败）— 右侧栏 surface**：
  - `Sources/AppDelegate.swift`：`MainWindowContext` 的 `fileExplorerState: FileExplorerState?`（`:706/:716`）、主窗口 setup 的 `FileExplorerState` 创建（`:8005`）、`applyRightSidebarRemoteCommand(...)`（`:6356`）及其在远程命令分发处的调用点（一并去，remote 路径 Phase 8b 已不再引用它）。
  - **CLI/socket `right_sidebar` 入口（审查 R2：删 `RightSidebarRemoteCommand.swift`→`RightSidebarRemoteRequest` 后这些悬空，Phase 4 不编译）**：`CLI/cmux.swift` 删 `right-sidebar` 命令解析/转发/help（`:3114` `rightSidebarSocketArguments`、`:4600`、`:5084` verb 表、`:14492` `cli.rightSidebar.usage` help、**`:14937` `forwardRightSidebarCommand`**）；`Sources/TerminalController.swift` 删 `right_sidebar` 焦点策略 gate（`:363`）+ `RightSidebarRemoteRequest.parse`（`:370`）+ policy params（`:1407`）+ dispatch/handler（`:1590-1591` `case "right_sidebar": return rightSidebar(args)`）+ **`:20407-20448` 的 `RightSidebarRemoteRequest.parse`/`app.applyRightSidebarRemoteCommand`（`:20421`）调用 + 测试 seam `parseRightSidebarRemoteRequestForTesting`（`:20436`）** + `debug_right_sidebar_focus`/`debug.right_sidebar.focus` 调试命令（`:171/:193/:1679`）；删 `cli.rightSidebar.*` 与 `rightSidebar.remote.error.*` 本地化键（`Resources/Localizable.xcstrings:160344+`）；**删 `cmuxTests/TerminalControllerSocketSecurityTests.swift:812+` 的 `right_sidebar` socket 测试（审查 R2）**；删 right-sidebar/dock 的 docs 或 CLI docs topic（`CMUXCLI+DocsSettings.swift` 中宣传该面的条目）。
  - `Sources/Workspace.swift`：`RightSidebarToolPanel` 创建/查找（`:15436/:15463`）、快照 `SessionRightSidebarToolPanelSnapshot`（`:555/:669/:674`）与 reattach（`:16171`）；`Sources/SessionPersistence.swift` 删 `SessionRightSidebarToolPanelSnapshot` 字段（Phase 0 解码器兜底旧快照）。
  - 快捷键/本地化/测试：`KeyboardShortcutSettings.swift` 与 `Packages/CmuxSettings/.../ShortcutAction.swift` 的右侧栏相关 action、`Resources/Localizable.xcstrings` 串、相关测试。
- [ ] **修改 — 全局搜索 surface（入口在 `Sources/Search/` 之外，须同 PR 去）**：`Sources/AppDelegate.swift` 删 `GlobalSearchCoordinator.shared.start()`（`:1388`）与菜单打开（`:8306`）；`Sources/App/MenuBarExtraController.swift` 删 `globalSearchItem`「Search All Windows」项 + 回调（`:24`）；`Sources/KeyboardShortcutSettings.swift` 删 `case globalSearch`（`:65` 及全部引用）、`Packages/CmuxSettings/.../ShortcutAction.swift` 删 `case globalSearch`（`:18/:129/:166`）+ 设置/本地化串 + 全局搜索快捷键测试。**注意 CLAUDE.md 快捷键政策**：删 cmux-owned 快捷键须同步 `KeyboardShortcutSettings`、Settings、`cmux.json` schema、快捷键文档。
- [ ] **保留（不可删，审查修正 — 终端查找不是单文件）**：`Sources/Find/` 的**三个终端查找文件** `SurfaceSearchOverlay.swift`、`TerminalSearchOverlayHostingView.swift`、`FindTextFieldSupport.swift`——`SurfaceSearchOverlay.swift:205` 的 `SearchNativeTextField` 子类化 `FindSelectionTrackingTextField`、`GhosttyTerminalView.swift:13467` 挂载 `TerminalSearchOverlayHostingView`、`:14703` 调 `cmuxRememberFindSelection`，三者互相依赖（见 CLAUDE.md「Terminal find layering contract」）。Phase 2 已删 `Sources/Find/Browser*` 两个文件，故本 phase **`Sources/Find/` 不再删任何文件**。
- [ ] 🗑️ `Sources/Feed/FeedPanelView.swift`、`FeedPanelViewModel.swift`、Feed 调试窗（`FeedButtonStyleDebugWindowController`、`FeedPreviewWindowController`、`FeedTextEditorDebugWindowController`）
- [ ] **保留（不可删）**：`Packages/CMUXWorkstream`、`Sources/Feed/FeedCoordinator.swift` 的 `ingestBlocking()`/`deliverReply()`/pid 跟踪、`TerminalController.v2FeedPush()`、`Sources/ChatRoomController.swift` —— 聊天桥的事件管道（D9）
- [ ] **修改**：`Sources/ContentView.swift` / `Sources/RightSidebarPanelView.swift`（若整文件不删）— 移除右侧栏 modes 切换、`FeedPanelView()` 引用、`FeedCoordinator.shared.store?.pending.count` 等 UI 观察
- [ ] **修改**：`Sources/AppDelegate.swift` — `FeedCoordinator.shared.install(store:)` **保留**；仅移除 Feed **面板 UI** 的挂载与菜单
- [ ] **修改**：`Sources/CommandPalette/*` — 删 files/find/sessions/feed/dock 命令条目

### Phase 5 — 侧边栏扩展 / 自定义渲染平台（含 D8c 已定位的 seam）

> 审查修正：seam 已核实——`CmuxSwiftRenderUI` 只喂 `extensionSidebarScrollArea()`（`ContentView.swift:11220`），不喂聊天侧边栏 `workspaceScrollArea()`（`:11056`），切换点 `:10960-10962`。**先断 `extensionSidebarScrollArea()` 这一路，确认 room 侧边栏走 `workspaceScrollArea()`，再删平台。** `Examples/` 在此删（Phase 1 已移走，因 `ContentView.swift:7` import 它）。
- [ ] **修改**：`Sources/ContentView.swift` — **保留** `workspaceScrollArea()`（`:11056`）；删 `extensionSidebarScrollArea()`（`:11220`）、`:10960-10962` 的 provider 切换、`CmuxExtensionSidebarSelection` 枚举/菜单/设置开关、`import CmuxExtensionSidebarExamples`（`:7`）、`@_spi(CmuxHostTransport) import`
- [ ] **修改**：`Sources/TerminalController.swift` — 移除 `import CmuxSwiftRenderUI` 与 `SidebarActionDispatch` 用法；`Sources/cmuxApp.swift` — 移除扩展侧边栏 provider 装配
- [ ] **修改（审查 R2：删 `CmuxExtensionSidebarSelection`/`CustomSidebarValidator` 包却留 socket 方法/handler/CLI/设置，会引用已删类型且留死面）— custom-sidebar socket/CLI/设置全切片**：
  - `Sources/TerminalController.swift`：删 `sidebar.custom.validate`/`sidebar.custom.reload`/`sidebar.custom.select` 的注册（`:911-913`）+ dispatch（`:1095-1099`）+ 其 handler（引用 `CustomSidebarValidator`/`CmuxExtensionSidebarSelection`，`:4067/4083` 及 reviewer 指出的 `:4129/:4150`）、`extension.sidebar.snapshot`（`:1929` dispatch + `:2418` capability）；删相关 `socket.sidebar.custom.*` 本地化串
  - `CLI/cmux.swift`：删 `cmux sidebar custom {validate,reload,select}` 命令（`:15022/:15042` 调上述 socket 方法）+ help/本地化/测试
  - 设置：🗑️/删 `Packages/CmuxSettings/.../Keys/BetaFeaturesCatalogSection.swift:44-47` 的 `customSidebars`（`customSidebars.beta.enabled`）、`Packages/CmuxSettingsUI/.../Sections/BetaFeaturesSection.swift:92` 的 `customSidebarsRow`、`Packages/CmuxSettingsUI/.../Navigation/CuratedSettingEntry+Default.swift:105` 搜索条目 + schema/本地化/测试（**CLAUDE.md 设置政策**：同步 `cmux.json` schema + 文档）
  - 文档/help（审查 R1.2：删 guide 却留指向它的 docs topic/事件文档）：删 `CLI/CMUXCLI+DocsSettings.swift:118-128` 的 `sidebars` docs topic（aliases `custom-sidebar`/`vibe-sidebar`，指向 `docs/custom-sidebars`）；改 `docs/events.md`（`:93/:237/:248` 引导扩展侧边栏作者用 `extension.sidebar.snapshot` 的段落——随该事件删除而去）；🗑️ `docs/custom-sidebars.md`、`docs/data-driven-sidebar-plan.md`
- [ ] **修改（审查 R1.1/R2.2：本 phase 删扩展平台包，故必须同 PR 拥有整条 `extensionBrowser` panel surface，否则留下引用已删包的活代码、Phase 5 不编译）— `extensionBrowser` PanelType 全切片**：
  - `Sources/Panels/Panel.swift` 删 `PanelType.extensionBrowser`（`:13`）及其全部 arm（`:690`/`:1888`/`surfaceKind` `:11729`、`SurfaceKind.extensionBrowser` `:10746`）
  - `Sources/Workspace.swift` 删 `newSidebarExtensionBrowserSurface(...)`（`:15030`，内部 `CMUXSidebarExtensionBrowserPanel` 创建）与 `createPanel()`/`sessionSnapshot()`/`surfaceKind(for:)` 的 `case .extensionBrowser`
  - `Sources/Panels/PanelContentView.swift` 删 extensionBrowser 视图分支
  - `Sources/AppDelegate.swift` 删 `openSidebarExtensionBrowser(from:title:)`（`:13732`）及其菜单/调用点
  - `Sources/Update/UpdateTitlebarAccessory.swift:943` **和** `Sources/Update/MinimalModeSidebarControls.swift:198`（审查 R1.1：第二个调用点）删 `CmuxExtensionSidebarSelection.showMenu(...)` 调用（**两文件整体由 Phase 11 删，但 Phase 5 删 `CmuxExtensionSidebarSelection` 会先断它们，故此处先去两处调用点**）
  - `Sources/SessionPersistence.swift` 删 extensionBrowser panel snapshot 字段（Phase 0 解码器已把 `extensionBrowser` 列入 drop 集兜底旧快照）
  - 快捷键/本地化/测试：相关 `KeyboardShortcutSettings`/`ShortcutAction` 条目、`Resources/Localizable.xcstrings` 串、对应测试
- [ ] 🗑️ `Sources/CMUXSidebarExtensionBrowserPanel.swift`（`:1` `@_spi(CmuxHostTransport) import CMUXExtensionHostSupport`）、`Sources/CMUXInstalledExtensionSidebarHostView.swift`、`Sources/ExtensionSidebarWorkspaceRowView.swift`、`Sources/ExtensionWorktreePrototype.swift`、`Sources/CmuxSidebarActionDispatch.swift`、`Packages/CmuxExtensionKit`、`CMUXExtensionHostSupport`、`CmuxSidebarProviderKit`、`CmuxSidebarInterpreterService`、`CmuxSwiftRender`、`CmuxSwiftRenderUI`、`Examples/`（含 `CmuxExtensionSidebarExamples` 与其余 `*Sidebar*` 样例）

### Phase 6 — 配对 Mac 移动主机（D3②；打字延迟热路径，谨慎）

- [ ] **修改**：`Sources/TerminalController.swift` — 删 `MobileViewportReport` 结构 + `mobileViewportReportsBySurfaceID` 等字典、`mobileTerminalRenderGridFrame()`/`mobileHostHandleRPC()`/`mobileHostResult()`、`MobileHostService.shared.*` 调用、`import CMUXMobileCore`
- [ ] **修改**：`Sources/GhosttyTerminalView.swift` — 删 `mobileByteTeeContext`、PTY byte-tee 回调安装与 `dropSurface` 处的 tee 清理、`import CMUXMobileCore`（**仅减负载**；diff 确认渲染网格帧无非移动用途依赖此 tee，否则先抽出该值类型到 `CmuxFoundation` 再删）
- [ ] **修改**：`Sources/AppDelegate.swift` — 删 `MobileHostService.shared.start()/stop()`、`ensureMobileWorkspaceListObserver()`/`removeMobileWorkspaceListObserverIfUnused()`/`installMobileHostSettingsObserver()`/`syncMobileHostService()` 及 `mobileWorkspaceListObservers`/`mobileHostSettingsObserver` 属性
- [ ] **修改（审查 R1.2：`TabManager` 直接用 `MobileHostRequestActivity`，定义在待删的 `Sources/Mobile/MobileHostService.swift:158`——不清理则 Phase 6 不编译）**：`Sources/TabManager.swift` 删 7 处 `MobileHostRequestActivity.quietDelay(...)`/`.hasRecentActivity(...)` 调用（`:1449`/`:1708`/`:1891`/`:2862`/`:2870`/`:3065`/`:3073`）及 `mobileHostBackgroundWorkQuietInterval` 常量——移除「移动主机活动期推迟后台工作」的节流：移动主机已删，无移动活动可节流，guard 直接去掉（后台工作照常进行），**不**引入替代节流（YAGNI，无第二来源）。
- [ ] **修改/删除（审查 R1.2：删主机却留「iOS Pairing」设置 = 死设置开关，更糟）**：🗑️ `Packages/CmuxSettingsUI/Sources/CmuxSettingsUI/Sections/MobileSection.swift`；删 `Packages/CmuxSettings/Sources/CmuxSettings/Keys/MobileCatalogSection.swift` 的 `iOSPairingHost`（`mobile.iOSPairingHost.enabled`）及该 catalog section 全部 mobile 键、设置搜索别名、`Resources/Localizable.xcstrings` 的 mobile 设置串、`cmux.json` schema/配置文档的 mobile 项、相关测试（**CLAUDE.md 设置政策**：删设置项须同步 schema + 文档 + 本地化）。
- [ ] 🗑️ `Packages/CMUXMobileCore`、`Sources/Mobile/`（上述引用清零后）

### Phase 7 — 未用 agent 集成（窄范围）+ `cmux top`（文件级 split）

> 审查修正：Rovo/Hermes/Amp **不孤立**——`Sources/SessionIndexStore.swift:1276-1277`、`Sources/SessionIndexView.swift:1158/1192/1499`、`Sources/SessionAgentPresentation.swift:10/24` 仍引用它们；保留的 `RestorableAgentKind`（18 cases，用于解码旧会话）也含这些 case。**故本 phase 收窄为「只删真正死的 hook 安装器 / CLI 入口」，保留 session-index/presentation 与 enum cases**（廉价、且解码旧会话需要）。
- [ ] 🗑️ **hook 安装器整套，全有全无（审查修正：rovo/hermes/amp 的 `AgentHookDef` 行 + dispatch 与 config 文件硬耦合，半删不编译）**。`cmux.swift:26241/26245` 把 rovodev/hermes-agent dispatch 到 `installRovoDevHooks`/`installHermesAgentHooks`（uninstall 在 `:26602/26606`），且 `rovoDevHooksContent`（`cmux.swift:26031-26043`）直接引用 `RovoDevHookConfig.Event/.installing`、`installHermesAgentHooks` **定义在**待删的 `CMUXCLI+HermesAgentHooks.swift` 内、amp 行（`AgentHookDef:212`）依赖待删的 `CMUXCLI+AmpExtension.swift`——故每个 agent 必须**同 PR 一起删**：
  - 文件：`Packages/CMUXAgentLaunch/Sources/CMUXAgentLaunch/RovoDevHookConfig.swift`、`HermesAgentHookConfig.swift`、`CLI/CMUXCLI+HermesAgentHooks.swift`、`CLI/CMUXCLI+AmpExtension.swift` + 各自测试；
  - **`AgentHookDef` 行**：`CLI/CMUXCLI+AgentHookDefinitions.swift` 的 rovodev(`:282`)/hermes-agent(`:294`)/amp(`:212`) 三行；
  - **dispatch**：`cmux.swift` 的 `if def.name == "rovodev"/"hermes-agent"` install(`:26240-26247`)/uninstall(`:26601-26608`) 分支，及 amp 经 flat 路径对 `CMUXCLI+AmpExtension` 的引用、`installRovoDevHooks`/`uninstallRovoDevHooks`/`rovoDevHooksContent` 三函数；
  - **入口**：`cmux hooks setup/uninstall {rovodev,hermes-agent,amp}` 子命令分发 + 本地化/help 串。
- [ ] **保留（不可删，审查指正）**：`Packages/CMUXAgentVault/Sources/CMUXAgentVault/Providers/{RovoDev,HermesAgent}/*Index.swift`（这是**会话索引 provider**，被保留的 session-index 用，**不是** hook 安装器）、`RestorableAgentKind` 全部 case（解码旧会话）、`SessionAgentPresentation.swift` 与 `SessionIndexStore/View` 的 rovo/hermes 分支。注意：删的是 `AgentHookDef` 中这三行**及其 dispatch**，不是整张表（claude/codex/cursor 行保留）。
- [ ] **OMP（D8a：可删，但须文件级完整，审查修正）**：🗑️ `CLI/CMUXCLI+OmpExtension.swift` 时**同 PR**移除 `CLI/CMUXCLI+AgentHookDefinitions.swift:203` 的 omp `AgentHookDef` 条目、`CLI/cmux.swift:26232` 对该文件方法的调用、`cmux hooks setup omp` 入口、相关测试与本地化串；并修 `AgentKind.swift:3` 过时注释。（要么整套删干净，要么整套保留——不可半删。）
- [ ] **`cmux top` 文件级 split**：**删除集** = `cmux top` 子命令 + 其面向用户的监控 UI 文件；**保留集** = `Sources/CmuxTopProcess*.swift`、`Sources/CmuxTopSnapshot*.swift`、`Sources/TerminalControllerTopSupport.swift`（被 `RestorableAgentSession`、`VaultAgentProcessScanner`、`Sources/App/AgentHibernationController.swift` 复用）。修改 `CLI/cmux.swift` 去掉 `top` dispatch。

> **审查修正：Phase 8 拆成 8a / 8b / 8c 三个独立 PR**（不同爆炸半径与回滚点），且加显式边界声明。
>
> **边界（必读）**：D2 删的是 **`cmuxd` 守护进程 + remote SSH**；**绝不**碰本地控制 socket `Packages/CmuxControlSocket` / `Packages/CmuxSocketControl`——CLI/hooks 经它通信，属脊柱。读到"删 daemon/cmuxd"时务必区分二者。已核实 `cmuxd`/`Remote*` 仅被 `Workspace.swift`/`WorkspaceRemoteConfiguration.swift`/SSH builder 引用，**不**被 `SessionPersistence`/`AgentHibernation` 引用。

### Phase 8a — 云 / Auth（独立 PR）

- [ ] 🗑️ `Sources/Cloud/`、`Sources/CloudVMActionLauncher.swift`、`Sources/Auth/`、`Packages/CMUXAuthCore`、`Packages/CmuxAuthRuntime`、`vendor/stack-auth-*`
- [ ] **前置（审查 R2.1：`web/` 不止 cloud——`web/data/` 是 app+CLI 引用的 canonical 设置 schema/shortcuts 源，必须先迁出再删 `web/`，否则核心设置 schema/docs 指向已删文件）**：把 `web/data/{cmux.schema.json,cmux-settings.schema.json,cmux-shortcuts.ts}` 移到非 web canonical home（如 `schema/`），并 repoint 全部引用——`Sources/KeyboardShortcutSettingsFileStore.swift:28-29`（`schemaURLString`/`legacySchemaURLString`）、`Sources/KeyboardShortcutSettingsFileStore+Template.swift:8`（生成的 `cmux.json` `$schema` URL）、`CLI/CMUXCLI+DocsSettings.swift:5/48`（`settingsSchemaURL`/shortcut data）、`CLI/CMUXCLI+Config.swift:151`——的 `main/web/data/...` raw URL 改为新路径。**这步是删 `web/` 的 hard 前置**；且后续 Phase（mobile/telemetry/customSidebars/workspaceGroups 删设置项）须同步更新迁出后的 schema 文件，保持 schema/docs 诚实。
- [ ] 🗑️ **`web/`（从 Phase 1 移入——CI/cloud-vm workflow 在此自然归属；schema/shortcuts 已先迁出）**：删 `web/` 整目录；**同 PR** 删/no-op `ci.yml:107` web-typecheck + `:161` web-db-migrations job、`.github/workflows/cloud-vm-migrate.yml`、`cloud-vm-smoke.yml`；`scripts/verify-cmd-click-file-previews.sh` 的 `web/public` fixture 引用已在 Phase 3 随 filePreview 删除（若未删则此处一并去）；删 `CMUXCLI+DocsSettings.swift` 中 browser/dock 等已删功能的 docs topic（随各功能删除而去，避免 docs 指向已删特性）。
- [ ] **修改 — CLI auth/vm/cloud surface（审查指出：socket handler 删了但 CLI verb 仍在，会对已删 handler 失败）**：`CLI/cmux.swift` 删 `case "auth", "login", "logout"`（`:3338`）、`case "vm", "cloud"`（`:3405`）dispatch 与其 helper、VM/cloud help 文本（`:12840`）；`scripts/stress-cli-socket-api.py` 删 `auth`/`cloud`/`auth login`（`:68/:72/:169`）等条目。
- [ ] **修改**：`Sources/TerminalController.swift` 删 `vm.*` / `auth.*` socket case（**`browser.profiles.*`/`browser.import.cookies` 已移至 Phase 2，其 backing 在 `Sources/Panels/`，不在本 phase**）；`Sources/TerminalNotificationStore.swift` 删 `PhonePushClient.shared.forward(...)`；`Sources/cmuxApp.swift` 删 `HostAccountFlow`/账户 section 装配；`Sources/AppDelegate.swift` 删 `AuthManager.shared.handleCallbackURL` 与 `cmux://auth-callback`；`Packages/CmuxSettingsUI` 账户 section

### Phase 8b — Remote SSH + 会话 snapshot 迁移（独立 PR）

- [ ] 🗑️ `Sources/WorkspaceRemoteConfiguration.swift`、`Sources/Remote*.swift`（`RemoteInteractiveShellBootstrapBuilder`、`RemoteRelayZshBootstrap`、`RemoteShellSessionParsing`、`RemoteLoopback*`、`WorkspaceRemoteSSHBatchCommandBuilder`）、`Sources/AppDelegate+CmuxSSHURL.swift`、`cmuxTests/WorkspaceRemoteConnectionTests.swift`（**`RightSidebarRemoteCommand.swift` 已移至 Phase 4、`MarkdownRemoteImageLoader.swift` 由 Phase 3 拥有（在 `Sources/Panels/`）——均不在本 phase，消除审查指出的 Phase 4/8b 与 Phase 3/8b 归属冲突**）
- [ ] **修改**：`Sources/Workspace.swift` 删 `WorkspaceRemoteSessionController`（~3.5k LOC）、全部 `@Published` remote 属性（含 `remoteProxyEndpoint`）、`isRemoteWorkspace` 及其遍布 guard、所有 `remote*` 方法、`newTerminalSurface()`/`createPanel()` 的 remote 分支
- [ ] **修改**：`Sources/TerminalController.swift` 删 `workspace.remote.*` RPC case 与 `v2WorkspaceRemotePTY*`/`v2WorkspaceRemoteConfigure`、`currentSocketPathForRemoteRestore()`；`Sources/ContentView.swift` 删 remote 状态观察/侧栏 UI/文件浏览 guard；`Sources/SessionPersistence.swift` 删 `SessionRemoteWorkspaceSnapshot` 与 terminal snapshot 的 `isRemoteTerminal`/`remotePTYSessionID`（Phase 0 持久化层解码器兜底旧含-remote 快照）

### Phase 8c — `cmuxd` 守护进程（独立 PR；**不碰** CmuxControlSocket/CmuxSocketControl）

- [ ] 🗑️ `daemon/`（cmuxd）— 核实其 remote-only、不承载本地运行/打包后删；**再次确认**未误删本地控制 socket 包。
- [ ] 🗑️ **daemon release/打包 helper 脚本（审查 R2.4：删 `daemon/` 却留这些会指向已删产物）**：`scripts/build_remote_daemon_release_assets.sh`（remote-daemon 资产构建器）；**修改** `scripts/prune_nightly_release_assets.py` 删 `cmuxd-remote-*` 资产匹配模式（`:15-17` 的 `cmuxd-remote-(darwin|linux)-*` / `cmuxd-remote-checksums-*` / `cmuxd-remote-manifest-*` 正则）。
- [ ] **修改 CI/release（审查指出 daemon 经 workflow + dev 脚本连线）**：`.github/workflows/ci.yml:97`、`tmux-corpus.yml:7`、`release.yml:249`、`nightly.yml:397` 的 cmuxd job，`scripts/release_asset_guard.js:6-11` 的 `cmuxd-remote-*` 资产校验行 + `scripts/release_asset_guard.test.js`（`ci.yml:53` 跑它），以及调用 `build_remote_daemon_release_assets.sh` 的 release/nightly 步骤，本地 dev 脚本 `scripts/reloads.sh`（`CMUXD_UNIX_PATH` 注入 `:236-237/:277`、`cmuxd` 构建/拷贝 `:259-267`）与 `scripts/reload.sh` 的同类 cmuxd 注入——**与本 PR 同步**移除或停用，否则本地编译过但 CI/release/dogfood 仍带 stale daemon 行为。若暂不动 release/nightly，则在本 phase **显式标注"先停用 remote-daemon job"** 再删 `daemon/`。

### Phase 9 — 「Bus」对外更名（D1，纯文案）

> 审查修正：更名（外显、最小）与 `WorkspaceGroup`（有风险的模型清理，gated on roomID/侧边栏稳定）**职责不同，拆开**。本 phase 只做对外文案。

- [ ] **修改（仅对外文案）**：`Resources/Info.plist` `CFBundleDisplayName` → Bus、About 面板、窗口标题构造、`README.md`、`docs/` 对外文案、`Resources/Localizable.xcstrings` 对外可见字符串。**严禁触碰**：`cmux` CLI 二进制名、`CMUX_*` 环境变量、socket 路径、bundle id 基名、`Cmux*/CMUX*` 包名、hook 协议、`scripts/*`、debug tag
- [ ] **（可选）新增**：薄 `bus` CLI alias 转发 `cmux`，不改协议/env

### Phase 10 — `WorkspaceGroup` 退役 + 内部收缩（独立 PR；gated）

> 审查修正：从 Phase 9 拆出。需 roomID 侧边栏/创建/关闭语义稳定，且补恢复/侧边栏/关闭不变量测试后才做（见测试计划）。
> 审查修正 R1：原一行严重 under-scope——`WorkspaceGroup` 横跨 sidebar/设置/config/docs/持久化/测试多面，glob 删 model 会留死的 sidebar/设置/docs 面或漏旧会话兼容。展开为完整垂直切片：
- [ ] **模型/核心（审查 R1.2 修正：`WorkspaceGroup` 类型实际在 `TabManager.swift`，非 `Workspace.swift`）**：`Sources/TabManager.swift` 删 `struct WorkspaceGroup`（`:1007`）与其 group 设置类型（`:920` 一带，如 `WorkspaceGroupNewWorkspacePlacementSettings`/`WorkspaceGroupNewPlacement`）；`Sources/Workspace.swift` 删 `groupId`/`deleteWorkspaceGroup`/ungroup·dissolve·anchor 路径与 group 配置解析使用点（`:10313` 状态、`:10560 resolveWorkspaceGroupConfig`）；`Sources/TerminalController.swift` 收缩不可达旧分支（终端 + chatRoom/agent only 假设）
- [ ] 🗑️ **专用 sidebar/group 文件**：`Sources/TabItemView+WorkspaceGroups.swift`、`Sources/VerticalTabsSidebar+WorkspaceGroups.swift`、`Sources/WorkspaceGroupMenuSnapshot.swift`、**（审查 R1.2）`Sources/SidebarWorkspaceGroupHeaderView.swift`、`SidebarWorkspaceGroupDialogs.swift`、`SidebarWorkspaceGroupConfigOpener.swift`、`SidebarWorkspaceGroupHeaderMetrics.swift`、`SidebarWorkspaceGroupingMetrics.swift`**
- [ ] **修改 — 设置/config/schema 引用（审查 R1.2：删模型/设置类型却留这些 → 编译错 + stale config）**：`Sources/KeyboardShortcutSettingsFileStore.swift` 删 `workspaceGroups` section 解析（`:372-373` + `parseWorkspaceGroupsSection` `:1007`、`workspaceGroups.newWorkspacePlacement` `:1014`）；`Sources/KeyboardShortcutSettingsFileStore+Template.swift:85` 删生成模板里的 `workspaceGroups` 项；`Sources/SettingsNavigation.swift:438` 删 `workspaceGroups.newWorkspacePlacement` 导航映射；`Sources/CmuxSettingsJSONPathSupport.swift:90` 删该 JSON path；同步迁出后的 `cmux.schema.json` 的 `workspaceGroups`（schema 已在 Phase 8a 迁出非 web home）
- [ ] **修改 — sidebar 渲染/上下文菜单**：`Sources/ContentView.swift` 删 `workspaceGroups`/`workspaceGroupById`/`workspaceGroupMenuSnapshot`（`:10900-10902/:10929`）与 group header/分组渲染、右键「分组/解组」菜单；`Sources/SidebarWorkspaceRenderItem.swift` 的 `groupHeader`/`renderItems(...groupsById:)` 旧分组路径（聊天室用 `chatRoomRenderItems`，group 路径已不可达）
- [ ] **修改 — AppDelegate 新建-入组路径**：`Sources/AppDelegate*.swift` 删「在 group 内新建 workspace」/move-into-group 分支
- [ ] **修改 — 持久化（旧会话兼容）**：`Sources/SessionPersistence.swift` 删 `SessionWorkspaceGroupSnapshot`（`:1825`）与 `SessionWorkspaceSnapshot.workspaceGroups`（`:1860`）字段——**旧会话兼容**：该字段是 `decodeIfPresent` 可选，删属性后 Codable 默认忽略未知 key；须确认 `SessionWorkspaceSnapshot` 无穷举 CodingKeys/抛错解码强制它，并加旧含-`workspaceGroups` 快照回归（恢复后 tab 顺序/平铺正常、无悬挂 `anchorWorkspaceId`）
- [ ] **修改 — config/设置/docs/本地化**：`Sources/CmuxConfig.swift` 删 `workspaceGroups`（`:19`）、`CmuxConfigWorkspaceGroupsDefinition`（`:157`）、`CmuxConfigWorkspaceGroupEntry`（`:165`）及 CodingKeys/decode（`:90-92`）；删 `cmux.json` schema 的 `workspaceGroups`、设置搜索别名、`Resources/Localizable.xcstrings` group 串；🗑️ `docs/workspace-groups.md`
- [ ] **修改 — 测试**：删/改 WorkspaceGroup 相关单测（reorder/dissolve/anchor/恢复），新增旧会话兼容回归（见测试计划「`WorkspaceGroup` 退役不变量」）

### Phase 11 — 更新器 / 分发删除（D4，独立 PR；审查指出非"随手 commit"）

- [ ] **修改**：`Sources/AppDelegate.swift` 删 `import CmuxUpdater`/`CmuxUpdaterUI`（`:6-7`）、`UpdateActionDelegate`/`UpdateActionsHost` 一致性与 retry/relaunch 回调、**`checkForUpdates(_:)` 方法**；`Sources/ContentView.swift` 删侧边栏 update pill；`Sources/cmuxApp.swift` 删 updater 装配
- [ ] **修改 — updater 入口 surface（审查指出散落在 Phase 11 文件之外，删 `checkForUpdates` 会断这些）**：`Sources/App/CmuxHelpCommands.swift:17-18` Help 菜单「Check for Updates」、`Sources/App/MenuBarExtraController.swift:33/130-132/277` `checkForUpdatesItem` + `checkForUpdatesAction`、`Sources/ContentView.swift:7001` 命令面板 `palette.checkForUpdates` 贡献 + 对应本地化串（`command.checkForUpdates.*`/`menu.checkForUpdates`）
- [ ] 🗑️ `Sources/Update/`、`Packages/CmuxUpdater`、`Packages/CmuxUpdaterUI`、`homebrew-cmux/`、相关测试（含 updater UI 测试）；Info.plist 的 `SUFeedURL`/`SUPublicEDKey` 等 Sparkle 键
- [ ] **本地 release 脚本（审查指出仍要求 Sparkle/appcast/homebrew）**：**改写** `scripts/build-sign-upload.sh`——剥除 Sparkle key 注入（`:83-95`）、appcast 生成/上传（`:131-158`）、homebrew 编辑（`:173`），**保留**构建/签名/公证/DMG/上传（app 仍需出 DMG，只是不再自动更新）；**审查 R1：`remove-sparkle-sandbox-xpc-services.sh` 非真 orphan——`scripts/sign-cmux-bundle.sh:79` 调它，而 `sign-cmux-bundle.sh` 仍被 `release.yml:360`/`nightly.yml:519` 用；故须同 PR 先改 `sign-cmux-bundle.sh` 删掉 `:79` 的调用（Sparkle 已不在 bundle 里，无需再剥 XPC）+ 删 `tests/test_sparkle_xpc_cleanup.sh`，再** 🗑️ `scripts/{sparkle_generate_appcast.sh,sparkle_generate_keys.sh,derive_sparkle_public_key.swift,remove-sparkle-sandbox-xpc-services.sh}`；`scripts/release-pretag-guard.sh` 剥除 appcast/Sparkle 检查；🗑️ feature-coupled 测试 `tests/test_ci_sparkle_build_monotonic.sh`、`tests/test_nightly_universal_build.sh` 的 Sparkle 部分（**这些是 Sparkle 专属守卫，随功能删——区别于保留的通用 `test_ci_*` 基础设施守卫**）
- [ ] **修改 CI/release**：`.github/workflows/update-homebrew.yml`（Sparkle/homebrew 发布流）、`release.yml`/`nightly.yml` 中的 appcast/Sparkle 步骤；**`scripts/release_asset_guard.js:5` 的 `"appcast.xml"` 必需资产行 + 其 `release_asset_guard.test.js`**（`release.yml:72` 经 `evaluateReleaseAssetGuard` 调用、`ci.yml:53` 跑 test）——删 appcast 生成的同时移除该校验行，否则 release 校验仍要求已不再生成的 appcast 资产而红。（注：该 guard 的 `cmuxd-remote-*` 行由 Phase 8c 处理，本 phase 只动 `appcast.xml` 行。）同步删除或停用

### Phase 12 — 遥测 / 崩溃上报删除（D7，独立 PR）

- [ ] **修改**：`Sources/GhosttyTerminalView.swift` 删 `import Sentry`（`:13`）与 `SentrySDK.capture` 调用点（如 `:1994`）；其余 `SentrySDK`/`PostHog` 调用点
- [ ] **修改 — 用户可见遥测设置 surface（审查指出：删内部实现却留「Send anonymous telemetry」开关 = 死隐私开关，更糟）**：删 `Sources/CommandPalette/CommandPaletteSettingsToggle.swift:310-318` 的 `sendAnonymousTelemetry` 开关、`Sources/SettingsSearchAliases.swift:76` 的 `app:telemetry` 别名、`Packages/CmuxSettingsUI/.../AppSection.swift:96/536` 的 telemetry 行、`Packages/CmuxSettings` 设置目录的 `app.sendAnonymousTelemetry` 项与 `TelemetrySettings` 模型、本地化串（`settings.app.telemetry` 等）、`cmuxTests/GhosttyConfigTests.swift:1290/1304` 的 `TelemetrySettings` 测试。**注意 CLAUDE.md 设置政策**：删设置项须同步 `cmux.json` schema + 配置文档 + 本地化。
- [ ] 🗑️ `Sources/PostHogAnalytics.swift`、`Sources/SentryHelper.swift`、Sentry/PostHog 的 pbxproj 包引用、相关测试与本地化串；**保留** `Packages/CMUXDebugLog`（本地 dogfood 日志）
- [ ] **修改 CI/release**：`release.yml:412`、`nightly.yml:592` 的 dSYM→Sentry 上传步骤——同步删除或停用

## 埋点事件分析（如适用）

N/A — 纯删除/重构，无新增用户操作或埋点。

## 错误跟踪（如适用）

N/A — 不新增运行时失败路径。唯一需观测的是删除 panel 类型 / remote 字段后**旧会话 snapshot 的解码迁移**——由 Phase 0 在**持久化边界**统一处理：`SessionPanelSnapshot` lossy 解码（已删类型字符串 → 丢弃该 panel + `cmuxDebugLog` 记一条）+ `restoreSessionSnapshot` 净化 layout/focus/selected id。不进运行时 `PanelType`，不抛错。

## 断言检测（如适用）

N/A。

## 实施步骤

> **重要**：
> - 计划大小为 L 或 XL 时必须使用阶段，计划大小为 XS、S 或 M 时仅使用步骤；XXL 和 XXXL 必须使用多个阶段，每个阶段对应一个独立 PR，并在每个阶段结束后运行完整测试套件
> - 一个阶段应该是它自己的 PR
> - 一个步骤可以是一个 PR 中的一次提交
> - **自动化优先**：AI 代理可以执行 shell 脚本和命令行工具（如 `ui-test/scripts/run_test.sh`、`pytest`、`gradle test` 等），因此运行脚本、执行测试、编译代码等操作**绝不应标记为手动步骤**。只有真正需要人类物理操作的步骤才应标记为 **(需要手动操作)**，例如：在浏览器中登录第三方服务、在 Web 控制台配置设置或验证数据是否到达、在 Xcode 中手动导入包、真实物理设备交互、需要人眼视觉判断的 UI 验收等。
> - 手动操作步骤必须清晰详细，例如：访问哪个网站、点击哪个按钮、添加什么内容、在哪个菜单中找到什么选项等。
> - 建议（非必须）开发者在每个步骤完成后修复所有编译错误、运行单元测试、提交并推送 (git commit, git push)。
> - **注意**：AI 代理应在完成每个步骤时勾选对应的复选框（标记为 **(需要手动操作)** 的步骤除外，这些步骤由开发者完成并勾选）
> - 计划执行只负责计划内要求的实现、测试和局部验证；全局 PR 收尾检查（覆盖率、单元测试、lint、架构文档同步、commit/push、PR 描述）由 `/pr` 统一负责。

XXXL 计划，**每个 phase = 一个独立 PR**。审查后阶段重排为：**Phase -1 / 0 / 1 / 1A / 1B / 2 / 3 / 4 / 5 / 6 / 7 / 8a / 8b / 8c / 9 / 10 / 11 / 12**。所有 phase 共享收尾门控 **G**（每 phase 末尾跑，不重复抄写）：

> **门控 G（每 phase 末尾跑，全自动）**：① 同步 `cmux.xcodeproj/project.pbxproj`（移除已删包/文件的 ref + Frameworks 链接）与**本 phase 文件清单列出的所有 phase-specific workflows**（不止 `ci.yml`/`test-ios.yml`——按 phase 还含 `ios-testflight.yml`、`release.yml`、`nightly.yml`、`tmux-corpus.yml`、`update-homebrew.yml` 等；以各 phase「需要修改的文件」为准，凡触发于已删路径或调用已删脚本的 workflow 必须同步删/停用）；② `python3 scripts/normalize-pbxproj.py` + `scripts/check-pbxproj.sh` + `scripts/lint-pbxproj-test-wiring.sh`；③ `xcodebuild -project cmux.xcodeproj -scheme cmux -configuration Debug -destination 'platform=macOS' -derivedDataPath /tmp/cmux-prune-bus build`（app 编译）；④ `xcodebuild -scheme cmux-unit -derivedDataPath /tmp/cmux-prune-bus build`（**测试 target 编译**——`reload.sh` 不编译它）；⑤ `./scripts/reload.sh --tag prune-bus` 起 tagged Debug；⑥ 自动化烟测（stale 命令面板/socket verb、旧快照 layout remap）+ 场景 1 见「测试计划」；⑦ **Periphery scoped 扫描（见「删除方法」）**：对本 phase 触及范围跑 Periphery，人工核对归属后删 transitively-dead 声明/文件（**两条护栏：scoped-only + 对 `@objc`/反射/sdef/IBAction 假阳性人工核对**；用 `--retain-objc-accessible` 等）；⑧ **非-Swift 消费者闸**：凡本 phase 删了 release/CI/dev 脚本或 `tests_v2` 套件，跑对应 **release 脚本 dry-run**（如 `sign-cmux-bundle.sh`/`build-sign-upload.sh` 的非签名路径）+ **完整 `scripts/run-tests-v2.sh`**，确认无指向已删脚本/API 的红。门控全绿才进下一 phase。

**Phase -1**：前提回归门控（不删任何东西）**(需要手动操作)**
- [ ] **步骤 1**：起 tagged app，新建 room + claude + codex agent，`@all` 发 prompt，确认**两者回复都回到 room channel**（非 `0 / N replied`）、终端查找可用；退出重开确认恢复 + claude 已 resume。**全绿才进 Phase 0。**

**Phase 0**：安全网（持久化边界宽松解码 + 恢复契约）
- [ ] **步骤 1**：复核 D8 a/b/c 代码锚点（OMP/CmuxTop/SwiftRender，已记于「已归档的决策」）。
- [ ] **步骤 2**：实现 `SessionPanelSnapshot` 持久化层 lossy 解码 + `restoreSessionSnapshot` 的 layout/focus/selected 净化（**不**加运行时 `PanelType.unknown`），作为**独立 commit**；配套写 `SessionSnapshotLenientDecodingTests`（见测试计划）。
- [ ] **步骤 3**：用含 `browser`/`markdown`/remote 字段、且 layout/selected 指向已删 panel 的真实旧 `session-*.json` 回归——丢弃未知 panel、layout 坍缩、窗口/tab 正常恢复、焦点不丢、不崩。
- [ ] **步骤 4**：门控 G。

**Phase 1**：真正独立目录删除
- [ ] **步骤 1**：删 `ios/`、`experiments/`、`Prototypes/`、`dogfood/`、`scripts/mobile-*`。**`web/` 移至 Phase 8a（CI web job + cloud-vm workflow + fixture 脚本耦合）；`diff-viewer/` 移至 Phase 3（CI job + markdown-viewer 内嵌产物）；`tests/` 不整删（含活跃 `test_ci_*` CI 守卫）。**
- [ ] **步骤 2**：删 12 个 `Packages/CmuxMobile*`（不含 `CMUXMobileCore`）；同 PR 删/no-op **`.github/workflows/test-ios.yml` 和 `.github/workflows/ios-testflight.yml`**（后者触发于 `ios/**`/`Packages/**`、`:188` 调 `./ios/scripts/upload-testflight.sh`——删 `ios/` 后会 scheduled/manual/main 红）；从 pbxproj 与 CI `PACKAGES` 移除引用。
- [ ] **步骤 3**：门控 G。**（`Examples/`、`AppleScript`、`claude-teams` 不在本 phase——见 Phase 5 / 1A / 1B。）**

**Phase 1A**：AppleScript 自动化面删除 **(需要手动操作：先确认无外部脚本依赖)**
- [ ] **步骤 1**：确认无外部 AppleScript 依赖后，删 `AppleScriptSupport.swift`、`Resources/cmux.sdef`、`Info.plist` 脚本键、相关本地化串/docs/tests + pbxproj 条目；门控 G。

**Phase 1B**：`claude-teams`/`codex-teams` 退役（**默认跳过**）
- [ ] **步骤 1**：默认保留（接在 resume/fork argv 脊柱上）。仅在确需退役时，迁移 `AgentResumeArgv`/`RestorableAgentSession:471`/`AgentLaunchSanitizer` + 旧会话兼容 + 测试后再删 CLI 子命令；门控 G。

**Phase 2**：浏览器垂直切片
- [ ] **步骤 1**：先断入口——`ContentView`/命令面板/菜单/`CLI` 移除一切 browser 入口（新建、socket verb、快捷键），编译通过。
- [ ] **步骤 2**：删 `PanelType.browser` + focus intent，逐处补齐 `Workspace`/`PanelContentView`/`SessionPersistence`/`KeyboardShortcutContext`/`TabManager` 的 `case .browser`。
- [ ] **步骤 3**：删全部 `Browser*`/`CmuxWebView*`/`Find/Browser{SearchOverlay,FindJavaScript}` 文件与 `Browser*Tests`；**同 PR 剥除 `Sources/Search/{GlobalSearchCoordinator,GlobalSearchPanelCaptureManager,AppDelegate+GlobalSearch}.swift` 的 browser 分支与 `Sources/Find/FindTextFieldSupport.swift:104` 的 browser fallback**（否则引用已删 `BrowserPanel`、编译失败）。`Sources/Find/` 终端查找三文件不动。
- [ ] **步骤 4**：门控 G + 旧快照回归（含 browser panel 的 session 能正常降级恢复）。

**Phase 3**：其余非终端 Panel（markdown / filePreview / project）
- [ ] **步骤 1**：断入口（创建路径、命令、快捷键），编译通过。
- [ ] **步骤 2**：删 `PanelType.{filePreview,project}` + intent，补齐各 `case`（**保留 `PanelType.markdown` 及全部 `Markdown*.swift`/markdown 渲染资产**）；删 filePreview/project 文件与 `CMUXProjectModel`（**保留 `FilePreviewTextEditingPanel` 协议——markdown 仍用**）；删 `Resources/markdown-viewer/` 的 **diff-viewer 子目录**（`diff-viewer/`、`diff-viewer-app/`，**不删** markdown 资产）；**删 `diff-viewer/` 顶层目录 + `scripts/{build-diff-viewer-app.sh,check-diff-viewer-react-compiler.mjs,open-diff-viewer-stress-samples.sh}` + `ci.yml:139-159` diff-viewer job + CLI runtime（`cmux.swift:2991` `diff-viewer-server`/`runDiffViewerServerCommand`、`cmux_open.swift` 的 `cmux-diff-viewer` server/asset 服务）**；删 `scripts/verify-cmd-click-file-previews.sh`（验的是已删的 filePreview，且读 `web/public` fixture——一并去免得 Phase 8a 删 web/ 时再处理）。
- [ ] **步骤 3**：门控 G + 旧快照回归。

**Phase 4**：旧右侧栏 modes + Feed 面板 UI（保留管道）
- [ ] **步骤 1**：删右侧栏 surface **整片**——`Sources/RightSidebar*.swift`（含 `RightSidebarRemoteCommand.swift`，本 phase 拥有）/`FileExplorer*.swift` + `AppDelegate` 的 `FileExplorerState`/`applyRightSidebarRemoteCommand` + `Workspace` 的 `RightSidebarToolPanel`/`SessionRightSidebarToolPanelSnapshot` + 快捷键/本地化/测试；**（审查 R2）删 `right_sidebar` CLI/socket 入口**——`CLI/cmux.swift` 的 `right-sidebar` 解析/转发/help（`:3114/4600/5084/14492` + `:14937` `forwardRightSidebarCommand`）+ `TerminalController` 的 `right_sidebar` gate/dispatch/handler（`:363/370/1407/1590`）+ `:20407-20448` 的 parse/`applyRightSidebarRemoteCommand`/测试 seam `parseRightSidebarRemoteRequestForTesting` + `debug_right_sidebar_focus`（`:171/193/1679`）+ `cli.rightSidebar.*`/`rightSidebar.remote.error.*` 本地化 + `cmuxTests/TerminalControllerSocketSecurityTests.swift:812+` 的 `right_sidebar` socket 测试 + right-sidebar/dock docs topic（否则引用已删 `RightSidebarRemoteRequest`/`rightSidebar(args)`、编译失败）；删全局搜索 **整片**——`Sources/Search/` + `AppDelegate` start/菜单 + `MenuBarExtraController` 项 + `KeyboardShortcutSettings`/`CmuxSettings` 的 `.globalSearch` action + `SearchIndexTests`（Phase 2 已去 browser 耦合）。**`Sources/Find/` 三个终端查找文件全部保留**（`SurfaceSearchOverlay`/`TerminalSearchOverlayHostingView`/`FindTextFieldSupport`），本 phase 不删 `Sources/Find/` 任何文件。
- [ ] **步骤 2**：仅删 `FeedPanelView*` 与 Feed 调试窗；**保留** `FeedCoordinator.ingestBlocking/deliverReply` + `CMUXWorkstream` + `v2FeedPush` + `ChatRoomController`。
- [ ] **步骤 3**：门控 G + **聊天回复回归**（@mention → claude/codex 回复仍回到 room；终端查找仍可用）。

**Phase 5**：侧边栏扩展 / 自定义渲染平台（seam 已定位：`extensionSidebarScrollArea` 喂 SwiftRender，非 `workspaceScrollArea`）
- [ ] **步骤 1**：断 `extensionSidebarScrollArea()`（`ContentView:11220`）+ provider 切换（`:10960-10962`）+ `import CmuxExtensionSidebarExamples`（`:7`），确认 room 侧边栏走 `workspaceScrollArea()`（`:11056`），编译通过。
- [ ] **步骤 2（审查 R1.1/R2.2：同 PR 删整条 `extensionBrowser` panel surface）**：删 `PanelType.extensionBrowser`（`Panel.swift:13` + arms）、`Workspace.newSidebarExtensionBrowserSurface`（`:15030`）+ 各 `case .extensionBrowser`、`PanelContentView` 分支、`AppDelegate.openSidebarExtensionBrowser`（`:13732`）、`UpdateTitlebarAccessory.swift:943` **和 `MinimalModeSidebarControls.swift:198`（审查 R1.1）** 的 `CmuxExtensionSidebarSelection.showMenu` 调用、`SessionPersistence` 的 extensionBrowser snapshot 字段、相关快捷键/本地化/测试；🗑️ `CMUXSidebarExtensionBrowserPanel.swift`/`CMUXInstalledExtensionSidebarHostView.swift`/`ExtensionSidebarWorkspaceRowView.swift`/`ExtensionWorktreePrototype.swift`。
- [ ] **步骤 3（审查 R2：custom-sidebar socket/CLI/设置全切片，同 PR）**：删 `TerminalController` 的 `sidebar.custom.{validate,reload,select}`（`:911-913` 注册 + `:1095` dispatch + handler `:4129/4150`）与 `extension.sidebar.snapshot`（`:1929/2418`）+ 本地化；删 `CLI/cmux.swift:15022/15042` 的 `cmux sidebar custom` 命令/help；删 beta 设置 `customSidebars`（`BetaFeaturesCatalogSection.swift:44`/`BetaFeaturesSection.swift:92`/`CuratedSettingEntry+Default.swift:105` + schema/本地化/测试）；删 `CMUXCLI+DocsSettings.swift:118` 的 `sidebars` docs topic + `docs/events.md` 扩展侧边栏段落；🗑️ `docs/custom-sidebars.md`、`docs/data-driven-sidebar-plan.md`。
- [ ] **步骤 4**：删 `CmuxExtensionKit`/`CMUXExtensionHostSupport`/`CmuxSidebarProviderKit`/`CmuxSidebarInterpreterService`/`CmuxSwiftRender(UI)`、`CmuxSidebarActionDispatch.swift`、**`Examples/`（含 `CmuxExtensionSidebarExamples`）**。
- [ ] **步骤 5**：门控 G + 侧边栏（rooms+agents）渲染回归 + 旧含-`extensionBrowser` 快照降级恢复回归 + `cmux sidebar custom`/`sidebar.custom.*` socket verb 已从运行时注册表移除（行为级断言）。

**Phase 6**：配对 Mac 移动主机（打字延迟热路径，谨慎）
- [ ] **步骤 1**：diff 确认 `GhosttyTerminalView`/`TerminalController` 的 byte-tee 与 render-grid-frame **仅服务移动主机**；若有非移动用途，先把该值类型抽到 `CmuxFoundation`。
- [ ] **步骤 2**：删 `AppDelegate`/`TerminalController`/`GhosttyTerminalView` 的 mobile 引用与 `import CMUXMobileCore`；**（审查 R1.2）**删 `TabManager` 7 处 `MobileHostRequestActivity` 节流调用（`:1449/1708/1891/2862/2870/3065/3073`）+ `mobileHostBackgroundWorkQuietInterval`；删 Mobile 设置面（`MobileSection.swift`、`MobileCatalogSection` 的 `iOSPairingHost` 等 mobile 键 + schema/文档/本地化/测试）；再删 `Packages/CMUXMobileCore` + `Sources/Mobile/`。
- [ ] **步骤 3**：门控 G + **打字延迟主观验收**（在 agent 终端连续输入，无卡顿/回显延迟）+ 确认设置面无残留「iOS Pairing」死开关。**(需要手动操作)** — 需人眼/手感判断。

**Phase 7**：未用 agent 集成（窄）+ OMP + `cmux top`（文件级 split）
- [ ] **步骤 1（rovo/hermes/amp 全有全无，同 commit）**：删 hook config/extension 文件（`RovoDevHookConfig.swift`、`HermesAgentHookConfig.swift`、`CLI/CMUXCLI+{HermesAgentHooks,AmpExtension}.swift` + 测试）**同时**删 `AgentHookDef` 的 rovodev/hermes-agent/amp 三行 + `cmux.swift` 的 install/uninstall dispatch（`:26240-26247`/`:26601-26608`）+ `installRovoDevHooks`/`rovoDevHooksContent` 等函数 + `cmux hooks setup/uninstall {rovodev,hermes-agent,amp}` 入口/本地化（否则 `cmux.swift` 引用已删符号、编译失败）。**保留** `CMUXAgentVault/Providers/{RovoDev,HermesAgent}/*Index.swift`（会话索引，非 hook）、`RestorableAgentKind` 全部 case、`SessionAgentPresentation`/`SessionIndexStore/View` 的 rovo/hermes 分支。
- [ ] **步骤 2**：删 OMP **整套**：`CMUXCLI+OmpExtension.swift` + `CMUXCLI+AgentHookDefinitions.swift:203` 的 omp 条目 + `cmux.swift:26232` 调用 + `cmux hooks setup omp` 入口 + 测试/本地化 + `AgentKind.swift:3` 注释（不可半删）。
- [ ] **步骤 3**：删 `cmux top` 命令 + 其 UI；**保留** `CmuxTopProcess*.swift`/`CmuxTopSnapshot*.swift`/`TerminalControllerTopSupport.swift`。
- [ ] **步骤 4**：门控 G + 新建 codex + claude agent，确认 hook（回复/状态）正常。

**Phase 8a**：云 / Auth（独立 PR）
- [ ] **步骤 0（审查 R2.1）**：先迁出 `web/data/{cmux.schema.json,cmux-settings.schema.json,cmux-shortcuts.ts}` 到非 web canonical home + repoint `KeyboardShortcutSettingsFileStore.swift:28-29`/`+Template.swift:8`/`CMUXCLI+DocsSettings.swift:5/48`/`CMUXCLI+Config.swift:151` 的 schema URL，**再**删 `web/`。
- [ ] **步骤 1**：删 `Sources/Cloud/`、`CloudVMActionLauncher`、`Sources/Auth/`、`CMUXAuthCore`、`CmuxAuthRuntime`、`vendor/stack-auth-*` 及其 socket verb / 账户 UI / 回调；**删 CLI auth/login/logout（`cmux.swift:3338`）与 vm/cloud（`:3405`）dispatch + help（`:12840`）+ `stress-cli-socket-api.py` 条目**；**删 `web/` + `ci.yml` web-typecheck/web-db-migrations job + `cloud-vm-migrate.yml`/`cloud-vm-smoke.yml`**；**删 `tests_v2/` 的 cloud/auth/vm 套件（审查 R2.2）**；门控 G。

**Phase 8b**：Remote SSH + 会话 snapshot 迁移（独立 PR）
- [ ] **步骤 1**：删 remote SSH（`WorkspaceRemoteConfiguration`、`Remote*`、`WorkspaceRemoteSessionController`、相关 RPC/属性/字段、`AppDelegate+CmuxSSHURL`）；**删 `tests_v2/` 的非-daemon remote 套件（审查 R2.2：`test_ssh_remote_*.py` 中调 `workspace.remote.status` 等的，如 `test_ssh_remote_cli_metadata.py:342`/`test_ssh_remote_cli_relay.py`/`test_ssh_remote_port_detection.py` 等；需 `daemon/` 的留至 Phase 8c）**；门控 G + **含-remote 字段旧快照回归**（Phase 0 持久化层兜底，layout 净化，不崩）。

**Phase 8c**：`cmuxd` 守护进程（独立 PR）
- [ ] **步骤 1**：核实 `cmuxd` remote-only 后删 `daemon/`。**同 PR 镜像文件清单的全部 CI/script 清理**：🗑️ `scripts/build_remote_daemon_release_assets.sh` + 改 `scripts/prune_nightly_release_assets.py` 删 `cmuxd-remote-*` 模式（`:15-17`，审查 R2.4）；`.github/workflows/ci.yml:97`、`tmux-corpus.yml:7`、`release.yml:249`、`nightly.yml:397` 的 cmuxd job + `scripts/release_asset_guard.js` 的 `cmuxd-remote-*` 资产校验行（`:6-11`）+ 其 `release_asset_guard.test.js`；本地 dev 脚本 `scripts/reloads.sh`（`CMUXD_UNIX_PATH` 注入 `:236-237/:277`、`cmuxd` 构建/拷贝 `:259-267`）与 `scripts/reload.sh` 中同类 cmuxd 注入——一并删/停用，否则本地编译过但 CI/release/dogfood 仍带 stale daemon 行为。若暂不动 release/nightly，则**先显式停用 remote-daemon job** 再删 `daemon/`。**删 `tests_v2/` 的 daemon-依赖 remote 套件（审查 R2.2：`test_ssh_remote_daemon_resize_stdio.py:95` 等 require `daemon/`/remote 的）**。**再次确认未碰** `CmuxControlSocket`/`CmuxSocketControl`（CLI/hooks 的本地控制 socket，脊柱）；门控 G。

**Phase 9**：「Bus」对外更名（纯文案）
- [ ] **步骤 1**：改对外文案为 **Bus**（`CFBundleDisplayName`、About、窗口标题、`README.md`、`docs/`、本地化对外串）；**全程不碰** `cmux` CLI 名 / `CMUX_*` / socket / bundle id 基名 / 包名 / hook 协议 / `scripts/*`。
- [ ] **步骤 2**：`./scripts/reload.sh --tag prune-bus` 确认 hooks/CLI/dogfood 零回归（命令仍是 `cmux`）；门控 G；可选加 `bus` alias 转发 `cmux`。

**Phase 10**：`WorkspaceGroup` 退役 + 内部收缩（gated）
- [ ] **步骤 1（审查 R1：完整垂直切片，非一行）**：roomID 侧边栏稳定后——删模型/核心（**`TabManager` 的 `struct WorkspaceGroup`（`:1007`）+ group 设置类型（`:920`）**、`Workspace` 的 `groupId`/ungroup/anchor/`:10560` group config 解析；收缩 `TabManager`/`TerminalController` 旧分支）；🗑️ `TabItemView+WorkspaceGroups.swift`/`VerticalTabsSidebar+WorkspaceGroups.swift`/`WorkspaceGroupMenuSnapshot.swift`/**`SidebarWorkspaceGroup{HeaderView,Dialogs,ConfigOpener,HeaderMetrics}.swift`/`SidebarWorkspaceGroupingMetrics.swift`**；删 `ContentView`/`SidebarWorkspaceRenderItem` 的 group 渲染/右键菜单、`AppDelegate` 新建-入组路径；删 `SessionPersistence` 的 `SessionWorkspaceGroupSnapshot`+`workspaceGroups` 字段、`CmuxConfig` 的 `workspaceGroups`/`CmuxConfigWorkspaceGroups*`（`:19/157/165`）+ **设置 surface（`KeyboardShortcutSettingsFileStore.swift:372`/`+Template.swift:85`/`SettingsNavigation.swift:438`/`CmuxSettingsJSONPathSupport.swift:90`）** + `cmux.schema.json`（迁出后）/设置别名/本地化；🗑️ `docs/workspace-groups.md`；改/删相关测试。
- [ ] **步骤 2**：门控 G + 恢复/侧边栏/关闭不变量测试 + **旧含-`workspaceGroups` 会话回归**（恢复后 tab 顺序/平铺正常、无悬挂 `anchorWorkspaceId`，见测试计划）。

**Phase 11**：更新器 / 分发删除（D4，独立 PR）
- [ ] **步骤 1**：删 `AppDelegate` 的 `import CmuxUpdater(UI)`/`UpdateActionsHost` 装配 + `checkForUpdates(_:)` + `ContentView` update pill；**删 updater 入口**（`CmuxHelpCommands.swift:17` Help 菜单、`MenuBarExtraController.swift:33/277` 菜单项+action、`ContentView.swift:7001` 命令面板 `palette.checkForUpdates` + 本地化）；删 `Sources/Update/`、`Packages/CmuxUpdater(UI)`、`homebrew-cmux/`、updater 测试、Info.plist Sparkle 键；**改写 `scripts/build-sign-upload.sh` 去 Sparkle/appcast/homebrew（保留 DMG 构建签名公证上传）+ 改 `scripts/sign-cmux-bundle.sh:79` 删 `remove-sparkle-sandbox-xpc-services.sh` 调用（审查 R1：否则 release/nightly 签名步骤调已删脚本而断）+ 删 `tests/test_sparkle_xpc_cleanup.sh` + 删 orphan `sparkle_*`/`derive_sparkle_public_key.swift`/`remove-sparkle-sandbox-xpc-services.sh` + `release-pretag-guard.sh` 去 appcast 检查 + 删 `tests/test_ci_sparkle_build_monotonic.sh`/`test_nightly_universal_build.sh` Sparkle 部分**；停用 `update-homebrew.yml` 与 release/nightly 的 Sparkle/appcast 步骤、移除 `scripts/release_asset_guard.js` 的 `"appcast.xml"` 资产行 + 其 test（否则 `release.yml:72` 的 guard 仍要求 appcast 资产）；门控 G。

**Phase 12**：遥测 / 崩溃上报删除（D7，独立 PR）
- [ ] **步骤 1**：删 `GhosttyTerminalView.swift:13` 的 `import Sentry` + 全部 `SentrySDK`/`PostHog` 调用点；删 `PostHogAnalytics.swift`、`SentryHelper.swift` + pbxproj 包引用；**删用户可见遥测设置**（`CommandPaletteSettingsToggle.swift:310` 开关、`SettingsSearchAliases.swift:76` 别名、`AppSection.swift:536` UI 行、`CmuxSettings` 目录 `app.sendAnonymousTelemetry` + `TelemetrySettings` 模型、本地化、`GhosttyConfigTests.swift` 测试、`cmux.json` schema/文档）；停用 release/nightly 的 dSYM→Sentry 上传；**保留** `CMUXDebugLog`；门控 G。

> **D5 命令面板目录清理**：在每个删除 phase 内随手做（删哪个面就删它的命令条目），不单列 phase。

## 测试计划

> **重要**：
> - **自动化测试优先**：AI 代理可以直接运行测试脚本（如 `ui-test/scripts/run_test.sh`、`pytest`、`gradle test` 等），因此所有可以通过脚本执行的测试都应作为自动化步骤，由 AI 代理在实施步骤中直接执行，**不应归类为手动测试**。
> - **手动测试仅限于最后手段**：只有在以下情况下才使用手动测试：需要人眼视觉判断的 UI 验收、需要真实物理设备交互、需要人类主观评估（如动画流畅度、视觉美观度）等。运行脚本、执行命令行工具、查看日志输出等操作不属于手动测试。

本计划是**删除 / 重构**，核心验证不是新增单测，而是「删后仍编译、核心流仍工作、旧数据仍可迁移」的回归门控。绝大多数验证可脚本化自动执行（编入「实施步骤」的门控 G），仅打字延迟手感与 UI 视觉验收属于手动测试。**不新增伪回归单测**（CLAUDE.md「测试质量政策」：禁止只断言源码文本/存在性的测试）。

### 单元测试

新增覆盖**新可执行行为**。审查指出删除行为也需自动化覆盖（非仅手动），故分两类。

#### 1. `SessionSnapshotLenientDecodingTests`（Phase 0 恢复契约；Swift Testing）

须按 CLAUDE.md 写入 `project.pbxproj` 的 `cmuxTests` target（否则 CI「Executed 0 tests」静默漏测）。**fixture 加载**：当前 `cmuxTests` 的 Resources build phase 为空（`project.pbxproj:2378`）——须把 `cmuxTests/Fixtures/*.json` 加入该 phase，或用 `Bundle.module`/相对路径读取，**否则 fixture 在 CI 取不到**。

```swift
@Suite struct SessionSnapshotLenientDecodingTests {
    // 持久化层（不涉及运行时 PanelType）
    @Test func droppedPanelTypeIsSkippedNotThrown()   // 旧 "browser"/"filepreview" panel → 丢弃，其余 panel 正常解出
    @Test func keptMarkdownPanelRestoresNotDropped()  // 旧 "markdown" panel → 正常恢复（markdown 保留，不在 drop 集）
    @Test func currentSnapshotRoundTripsUnchanged()   // 当前格式 encode→decode 不变（不回归）
    // 恢复契约（layout/focus/selected 净化）
    @Test func unknownSelectedPanelIsRemapped()       // selected 指向已删 panel → 重映射到幸存集合
    @Test func unknownFocusedPanelIsCleared()         // focusedPanelId 指向已删 panel → 清空/重映射
    @Test func splitWithOneSideRemovedCollapses()     // 分屏一侧 panel 被删 → layout 坍缩为单 pane
    @Test func workspaceLosingAllPanelsFallsBackToTerminal() // workspace 丢光 panel → 回退一个新建空终端，不留空白
    @Test func legacySnapshotWithRemoteFieldsRestores()      // 含 remote 字段旧快照 → 窗口/tab 恢复，remote 忽略
    @Test func droppedRightSidebarToolAndExtensionBrowserSkipped() // 审查 R2.1/R2.2：含 rightSidebarTool / extensionBrowser panel 旧快照 → 丢弃，其余正常
}
```
- fixture：脱敏的真实旧 `session-*.json` 拷贝置 `cmuxTests/Fixtures/`，**被删类型**覆盖 **browser/filePreview/project/rightSidebarTool/extensionBrowser/remote** + layout/selected 指向已删 panel（审查 R2.1/R2.2）；**保留类型**须含一个 `markdown` panel 验证它**正常恢复**（不被丢弃）。

#### 2. 删除切片的行为级回归（自动化，编入门控 G）

按 CLAUDE.md「测试质量政策」**不写「源码不含 X」文本断言**；改为断言**可执行行为**：
- **命令面板 / socket verb 清理**：每个删除切片后，运行时枚举命令面板可见命令 / V2 socket method 列表，`#expect` 不含已删面的条目（断的是运行时注册表，非源码 grep）。
- **Feed 管道存活**：Phase 4 删 Feed UI 后，注入一条 `feed.push` Stop 事件，`#expect` `ChatRoomController` 仍把回复挂到对应 exchange（`FeedCoordinator.ingestBlocking/deliverReply` 未被误删）。
- **`WorkspaceGroup` 退役不变量**（Phase 10）：构造含 group 的旧会话，恢复后 `#expect` tab 顺序/关闭/侧边栏分组语义符合 roomID 模型，无悬挂 `anchorWorkspaceId`。
- **resume/fork argv 存活**（若执行 Phase 1B）：`#expect` `AgentResumeArgv`/`RestorableAgentSession` 对 claude/codex 仍生成正确 resume argv。
- **`tests_v2/` 套件归属（审查 R2.2）**：`scripts/run-tests-v2.sh:224` glob 全部 `tests_v2/test_*.py`，故**每个删除 phase 必须连带删除其对应的 v2 套件**（Phase 2→`test_browser_*`/`test_cli_browser_*`/`test_ssh_remote_browser_*`；Phase 8a→cloud/auth/vm；Phase 8b→非-daemon `test_ssh_remote_*`；Phase 8c→daemon-依赖的）+ helper/docs 引用；**保留**终端/分屏/聊天室的中性 v2 覆盖。否则全量 v2 在功能删除后永久红、或仓库留下对已删 API 的死测试。

### 手动测试（仅人眼 / 手感验收，最后手段）

> 每个 phase 末尾，tagged app（`cmux DEV prune-bus`）启动后执行。除 Phase 6 打字延迟外，其余「能否操作/有无报错」其实可由日志判断，但 room/agent 的视觉完整性仍建议人眼过一遍。

#### 场景 1：聊天室核心流（每 phase 后）
- [ ] **步骤 1**：新建一个 room，在其中新建一个 claude agent 与一个 codex agent。
  - **预期**：两个 agent tab 出现在该 room 下，终端可交互。
- [ ] **步骤 2**：`@all` 发一条 prompt。
  - **预期**：两个 agent 各自终端收到 prompt；各自**最终回复回到该 room 的 channel**，绿色 spinner→回复，无截断 `…`。
- [ ] **步骤 3**：在某 agent 终端按终端查找快捷键。
  - **预期**：`SurfaceSearchOverlay` 仍可用（Phase 4 之后重点验）。
- [ ] **步骤 4**：退出并重开 app。
  - **预期**：room + 两个 agent tab 恢复；claude tab **恢复为已 resume 的会话**而非裸 shell（依赖此前的 resume-binding 修复）。

#### 场景 2：旧快照迁移（Phase 2 / 3 / 8② 后）
- [ ] **步骤 1**：把一份**删除前**保存、含 browser/filePreview/remote（已删类型）**及一个 markdown（保留类型）** panel 的 `session-com.cmuxterm.app.debug.prune-bus.json` 放回 app-support 目录，重开 app。
  - **预期**：app 正常启动，已删类型 panel 被静默丢弃，**markdown panel 正常恢复并能渲染（含 mermaid）**，其余窗口/tab/room 正常恢复，不崩、不空白。

#### 场景 3：打字延迟手感（Phase 6 后）**(需要手动操作)**
- [ ] **步骤 1**：在 agent 终端快速连续输入一段文本。
  - **预期**：无可感知的回显延迟或卡顿（移动 byte-tee 移除只应减负载）。

#### 场景 4：更名零回归（Phase 9 后）
- [ ] **步骤 1**：确认 About / 窗口标题 / Dock 名显示 **Bus**。
  - **预期**：对外是 Bus。
- [ ] **步骤 2**：在 agent 终端运行 `cmux list-workspaces`（CLI 名仍是 `cmux`）。
  - **预期**：CLI/hook 正常工作，命令名未变。

---

## 规则优先级
> **⚠️ 不可修改**：以下规则部分必须包含在每个计划文档中，AI 和开发者不得修改此部分.

<!-- 规则优先级：开始 - 此部分不可修改 -->
- 计划生成规则和计划执行规则优先于模型的隐式行为
- 当任务指令与计划生成规则或计划执行规则冲突时，必须遵循这些规则
- 如果由于任务约束无法遵循计划生成规则或计划执行规则中的某条规则，应暂停并请求澄清，而不是猜测
- 如需覆盖这些规则，应更新计划模板文档，而不是在单个计划文档中覆盖

<!-- 规则优先级：结束 -->

## 计划生成规则
> **⚠️ 不可修改**：以下规则部分必须包含在每个计划文档中，AI 和开发者不得修改此部分.

<!-- 计划生成规则：开始 - 此部分不可修改 -->
- **作者**字段必须填写 GitHub 用户名（通过 `gh api user -q .login` 获取），不得使用 "claude_code"、"AI" 等非人类标识符。此字段用于追踪计划质量归属
- AI 生成的计划文档必须包含计划模板中的所有部分，标记为"（如适用）"的部分是可选的，开发者可以选择主动删除
- 开发者可以根据需要添加或删除部分
- 所有 "**重要**：" 部分必须从模板中复制，不得修改或省略
- **当前计划完整程度**初始应留空，AI 不得自动填写百分比。随着开发者做出决策并解决"需要决策的事项"部分中的问题，AI 应更新此百分比
- **大小**, **实施步骤**, **埋点事件分析**, **错误跟踪**, **需要修改/添加的文件**, 和**测试计划**部分初始应留空，仅当以下条件全部满足后才生成和更新内容：
  - 参考资料部分（参考资料）已完整
  - 需要决策的事项部分（需要决策的事项）中无未解决的问题
  - 当前计划完整程度达到或超过 95%
- 用户做出决策后：
  - 必须将决策保存到已归档的决策部分
  - 如果**实施步骤**, **埋点事件分析**, **错误跟踪**, **需要修改/添加的文件**, 和**测试计划**部分不为空，必须更新这些部分以反映新的决策
- 当以下条件全部满足时，AI 必须自动将**当前计划完整程度**更新为 100%：
  - **需要决策的事项**部分中没有未解决的问题（所有决策已归档）
  - **需要修改/添加的文件**部分中所有文件的复选框都已勾选（已审查）
<!-- 计划生成规则：结束 -->

## 计划执行规则
> **⚠️ 不可修改**：以下规则部分必须包含在每个计划文档中，AI 和开发者不得修改此部分.

<!-- 计划执行规则：开始 - 此部分不可修改 -->
- 除非以下条件全部满足，否则 AI 必须拒绝执行计划，不得有任何例外：
  - 计划完整程度达到或超过 95%
  - 需要修改/添加的文件部分中的所有新增和修改文件都已标记为已审查
- **最小变更原则**：
  - 仅修改任务直接要求的代码
  - 除非明确要求，否则不得重写、重新排序或重构不相关的文件或模块
  - 除非必要，否则不得修改空白字符（不删除空行、不添加空行、不更改缩进或格式）
  - 保留所有现有的命名、风格、模式和架构
  - 不确定是否需要额外的自定义逻辑、抽象或新结构时，应停止并请求人工确认，而不是发明新机制
- **注释质量原则**：
  - 不要生成重复代码内容的注释
  - 不要描述函数名、参数名、返回类型或基本逻辑（循环、空值检查、简单条件判断）
  - 仅在解释**为什么**时添加注释，而非解释**是什么**
  - 允许的注释内容：非显而易见的逻辑或行为、关键假设或约束、平台特定问题、副作用或生命周期交互、代码中不明显的重要推理
  - 宁愿**不添加注释**，也不要添加无意义或冗余的注释
  - 所有注释必须使用**简体中文**编写
- **禁止 TODO 原则**：
  - 不得编写 TODO、FIXME、XXX 或占位符注释
  - 不得留下存根实现、空代码块或未实现的函数
  - 生成的每段代码必须完整、具体且可在上下文中运行
  - 如果无法完全实现某项功能，应停止并请求澄清，而不是猜测或留下占位符
- **任务范围原则**：
  - XS/S/M/L/XL 计划的代码生成应一次性完成，不分阶段
  - XXL/XXXL 计划适用于由 AI Agent 主导执行的大型任务，必须分阶段完成，每个阶段结束后运行完整单元测试和 UI 测试以确保质量
  - 无需考虑渐进式迁移策略，应直接完整实现所需功能
<!-- 计划执行规则：结束 -->
