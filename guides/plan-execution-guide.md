# Ralph 计划执行指南

本文档为 max_full_send Phase 1（代码生成）提供 Ralph 特有的操作约束。代码质量、风格、架构等方面的规范已存在于代码库中（`guides/encyclopedia.md` → 各模块 `architecture.md`），无需在此重复。

## 参考资料

- `guides/code-review-guide.md` — 代码审查标准（架构、正确性、安全性、测试覆盖等 13 个审查维度）
- `guides/naming-guide.md` — 命名规范（模块/文件/类/函数/测试命名约定）

## 文件导航

计划文档和参考资料中列出的文件路径可直接使用 Read 工具读取，优先按路径直接读取而非搜索。

- 如需查找计划中未列出的文件，使用 `guides/encyclopedia.md` → 对应模块的 `architecture.md` → 直接导航到目标文件
- Glob/Grep 应作为最后手段——每次搜索都消耗一个 turn，应优先将 turn 预算用于编写代码

## 上下文管理

计划文档已作为 prompt 的一部分传入，不需要从磁盘重新读取。

- 按需读取参考文件——实现每个步骤时只读取该步骤需要的参考文件，避免一次性读取所有参考文件导致上下文膨胀
- 不要重复读取已读过的文件，除非需要验证刚刚做出的编辑
- 上下文压缩后需要重新读取的文件应仅限于当前步骤需要的文件

## 日志

日志是 Ralph 自主调试的关键基础设施。Ralph 在运行时没有人类在场，当出现问题时，日志是唯一的诊断手段。生成的代码中应包含充足的日志，让 Ralph 能通过日志追踪代码的执行路径。

参考现有代码中的日志模式（Kotlin: `Logger.logDebug(TAG, msg)`, Swift: `logger.logDebug(tag:message:)`, Python: `print()`）。

## 注释质量

代码注释必须独立于计划文档自解释。计划执行后可能归档、删除或重写，因此生成代码中禁止留下只引用计划上下文的注释，例如 `// 决策 11 / 14：...`、`// plan Q2=B ...`、`// Decision #3 ...`、`// Phase 3 ...`、`// 阶段 2 ...`、`// 第三阶段 ...`。

如果确实需要注释，直接写代码旁的原因：为什么这里要这样做、有什么非显而易见的约束、哪个运行时行为会出问题。不要把解释压缩成计划中的决策编号、阶段编号或选项代号。

## View / ViewModel / Service 边界

计划执行时必须严格区分三层职责，避免为了“让按钮工作”而把逻辑塞进错误的层。边界与测试策略的完整规范见 [how_to_write_stable_unit_test.md](/Users/dylanliu/work/vibe-coding-editor/unit-test/docs/how_to_write_stable_unit_test.md)。

- **Service 层**：承载可复用业务逻辑、规则、批量数据变换、几何计算、选择语义和工作流
- **ViewModel 层**：负责 view state、交互编排、菜单/按钮状态以及对 Service API 的调用委托
- **View 层**：负责渲染和事件转发

执行计划时如果不确定逻辑该放哪一层，优先判断它是否脱离当前 UI 仍然成立、是否可能被多个调用方复用；如果是，优先下沉到 Service 层。

## ViewModel 单元测试规则

关于 fixture、dispatcher、timed case 隔离、shared helper 和 assertion 目标的完整规范，统一遵循 [how_to_write_stable_unit_test.md](/Users/dylanliu/work/vibe-coding-editor/unit-test/docs/how_to_write_stable_unit_test.md)。

这里仅保留执行期硬约束：

- 新增 ViewModel 测试时，优先复用同模块内已有稳定测试文件的模式
- 不要为了一个 timed case 改写整份稳定测试文件的共享 harness
- 如果计划包含单元测试，参考资料中应包含该指南

## 计划执行验证边界

计划执行阶段只负责完成计划中明确要求的实现、测试和局部验证。全局 PR 收尾检查（覆盖率、单元测试、lint、架构文档同步、commit/push、PR 描述）由 `/pr` 统一负责，避免每个计划模板重复绑定同一套 PR gate。

## 禁止 Git 操作

AI agent 不得执行任何 git 操作（`git add`、`git commit`、`git push`、`git checkout` 等）。所有 git 操作由 ralph_full_send 的 Python 编排层负责。
