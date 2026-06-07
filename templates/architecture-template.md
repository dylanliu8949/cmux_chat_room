# {module-name} 架构

## 模块职责

> 一段话描述模块的核心职责、边界和设计意图。

## 依赖关系

> 内部依赖指 app 内的第一方模块。使用 mermaid 图展示依赖关系，并在下方逐条列出每个依赖的用途。

**内部依赖**：

<!-- 示例：开始 -->
```mermaid
graph TD
    THIS[{module-name}]
    DEP1[dep-module-1<br/>简短说明]
    DEP2[dep-module-2<br/>简短说明]

    THIS --> DEP1
    THIS --> DEP2
```

- `dep-module-1`（API）— {使用了什么}
- `dep-module-2` — {使用了什么}
<!-- 示例：结束 -->

> 列出刻意不依赖的模块及原因。如果没有刻意不依赖的模块，省略此项。

<!-- 示例：开始 -->
**不依赖**：{模块名}（{原因}）
<!-- 示例：结束 -->

**外部依赖**：
<!-- 示例：开始 -->
- `library:version` — {用途}
<!-- 示例：结束 -->

**平台目标**：Android (API 24+)、iOS (arm64 + simulator)

## 包结构

<!-- 示例：开始 -->
```
canvas-editor/{module-name}/src/
├── commonMain/kotlin/com/vibe/canvaseditor/{package}/
│   ├── File1.kt              # 简短说明
│   └── File2.kt              # 简短说明
├── androidMain/               # 平台实现（如有）
├── iosMain/                   # 平台实现（如有）
└── commonTest/                # 测试
```
<!-- 示例：结束 -->

## 可见性

> 公开 API 部分先用表格汇总，再展开详细条目。表格列统一为：`API`、`类型`、`主要能力`、`主要调用方`。
> 公开 API 部分列出所有跨模块可见的类型和函数。每个条目包含：定义的代码块 + 来自其他模块的真实使用示例代码块。
> 使用示例直接从代码库中复制粘贴当时的代码片段即可，不要引用文件路径和行号（因为行号会频繁变化）。

### 公开 API（跨模块可见）

<!-- 示例：开始 -->
| API | 类型 | 主要能力 | 主要调用方 |
|-----|------|----------|------------|
| `ClassName` | class | 提供 {核心能力} | `other-module-a`, `other-module-b` |
| └ `methodName()` | fun | 执行 {方法操作} | `other-module-a` |
| └ `propertyName` | val | {属性说明} | `other-module-b` |
| `AnotherClass` | class | 提供 {另一能力} | `other-module-c` |
| └ `methodA()` | fun | 执行 {操作} | `other-module-c` |

#### `ClassName`

{用途说明。}

```kotlin
// 定义
class ClassName(param: Type) {
    fun method(): ReturnType
}
```

使用示例（来自 other-module）：

```kotlin
val instance = ClassName(param)
instance.method()
```

#### `functionName()`

{用途说明。}

```kotlin
// 定义
fun functionName(param: Type): ReturnType
```

使用示例（来自 other-module）：

```kotlin
val result = functionName(value)
```
<!-- 示例：结束 -->

### 模块内部（`internal`）
<!-- 示例：开始 -->
- `InternalClass` — 用途说明
- `internalFun()` — 用途说明
<!-- 示例：结束 -->

## 单元测试

> 列出测试文件和覆盖范围。UI 模块（editor-phone-ui 等纯 Compose UI 模块）豁免单元测试。

<!-- 示例：开始 -->
| 测试文件 | 覆盖范围 |
|----------|---------|
| `ClassNameTest.kt` | {测试了什么} |
| `FunctionNameTest.kt` | {测试了什么} |
<!-- 示例：结束 -->

## 设计说明

> 每个决策描述一个架构决策、权衡和理由。可引用 [Canvas Editor 架构概览](../../docs/architecture.md) 中的全局设计。
> 如果该决策有对应的计划文档，在决策标题下方添加计划文档链接。如果没有对应的计划文档，省略链接即可。

<!-- 示例：开始 -->
### {决策标题}

计划文档：[`plans/{plan-name}.md`](../../plans/{plan-name}.md)

{描述架构决策、权衡和理由。}

### {另一个决策标题}

{描述。}
<!-- 示例：结束 -->
