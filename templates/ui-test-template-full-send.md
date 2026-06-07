# [功能名称] — UI 测试计划

**关联主计划**：`plans/[主计划名称].md`（主计划的「关联 UI 测试计划」字段必须反向引用本文件）
**状态**：[create-plan-in-progress|create-plan-complete|review-plan-in-progress|review-plan-complete|plan-execution-in-progress|plan-execution-complete|manual-test-in-progress|manual-test-complete|automated-ui-test-in-progress|automated-ui-test-complete|code-review-in-progress|code-review-complete|merge-complete|abandoned]

> **状态说明**：参见 `templates/plan-template.md` 头部「状态说明」表格。UI 测试计划与主计划共用同一套 14 值枚举和门控规则。

## 功能概述

简要描述功能的用户可见行为，重点关注 UI 交互和可测试的操作。

> **重要**：
> - 描述用户可以执行的具体操作（点击、拖动、选择等），而不是内部实现细节
> - 列出所有 UI 变更：新增按钮、菜单项、对话框等，包含其 AccessibilityId
> - 说明按钮/菜单项的显示条件（什么时候可见、什么时候隐藏）
> - 说明操作后 UI 的预期响应（状态切换、菜单更新等）
> - 如果功能涉及序列化/debug server 数据，说明返回的 JSON 结构和类型名称（测试通过 debug server 验证状态）

### UI 变更

[列出所有 UI 变更]

### 序列化

[说明 debug server 返回的数据结构]

## 参考资料

> **重要**：
> - 必须包含 `ui-test/docs/how_to_write_stable_ui_test.md` 和 `ui-test/docs/architecture.md` 并标记为（**必读**）
> - 必须包含所有会用到的 framework 模块文件路径，并在每个路径后用括号注明该文件提供的关键 API（函数名 + 参数签名）
> - 必须包含 `ui-test/framework/utilities/models.py` 并说明现有的数据模型（`Element`, `ImageElement`, `TextElement`, `CanvasState` 等）
> - 必须包含 `ui-test/framework/app/gesture.py` 并列出可用手势 API（`select_all()`, `deselect_all()`, `drag()`, `drag_resize_handle()`, `drag_rotation_handle()`, `pinch_to_zoom()` 等）
> - 必须包含 `ui-test/framework/app/pages/editor/` 下所有会用到的页面模块（context_menu, nav_bar, tab_bar 等），并列出每个模块的关键函数
> - 包含 1 个现有 e2e test 或 feature test 作为参考（`ui-test/e2e-tests/editor_e2e_1_test.py`）
> - 包含 `guides/encyclopedia.md` — 文档索引
> - 如果功能需要新的 framework 模块或 API，必须在参考资料中说明将参考哪些现有模块的模式

[列出参考资料]

## 测试文件命名规则

> **⚠️ 重要**：测试文件名必须与主计划文件名一致，格式为 `feature-tests/{plan_name}_test.py`，其中 `plan_name` 是主计划文件名（去掉 `.md` 后缀，连字符替换为下划线）。
>
> 例如：主计划 `plans/text-selection-drag.md` → 测试文件 `feature-tests/text_selection_drag_test.py`
>
> 这是因为 `max_full_send.py` 的 `_derive_ui_test_file()` 会从计划名推导测试文件路径。如果计划中引用的文件名与推导结果不一致，会导致 UI test loop 找不到测试文件而失败。

## 需要修改/添加的文件

> **重要**：
> - 如果需要新的 Python 数据模型（如新的 Element 子类），必须详细说明：dataclass 字段、`from_json()` 路由分支、需要处理的 JSON wrapper 类型名
> - 如果需要新的页面交互函数（如 `group_elements(gesture)`），必须说明：函数签名、调用的底层 API（如 `_tap_context_menu_button(gesture, "button_id", "Button Label")`）
> - 对于每个需要修改的 `__init__.py`，必须说明需要添加到 import 和 `__all__` 的名称
> - 测试文件的修改说明应按 Step 拆分，不要只写"按上方步骤编写测试"

[列出文件]

## 测试步骤

> **重要**：
> - 每个 Step 必须拆分为「操作」和「验证」两部分
> - 「操作」必须使用具体的 framework API 名称（如 `gesture.select_all()`、`context_menu.group_elements(gesture)`），不要用模糊描述
> - 「验证」必须通过 `debug_client.get_canvas_state()` 获取状态并断言具体字段（元素数量、类型、属性值）
> - 涉及元素重叠/遮挡的场景，必须注明处理策略（如 `send_to_back()` 或通过坐标偏移点击）
> - 涉及变换验证（move/rotate/resize）时，必须说明：记录变换前的值 → 执行操作 → 断言值发生变化（使用容差比较）
> - Undo/Redo 测试必须说明每步 undo/redo 后的预期状态（元素数量、类型、结构）
> - 前置条件必须明确（如：App 启动 → 验证在主页 → 点击 Release 按钮进入编辑器）
> - 测试代码必须是平台无关的 — 平台选择由 max_full_send 的 `--platform` 参数控制，测试本身不应包含任何平台特定逻辑

前置条件：[描述测试的前置条件]

Step 1: [步骤名称]
- 操作：[具体操作，使用 framework API 名称]
- 验证：[具体验证条件，使用 canvasState 断言]

Step 2: [步骤名称]
- 操作：[具体操作]
- 验证：[具体验证条件]

## 实施步骤

> **注意**：AI 代理应在完成每个步骤时勾选对应的复选框

- [ ] **步骤 1**：[修改 framework 文件 — 具体说明]
- [ ] **步骤 2**：[更新 __init__.py 导出]
- [ ] **步骤 3**：[创建测试文件 — 按上方 Step 编写测试代码]

## 文件导航规则

- 本计划的 参考资料 与 需要修改/添加的文件 已列出可直接读取的路径。**直接用 Read 读取这些路径，不要用 Glob 确认它们是否存在。**
- 如需查找本计划中未列出的文件，使用 `guides/encyclopedia.md` → 找到相关 architecture doc → 从中获取文件路径 → 直接读取。
- Glob/Grep 仅作为最后手段 — 每次搜索都会浪费一次可用于写测试的轮次。
