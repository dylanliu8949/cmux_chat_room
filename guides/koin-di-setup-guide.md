# Koin 依赖注入设置指南 (AI Agent 专用)

## 概述

本项目使用 Koin 作为 Kotlin Multiplatform (KMP) 的依赖注入框架。每当创建新的服务模块时，必须正确配置 DI 才能在运行时正常工作。

**重要**: 如果忘记注册模块，应用会在启动时崩溃，错误信息为：
```
org.koin.core.error.NoDefinitionFoundException: No definition found for type 'xxx'.
Check your Modules configuration and add missing type and/or qualifier!
```

## 项目 DI 架构

```
┌─────────────────────────────────────────────────────────────┐
│                      KoinIOS.kt / MainApplication.kt        │
│                      (平台入口点，加载所有模块)                │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    平台特定模块 (先加载)                      │
│  - iosXxxServiceModule / androidXxxServiceModule            │
│  - 提供接口的具体实现                                         │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    业务模块 (后加载)                          │
│  - canvasEditorModule                                       │
│  - 依赖上面的平台模块                                         │
└─────────────────────────────────────────────────────────────┘
```

## 创建新服务模块的完整步骤

### 步骤 1: 创建 commonMain 接口

**文件位置**: `{moduleName}/src/commonMain/kotlin/com/vibe/{modulename}/{ServiceName}.kt`

```kotlin
package com.vibe.{modulename}

interface {ServiceName} {
    suspend fun doSomething(): Result<String>
}
```

### 步骤 2: 创建 iOS 实现

**文件位置**: `{moduleName}/src/iosMain/kotlin/com/vibe/{modulename}/Ios{ServiceName}.kt`

```kotlin
package com.vibe.{modulename}

class Ios{ServiceName} : {ServiceName} {
    override suspend fun doSomething(): Result<String> {
        // iOS 实现
    }
}
```

### 步骤 3: 创建 iOS DI 模块 ⚠️ 关键步骤

**文件位置**: `{moduleName}/src/iosMain/kotlin/com/vibe/{modulename}/di/Ios{ServiceName}Module.kt`

```kotlin
package com.vibe.{modulename}.di

import com.vibe.{modulename}.{ServiceName}
import com.vibe.{modulename}.Ios{ServiceName}
import org.koin.dsl.module

val ios{ServiceName}Module = module {
    single<{ServiceName}> { Ios{ServiceName}() }
}
```

### 步骤 4: 创建 Android 实现

**文件位置**: `{moduleName}/src/androidMain/kotlin/com/vibe/{modulename}/Android{ServiceName}.kt`

```kotlin
package com.vibe.{modulename}

class Android{ServiceName} : {ServiceName} {
    override suspend fun doSomething(): Result<String> {
        // Android 实现
    }
}
```

### 步骤 5: 创建 Android DI 模块 ⚠️ 关键步骤

**文件位置**: `{moduleName}/src/androidMain/kotlin/com/vibe/{modulename}/di/Android{ServiceName}Module.kt`

```kotlin
package com.vibe.{modulename}.di

import com.vibe.{modulename}.{ServiceName}
import com.vibe.{modulename}.Android{ServiceName}
import org.koin.dsl.module

val android{ServiceName}Module = module {
    single<{ServiceName}> { Android{ServiceName}() }
}
```

### 步骤 6: 在 iOS Koin 入口注册模块 ⚠️ 最容易遗漏的步骤

**文件位置**: `canvas-editor/src/iosMain/kotlin/com/vibe/canvaseditor/KoinIOS.kt`

```kotlin
package com.vibe.canvaseditor

import com.vibe.{modulename}.di.ios{ServiceName}Module  // ← 添加 import
// ... 其他 imports

fun doInitKoin() {
    startKoin {
        modules(
            // 平台特定模块 (必须先注册)
            iosLocalStorageServiceModule,
            iosPermissionServiceModule,
            iosPhotoServiceModule,
            photoServiceModule,
            ios{ServiceName}Module,  // ← 添加新模块
            // 业务模块 (依赖上面的模块)
            canvasEditorModule,
        )
    }
}
```

### 步骤 7: 在 Android Koin 入口注册模块

**文件位置**: `androidApp/app/src/main/java/com/vibe/canvaseditor/MainApplication.kt`

```kotlin
class MainApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        startKoin {
            androidContext(this@MainApplication)
            modules(
                // 平台特定模块
                androidLocalStorageServiceModule,
                androidPermissionServiceModule,
                androidPhotoServiceModule,
                photoServiceModule,
                android{ServiceName}Module,  // ← 添加新模块
                // 业务模块
                canvasEditorModule,
            )
        }
    }
}
```

### 步骤 8: 在 build.gradle.kts 添加依赖

如果其他模块需要使用这个新服务，在其 `build.gradle.kts` 中添加：

```kotlin
commonMain {
    dependencies {
        implementation(project(":{moduleName}"))
    }
}
```

## 在业务代码中使用服务

### 方式 1: 在 Koin 模块中注入

```kotlin
// canvas-editor/src/commonMain/kotlin/com/vibe/canvaseditor/di/CanvasEditorModule.kt
val canvasEditorModule = module {
    single<EditorService> {
        EditorService(
            documentSyncService = get<DocumentSyncService>(),
            imageLoader = get<ImageLoader>(),
            myNewService = get<{ServiceName}>(),  // ← 注入新服务
        )
    }
}
```

### 方式 2: 在 Composable 中注入

```kotlin
@Composable
fun MyScreen() {
    val myService: {ServiceName} by inject()
    // 使用 myService
}
```

## 常见错误和解决方案

### 错误 1: NoDefinitionFoundException

**错误信息**:
```
org.koin.core.error.NoDefinitionFoundException: No definition found for type 'com.vibe.xxx.XxxService'
```

**原因**: 服务的 DI 模块没有在 KoinIOS.kt 或 MainApplication.kt 中注册

**解决方案**:
1. 检查 `ios{ServiceName}Module` 是否存在
2. 检查 KoinIOS.kt 中是否导入并添加了该模块

### 错误 2: InstanceCreationException

**错误信息**:
```
org.koin.core.error.InstanceCreationException: Could not create instance for 'XxxService'
Caused by: NoDefinitionFoundException for dependency 'YyyService'
```

**原因**: XxxService 依赖 YyyService，但 YyyService 没有注册

**解决方案**:
1. 确保 YyyService 的模块在 XxxService 之前注册
2. 检查模块加载顺序

### 错误 3: 循环依赖

**错误信息**:
```
org.koin.core.error.KoinException: Circular dependency detected
```

**解决方案**:
1. 重构代码，消除循环依赖
2. 使用 `lazy` 注入延迟加载

## 模块注册顺序原则

```
1. 基础服务模块 (无依赖)
   - iosLocalStorageServiceModule
   - iosPermissionServiceModule

2. 中间服务模块 (依赖基础服务)
   - iosPhotoServiceModule
   - photoServiceModule
   - iosBackgroundRemoverServiceModule

3. 业务模块 (依赖所有服务)
   - canvasEditorModule
```

## Checklist: 新模块创建检查清单

创建新服务模块时，确保完成以下所有步骤：

- [ ] 创建 commonMain 接口
- [ ] 创建 iosMain 实现类
- [ ] 创建 iosMain DI 模块 (`ios{ServiceName}Module`)
- [ ] 创建 androidMain 实现类
- [ ] 创建 androidMain DI 模块 (`android{ServiceName}Module`)
- [ ] 在 `KoinIOS.kt` 中 import 并注册 iOS 模块
- [ ] 在 `MainApplication.kt` 中 import 并注册 Android 模块
- [ ] 在依赖此服务的模块的 `build.gradle.kts` 中添加项目依赖
- [ ] 如果其他服务依赖此服务，更新其 Koin 模块注入

## 现有模块参考

| 模块名 | iOS 模块变量名 | Android 模块变量名 |
|--------|---------------|-------------------|
| photoService | `iosPhotoServiceModule` | `androidPhotoServiceModule` |
| localStorageService | `iosLocalStorageServiceModule` | `androidLocalStorageServiceModule` |
| permissionService | `iosPermissionServiceModule` | `androidPermissionServiceModule` |
| backgroundRemoverService | `iosBackgroundRemoverServiceModule` | `androidBackgroundRemoverServiceModule` |

## 文件路径汇总

| 文件类型 | iOS 路径 | Android 路径 |
|---------|---------|-------------|
| 接口定义 | `{module}/src/commonMain/kotlin/com/vibe/{module}/{Service}.kt` | 同左 |
| 平台实现 | `{module}/src/iosMain/kotlin/com/vibe/{module}/Ios{Service}.kt` | `{module}/src/androidMain/kotlin/com/vibe/{module}/Android{Service}.kt` |
| DI 模块 | `{module}/src/iosMain/kotlin/com/vibe/{module}/di/Ios{Service}Module.kt` | `{module}/src/androidMain/kotlin/com/vibe/{module}/di/Android{Service}Module.kt` |
| Koin 入口 | `canvas-editor/src/iosMain/kotlin/com/vibe/canvaseditor/KoinIOS.kt` | `androidApp/app/src/main/java/com/vibe/canvaseditor/MainApplication.kt` |
