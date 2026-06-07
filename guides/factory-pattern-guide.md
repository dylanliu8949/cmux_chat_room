# Factory 模式指南

## 什么是 Factory

Factory 是 UI 模块中页面的组合根（composition root）。它负责三件事：

1. **创建基础设施**：RenderEngine、ExportRenderer、应用页面配置等
2. **创建父级协调 VM**（仅当页面需要跨兄弟组件协调时）：例如 `EditorPageViewModel` 持有选中状态、panel 导航状态等跨 feature 的 UI 状态
3. **组装布局**：按布局结构拼装 feature composable

**Factory 不创建 feature 级 ViewModel**。每个 feature composable（`TextPropertiesBar`、`LayersPanel`、`ColorPickerPanel` 等）在自己的函数体内通过 `viewModel { }` 创建自己的 VM。这是 Compose 官方模式，详见 [mvvm-guide.md](mvvm-guide.md) §"View 层规范"。

Factory 是页面的唯一 public 入口。所有 feature composable、父级 VM、子组件都是 internal——App 层只需调用 Factory。

文件名约定为 `*Factory.kt` 或 `*Factory.swift`，位于 UI 模块根目录。

```
EditorFactory.kt (public)
├── 创建 RenderEngine、ExportRenderer
├── 应用 EditorPageConfiguration 到 RenderEngine
├── 创建 EditorPageViewModel（父级协调 VM：选中状态 + panel 导航状态）
└── 组装布局：NavigationBar + CanvasView + ContextMenu + TabBar + (当前激活的 Panel)
    └─ 每个 feature composable 内部自己创建自己的 feature VM
```

当页面需要变体（实验、平台适配、迁移）时，Factory 扩展为选择器：

```
HomePageFactory.kt
├── createHomePage()                    // public，入口，检查 flag 和条件
├── createHomePageWithGiantBanner()     // private，实验变体
├── createHomePageWithSmallBanner()     // private，实验变体
├── createPhoneHomePage()              // private，平台变体
├── createTabletHomePage()             // private，平台变体
└── createDesktopHomePage()            // private，平台变体
```

## 适用场景

- **页面组合根**：每个页面都应有一个 Factory 作为唯一 public 入口，负责创建基础设施、ViewModel 和组装布局。即使当前只有一个变体，Factory 也确保了页面的 ViewModel 和子组件保持 internal。
- **实验（Experiment）**：每个实验有一个 flag，改变页面的视觉或行为。实验是短命的（几周），失败后整个变体函数及其专属的 ViewModel、View 一起删除。
- **多平台适配**：不同平台（Phone / Tablet / Desktop）需要不同的页面布局和交互。每个平台有自己的 create 函数、ViewModel 和 View。
- **大规模迁移**：新旧实现并存期间，Factory 通过 flag 控制流量切换。迁移完成后删除旧变体。

## 为什么 Factory 不受常规规则约束

常规规则（DRY、YAGNI、KISS、最小变更面）优化的是长期代码健康。Factory 管理的变体生命周期不同——实验几周后删除，平台变体在统一布局后合并，迁移完成后旧版本被清理。

如果在变体之间提取共用逻辑，删除一个变体时需要检查共享代码是否还被其他变体使用，清理变成考古。变体之间保持独立，即使存在大量重复，删除就是 `git rm` 一个 create 函数和它专属的 ViewModel/View 文件。

## 为什么不在 ViewModel 里做

在 ViewModel 里用 if/else 管理变体是常见错误。结果是：

- ViewModel 膨胀，充满条件分支，没人知道"干净版"长什么样
- 删除一个实验意味着从 500 行 ViewModel 中外科手术式地移除 if 分支
- 多个实验的条件交叉，复杂度指数增长

Factory 让 ViewModel 保持干净——每个 ViewModel 只知道一个版本的现实。Factory 决定创建哪个 ViewModel。删除变体 = 删除 create 函数 + 删除专属 ViewModel/View。

## 为什么不在 Factory 里创建 feature VM

同样的「把 VM 提升到 Factory」也是常见错误。结果是：

- 违反 Compose 官方模式：*"Try to avoid passing down ViewModel instances to other composables as this can make those composables more difficult to test and can break previews."*（[Android docs](https://developer.android.com/develop/ui/compose/migrate/other-considerations)）
- Feature composable 失去独立性：无法 preview、无法在其他页面复用、无法被集成测试单独挂载
- Factory 必须知道每个 feature 的 VM 构造参数，耦合度爆炸
- 变体切换时需要同时切换 create 函数和 VM 参数传递，删除成本变高

正确做法：feature composable 自己在函数体内 `viewModel { }` 创建 VM。Factory 只创建**父级协调 VM**（通常一个就够，例如 `EditorPageViewModel`），用它统一管理 feature 之间的导航/可见性状态。跨 feature 的协调见 [mvvm-guide.md](mvvm-guide.md) §"跨兄弟组件协调"。

## 生命周期

1. **创建 Factory**：当一个页面或组件需要第一个变体时（第一个实验、第一个平台适配），创建 Factory 文件
2. **添加变体**：每个新实验/平台/迁移方案添加一个 private create 函数和专属的 ViewModel/View
3. **删除变体**：实验失败或迁移完成，删除对应的 create 函数及其专属文件
4. **删除 Factory**：当所有实验结束、只剩一个最优变体时，删除 Factory，将获胜的 ViewModel 和 View 提升为标准实现

## 规则豁免

**豁免范围严格限定：只有 variant create 函数及其专属子组件不受 DRY/YAGNI/KISS 约束。** Factory 中的基础设施创建、布局组装、父级协调 VM 创建等**普通代码**遵守项目常规规则。

variant 部分豁免以下规则：

- **DRY**：变体之间的代码重复是有意为之
- **YAGNI**：为每个变体创建专属 ViewModel/View 是必要的，即使当前只有一个调用方
- **KISS**：多个 create 函数比一个带有复杂条件的函数更好
- **最小变更面**：添加变体会新增多个文件，这是预期行为

审查和打磨 variant 函数时：不要标记变体之间的重复为"重复造轮子"，不要建议提取变体之间的共用逻辑，不要质疑变体专属组件的存在，不要建议合并变体。

**判断标准**：如果 Factory 当前只有一个变体（像 `EditorFactory.kt`），那它实际上只是 composition root，**没有任何部分享受豁免**。豁免是为真正存在多变体的场景准备的。

## 现有 Factory

| Factory | 模块 | 职责 |
|---------|------|------|
| `EditorFactory.kt` | `editor-phone-ui` | 编辑器页面组合根：创建 RenderEngine/ExportRenderer、应用 EditorPageConfiguration、创建父级协调 VM `EditorPageViewModel`（持有选中状态和 panel 导航状态）、组装页面布局（NavigationBar + CanvasView + ContextMenu + TabBar + 当前激活的 Panel）。Feature 级 VM 由各自的 composable 内部创建。当前只有一个变体（手机端），未来可扩展为 Phone/Tablet/Desktop 变体。 |
