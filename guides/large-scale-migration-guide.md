# 大规模迁移指南

## 核心原则

本仓库默认采用 **大规模 clean-to-clean 迁移**：一个 PR 内完成数据模型 / wire 格式 / API 的完整切换，包括所有读写方、测试、文档。**不接受中间过渡状态**——代码库要么是"旧的，干净"，要么是"新的，干净"，不能停在两者之间。

即便 diff 超过 10k–20k 行也按一个 PR 走。AI 辅助让大规模机械重构变得可行；codex / review 工具建议"为了 reviewability 拆开"时也不拆——已显式接受大 diff。

## 为什么

### 1. 端到端可测

许多迁移只有完成后才能真正端到端测试。半完成状态下，数据已切到新形态但 UI 还在读旧形态，或者反过来——UI 测试 / 手动测试都跑不通，因为"一半的动作走不通流程"。等到全切完才有 testable surface，反而不如一次到位。

### 2. 不行就抛弃整个分支

一个大 PR 试出来不对，`git checkout main` + 删分支即可，0 成本。半迁移状态合进 main 之后想回头：要么把半迁移的代码再清掉（双倍代价），要么继续把它做完（被迫扩 scope）。clean-to-clean 是唯一让"抛弃"始终便宜的策略。

### 3. 代码库始终 CLEAN

代码库本身是 agent 的训练数据。任何过渡期的"两份并存 / 字段名带 `Old` / `// TODO 等迁移完删掉` / `@Deprecated` 标记 / version-bump-and-migrate-on-load" 都会被下一个 agent 当作合法 pattern 模仿。维持代码库的洁净不是代码风格洁癖，是给后续 agent 提供干净的范本。

### 大前提

- **本项目是 prototype mobile app，尚未在 App Store / Play Store 发布**，没有需要"前向兼容旧版本本地存储"的已安装用户。Compiled binary 的"向后兼容"是 server / API 层的问题，不是 in-app 代码库的问题。
- AI 辅助重构使得 10k–20k 行的机械改写成为周级工作，而不是月级工作。手动时代不可行的策略在 AI 时代变成了默认选项。

## 怎么做

标准动作（一个 PR 内）：

1. **删旧类型**——不留 typealias、不留 `@Deprecated`、不留"兼容方法"
2. **替换所有读写方**——序列化器、UI、测试夹具、文档示例同一 PR 全部对齐
3. **重写相关单元 / UI 测试**——`check_unit_test_coverage.py` 强制每个 public/internal 函数有测，所以删旧函数 → 删旧测试 → 添新函数 → 添新测试是一组
4. **更新 `docs/architecture.md`**——架构文档必须反映新的真实状态，不能滞后

示例：把 `TextElement.attributedText` 切到 `TextElement.flow`

- ✅ 同一 PR 删 `attributedText` 字段、改 `SerializableTextElementWrapper`、改所有 UI、改测试、改文档
- ❌ Phase 1 加 `flow` 字段保留 `attributedText`、Phase 2 把 UI 切过去、Phase 3 删 `attributedText`

## 不要做

- **双状态并存**：`oldFooBlock: TextBlock?` 与新字段并列、运行时择优
- **阶段性 rollout**：phase 1 / phase 2 / phase 3 follow-up
- **Feature flag 灰度**：本项目无生产用户，没有灰度的意义
- **`@Deprecated` 渐进废弃**：直接删
- **`migrate-on-load` 适配器**：本地缓存可以一次清掉，没有"用户已经持有的数据"需要救
- **"为 review 友好"拆 PR**：用户已显式接受 20k+ 行 PR

## 真正应该拆的情况

唯一允许拆的场景是 **compile-blocking blast radius**：迁移会同时编译失败 N 个互相不通的模块边界，必须按模块拓扑顺序分多个 PR 才能编译。这种情况下：

- 在 PR / 计划文档里**明确**说明拆分原因（指出哪些模块互相阻塞）
- 不要默认拆，证明必须拆

"reviewability 困难"、"diff 太大不好看"、"测试覆盖压力"都**不是**拆 PR 的理由——前者交给 AI review 工具，后者通过 `check_unit_test_coverage.py` 强制保证。

## 关联

- `guides/dictionary.md` — Plan / PR / Review 等术语定义
- `guides/code-review-guide.md` — 代码审查的 3 种结论
- `guides/plan-execution-guide.md` — 计划执行的操作约束
- `lint/lint_dead_code.sh` — 强制清掉 commented-out / empty body / unused 声明
- `scripts/check_unit_test_coverage.py` — 强制每个 public/internal 函数有测
