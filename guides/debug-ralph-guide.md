# Ralph 调试与开发指南

本文档记录开发和调试 Ralph 本身时的经验教训和核心原则。

## 核心原则

**提供所有相关上下文，去除噪音，中间过程让 AI agent 自由发挥。**

Ralph 的价值在于编排（运行测试、管理 git、重试），而不是教 AI 怎么写代码或怎么调试。如果 Ralph 的表现比直接把同样的上下文丢给当前选定的 coding agent（如 Claude Code 或 Codex）还差，那说明我们在往 context 里塞垃圾。

## 宏观拆分 vs 微观拆分

把流程拆成**宏观阶段**（代码生成 → 编译测试 → 调试 → lint）是正确的——每个阶段获得一个全新的 context window，避免了单次 agent 调用中 context 被污染或耗尽的问题。这是 Ralph 作为编排层存在的核心价值。

但在单个 agent 调用**内部**把工作拆成太多微步骤（诊断 → 假设生成 → 去重 → 应用修复）是过度微管理。真正的开发者不会这样工作——他们看到错误，理解问题，然后修复。AI agent 也应该这样。

每增加一个微观编排步骤都有成本：
- 额外的 prompt 占用 context window
- 步骤之间的信息损失（摘要丢失细节）
- 限制了 agent 的自主判断空间

**只在 agent 自己做不好的地方介入**，例如：
- 提供 agent 无法获取的上下文（测试日志、构建输出、session 历史）
- 设置护栏防止 agent 走捷径（不要删除测试、不要弱化断言）
- 管理 agent 无权操作的外部状态（git、CI）

## 反模式：prompt 膨胀

system prompt 和 guide 文档应该只包含 agent 自己无法从代码库中推断出的信息。

**不该放的内容：**
- 通用编码建议（最小变更、注释质量、代码结构）——AI 已经知道
- "如何调试"的步骤教程（读错误、找源码、修复）——AI 已经知道
- 代码库里已有的信息（lint 规则、代码风格）——AI 能从配置文件和现有代码中学到
- 重复 `guides/encyclopedia.md` 和各模块 `architecture.md` 里已有的内容

**应该放的内容：**
- 护栏（无人监督时 agent 可能走的捷径）
- agent 无法自行发现的 codebase 特有知识（debug server 端口、日志时间戳关联规则、Appium 延迟偏移量）
- Ralph 编排层的约束（禁止 git 操作、日志路径）

**检验标准：** 如果把同样的错误信息直接丢给当前选定的 coding agent（不附加任何 guide），它是否已经能正确处理？如果是，那这段 guide 就是噪音。

## 反模式：context 浪费

Phase 1 代码生成曾经用了 101 个 turn、5800% context，原因：

1. **一次性读取所有参考文件** → context 爆炸 → 压缩 → 重新读取同样的文件。应该按步骤按需读取
2. **重复读取 plan 文档** → plan 已在 prompt 中，不需要从磁盘重新读取
3. **Glob/Grep 搜索已知路径的文件** → plan 和 architecture docs 已列出路径，直接 Read
4. **派生 Task 子 agent 做简单的文件读取** → 直接 Read 即可

## 反模式：agent 在单个 turn 内自建 debug loop

Ralph loop 的核心价值不是“让 agent 一次想清楚并自行验证到满意为止”，而是：

1. 给 agent 一个**新鲜的 context window**
2. 提供上一次失败的输出和必要历史作为附加上下文
3. 让 agent 做**一次**修复尝试
4. 把验证、提交、回滚、重试交还给 Ralph

这本质上是一种 **agentic problem solving 的 gradient descent**：每一轮只做一个有信息增益的尝试，然后用新的失败信号进入下一轮。

如果 agent（尤其是无 turn limit、强烈倾向自验证的 backend）在**单个 turn 内坚持自己跑测试、继续修、再跑测试、再继续修**，结果通常不是更聪明，而是：

- context window 被自己制造的中间状态、次生错误和无关日志污染
- 为了修复自己刚引入的问题继续偏航
- 逐渐忘记最初要解决的 failure 是什么
- 100 个 turn 之后主要在修复自己造成的破坏，而不是原始问题

在这种模式下，**revert + fresh context window** 的价值远高于“再坚持一下”。经验上，长时间不受控的单 turn 自循环是一种劣化机制，不是收敛机制。

### Canvas Editor 特有的错误吸引子：gesture 代码

在 canvas editor 这个仓库里，agent 很容易漂移到：

- `GestureRecognizer`
- 各类 gesture handler
- 输入坐标换算 / 手势识别底层

这通常是一个**错误吸引子**，因为这些模块：

- 历史上经过大量手动测试
- 长期是相对稳定的代码
- 体积大、表象复杂、很容易被 agent 当成“解释一切”的根因

结果是 agent 会把本来属于测试实现、页面交互、picker 识别、context menu 前置条件的问题，误判成 gesture 层 bug。

**结论**：
- 不要默认允许 agent 在单个 turn 内自建循环直到“自己满意”
- 让 Ralph 保持短回合、强回滚、强 fresh-context 的节奏
- 对 gesture / input 子系统设置更高的修改门槛：没有强证据，不应把它当作默认修复目标

## 反模式：为了简单文档编辑发明“运输层技巧”

如果任务只是更新 markdown 文档，而 agent 却开始发明复杂的 shell / 临时脚本运输机制，这通常说明它已经偏离了正确抽象层。

一个真实的坏例子是：为了修改 `architecture.md`，agent 生成了

- 嵌套的 `zsh -lc` / `bash -lc`
- heredoc 写入 base64 内容
- 再用 Python 解码生成临时脚本
- 最后执行临时脚本去改 markdown

这种行为的问题不是“丑”，而是它同时暴露了多个更深层的问题：

- 没有选择最直接的编辑手段（直接修改文档）
- 开始为并不存在的限制发明 workaround
- 日志可读性急剧下降，人工几乎无法快速判断它到底想做什么
- 出错面扩大（shell quoting、临时文件、编码、路径）
- 说明 agent 已经在“终端技巧表演”而不是在完成任务

对于 Ralph 来说，这类输出应该被视为**backend / prompt contract 不匹配的信号**。如果一个 phase 本应是：

- 读文档
- 对照代码
- 更新文档

却演化成“构造 base64 Python 脚本并通过 shell 解码执行”，那就说明当前 backend 不适合负责这个 phase，或者 prompt 没有把任务边界限制清楚。

### 判断标准

如果任务目标只是：
- 更新 markdown
- 改一小段代码
- 调整已知文件中的现有内容

那么正常路径应该是：
- 直接读文件
- 直接编辑文件

而不是：
- 生成临时脚本
- base64 编码/解码
- 多层 shell 嵌套
- 为了绕开引用问题继续堆更多运输层技巧

一旦看到这种模式，优先判断：
1. prompt 是否没有明确要求“直接编辑目标文件”
2. backend 是否在该 phase 过度偏好终端拼装而不是文件编辑
3. 是否应该把该 phase 切回更稳定的 agent

## 日志和产物位置

Ralph 的每一层都应该把日志写入独立的文件，方便事后定位问题和优化系统。

### 原则

1. **Agent 内部思考必须记录** — 所有 agent 调用都应使用 `--verbose`（或等效选项）将 agent 的完整推理过程写入日志文件。没有 verbose 日志，无法判断 agent 是在高效工作还是在兜圈子。
2. **Ralph 编排步骤必须记录** — 每个 phase 的开始、结束、耗时、结果（pass/fail/skip）都应写入 `output.log`。这是理解流水线瓶颈和失败模式的基础。
3. **每个子进程独立日志** — 编译、测试、lint 等子进程的 stdout/stderr 应写入各自的日志文件，不要混入 Ralph 编排日志。混合日志难以 grep、难以定位。
4. **组合 skill 有自己的日志目录** — `max_full_send` 这样的组合流程应在自己的 run folder 下记录完整的阶段日志。当它调用子 skill（code_polish、commit_and_push 等）时，子 skill 的日志也写入 `max_full_send` 的 run folder，而非 skill 各自的独立目录。

### 日志的用途

- **调试失败**：从 `output.log` 定位失败的 phase，再到对应子进程日志看具体错误
- **优化 prompt**：从 verbose 日志观察 agent 是否在做无效操作（重复读文件、搜索已知路径、派生不必要的子 agent）
- **评估改动效果**：对比修改前后的 turn 数、context 使用率、phase 耗时

## 本地 Python 回归命令

在改 Ralph / `ui-test` 的 Python 基础设施后，先跑：

```bash
unit-test/run_python_tooling_tests.sh
```

这个脚本会做三件事：
- 跑 Ralph 的 Python 单元测试：`ralph/agents/tests`、`ralph/common/tests`、`ralph/skills/tests`、`ralph/tests`
- 跑 `ui-test` 的纯 Python 单元测试：`ui-test/framework/utilities/tests`、`ui-test/unit-tests`
- 跑真实 agent smoke test：通过 Ralph wrapper 分别调用本机已安装并已登录的 Claude Code 和 Codex

这里的 smoke test 不是 mock：
- Claude 走 `agents/claude_code.py`
- Codex 走 `agents/codex_cli.py`
- 目的是尽早发现 CLI 安装、认证状态、模型配置、wrapper 参数拼接是否失效

输出目录：

```text
unit-test/.run/<timestamp>/
├── ralph-python-tests.log
├── ui-test-python-tests.log
└── agent-smoke.log
```

### 单元测试
```
unit-test/.run/<timestamp>/
├── output.log       ← 完整的构建 + 测试输出
└── test-results/    ← XML 测试报告
    └── TEST-<package>.<TestClass>.xml
```

### UI 测试
```
ui-test/.run/<timestamp>/
├── android_appium.log / ios_appium.log   ← Appium server 日志
├── android_test.log / ios_test.log       ← pytest 输出（带 [ms] 时间戳）
├── android_app.log / ios_app.log         ← 设备应用日志（按 app PID 过滤）
├── android_final_screenshot.png          ← 测试结束时的截图
├── recordings/                           ← 屏幕录制（需启用 record=True）
└── env.sh                                ← 运行时状态（设备序列号、时钟偏移等）
```

### Ralph 自身
```
ralph/.run/
├── max_full_send/<timestamp>/
│   ├── .ralph_session_history.jsonl  ← session 事件日志
│   └── output.log                   ← 编排层输出
├── debug/<timestamp>/               ← debug loop 的 session 和输出
├── code/<timestamp>/                ← code loop 的 session 和输出
└── skills/                          ← skill 独立运行的日志
    ├── code_review/<timestamp>/
    │   └── output.log
    ├── code_polish/<timestamp>/
    │   └── output.log
    ├── review_plan/<timestamp>/
    │   └── output.log
    ├── review_ui_test_plan/<timestamp>/
    │   └── output.log
    ├── commit_and_push/<timestamp>/
    │   └── output.log
    ├── create_pr/<timestamp>/
    │   └── output.log
    ├── check_docs_update/<timestamp>/
    │   └── output.log
    └── update_docs/<timestamp>/
        └── output.log
```

> **注意**：`skills/` 下的日志仅在通过命令行直接运行 skill 时产生。当 skill 被 `max_full_send` 调用时，日志写入 `max_full_send` 的 run folder。

## 识别和清理 Ralph 提交

所有 Ralph 生成的 commit 都带 `[ralph]` 前缀（由 `common/git.py:git_commit_and_push()` 自动添加）。

**重新运行 pipeline 前必须清理**：Ralph 的 code loop、lint loop 等会在运行前检查当前测试状态。如果上一次运行的代码还在（尤其是有 bug 的代码），下一次运行会从错误的起点开始。

```bash
# 查看当前分支上所有 ralph 提交
git log --oneline origin/main..HEAD --grep='\[ralph\]'

# 回退到最后一个非 ralph 提交（保留计划修改等人工提交）
git reset --hard <last-non-ralph-commit>

# 或回退所有 ralph 提交，只保留 plan refinement
git reset --hard $(git log --oneline origin/main..HEAD | grep -v '\[ralph\]' | head -1 | cut -d' ' -f1)
```

**注意**：`git reset --hard` 后需要 `git push --force-with-lease` 同步远程。

## 评估 Ralph 改动的方法

修改 Ralph 的 prompt、guide 或编排逻辑后：

1. 对比改动前后 agent 的 turn 数和 context 使用率
2. 检查 output.log 中是否有重复读取、无效搜索、不必要的 Task 子 agent
3. 问自己：如果我直接把同样的输入丢给当前选定的 coding agent，结果会更好还是更差？
