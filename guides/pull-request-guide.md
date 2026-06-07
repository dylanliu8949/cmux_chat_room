# Pull Request 工作流程指南

> 适用范围：Lovart 移动端  
> 目的：统一代码提交流程，确保代码质量和版本控制规范

---

## 工作流程概述

* **每个 Issue 可以有多个 PR 和分支，但每个 PR 只能处理一个 Issue**
* 通过 Pull Request（PR）将代码合并到主分支

## 详细步骤

### 1. 创建功能分支

* **分支命名规则**：
  * **基本格式**：`<YOUR_NAME>-<ISSUE_NAME>`
  * **示例**：`dylan-add-text-editor`、`alice-fix-image-crash`
  * **PR Train（同一 Issue 的多个 PR）**：使用递增序号
    * `dylan-add-text-editor-1`（第一个 PR）
    * `dylan-add-text-editor-2`（第二个 PR）
    * `dylan-add-text-editor-3`（第三个 PR）

```bash
# 确保主分支是最新的
git checkout main && git pull origin main

# 创建并切换到新分支
git checkout -b dylan-add-text-editor
# 或 PR Train：git checkout -b dylan-add-text-editor-1
```

### 2. 本地开发

* **在本地分支上进行所有代码修改**
* **使用 Commit 和 Push 作为保存点**（类似游戏中的保存点）
* **频繁提交**：
  * 完成一个小功能后立即提交
  * 完成一个独立的文件立即提交
  * 重构一小部分代码后立即提交
  * 不要等到整个 Issue 完成才提交

* **使用 Cursor 生成 Commit Message**：
  * 直接告诉 Cursor "commit and push"
  * Cursor 会自动分析代码变更并生成合适的 commit 标题和描述
  * 无需手动编写 commit message

### 3. 创建 Pull Request

* **当完成 Issue 的全部改动工作后，即可创建 Pull Request**
* **目标分支**：`main` 或 `master`
* **PR 标题和描述**：
  * **必须遵循 PR 模板**：`templates/pr-template.md`
  * **使用 AI 生成**：告诉 Cursor 使用以下信息生成 PR 标题和描述：
    * 代码差异：与基础分支（main/master）的 diff
    * PR 模板：`templates/pr-template.md`
    * 计划文档：该 Issue 对应的 `plan.md` 文件（如适用）

### 4. Pre-merge 检查

* **等待所有 Pre-merge 检查通过**
* **常见检查项**：
  * 代码编译通过（Android/iOS）
  * 单元测试通过
  * 代码风格检查（Lint）
  * CI/CD 流水线检查（未来会加）
  * 代码审查（Code Review）批准（未来会加）

* **如果检查失败**：修复问题后提交，PR 会自动更新并重新运行检查

### 5. Rebase 主分支

* **在合并前，将功能分支 rebase 到最新的主分支（master 或 main）**
* **目的**：确保功能分支包含主分支的最新更改，避免合并冲突
* **操作方式**：
  * 在 PR 界面使用 "Update branch" 功能（如果支持）
  * 或在本地执行：
    ```bash
    git checkout dylan-add-text-editor
    git fetch origin && git rebase origin/main
    git push origin dylan-add-text-editor --force-with-lease
    ```

### 6. 合并 Pull Request

* **Rebase 完成后，合并 PR 到主分支**
* **合并方式**：Squash and Merge（将多个 commit 合并为一个）

* **合并后**：
  * 删除功能分支（通常可自动删除）
  * 更新本地主分支：`git checkout main && git pull origin main`
  * **Issue 状态更新**：
    * 如果这是 Issue 的最后一个 PR，将 Issue 状态更新为 "Completed"
    * 如果 Issue 还有其他未完成的 PR，保持 Issue 状态为 "Vibing"

## 工作流程图示

```
main/master → 创建功能分支 → 本地开发（频繁 commit/push）
    ↓
创建 Pull Request → Pre-merge 检查
    ↓
✅ 通过 → Rebase master/main → 合并到 main/master → 删除功能分支
    ↓
❌ 失败 → 修复 → 重新检查
```

## 重要原则

### Issue、分支和 PR 的关系

* **一个 Issue 可以有多个 PR 和分支，但每个 PR 只能处理一个 Issue**
* **示例**：
  * 第一个 PR：创建计划文档（plan doc）
  * 后续 PR：执行计划中的各个步骤（每个步骤可以是独立的 PR）
* **保持 PR 的单一职责，便于审查和回滚**

### 频繁提交和推送

* **将 Commit 和 Push 视为保存点**，不要担心提交未完成的工作
* **好处**：记录工作进度、便于回滚、减少代码丢失风险、便于协作

### 保持分支同步

* **定期从主分支拉取最新更改**，避免分支与主分支差异过大
* ```bash
  git checkout dylan-add-text-editor
  git fetch origin && git rebase origin/main
  ```

## 常见场景

### 场景 1：一个 Issue 需要多个 PR

如果一个 Issue 较大，可以拆分为多个 PR：
* PR #1: 创建计划文档
* PR #2: 实现核心功能
* PR #3: 添加单元测试
* PR #4: 更新文档
* 所有 PR 都完成后，Issue 状态更新为 "Completed"

### 场景 2：Issue 需要拆分为多个独立 Issue

如果 Issue 太大且各部分相互独立：
1. 完成当前分支的部分工作
2. 创建 PR 并合并
3. 创建新的 Issue 和分支继续剩余工作

### 场景 3：Issue 被阻塞

如果 Issue 被外部因素阻塞：
1. 提交当前进度（即使未完成）
2. 在 PR 描述中说明阻塞原因
3. 将 Issue 状态更新为 "Blocked"
4. 解决阻塞后继续开发

### 场景 4：需要紧急修复

如果需要紧急修复生产环境问题：
1. 从主分支创建 `hotfix/` 分支
2. 快速修复并提交
3. 创建 PR 并标记为紧急
4. 合并后立即发布

## 最佳实践总结

✅ **DO（推荐）**：
* 一个 Issue 可以有多个分支和 PR，但每个 PR 只处理一个 Issue
* 频繁提交和推送（作为保存点）
* 保持 PR 小而专注
* 等待所有检查通过后再合并
* 当 Issue 的所有 PR 都合并后，才将 Issue 标记为 "Completed"

❌ **DON'T（避免）**：
* 在主分支直接提交代码
* 在一个 PR 中包含多个 Issue
* 等到整个 Issue 完全完成才创建 PR
* 忽略 Pre-merge 检查失败
* 在 Issue 还有未完成的 PR 时就标记为 "Completed"
