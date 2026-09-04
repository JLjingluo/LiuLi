# 琉璃助手 (LiuLi) · 开发文档

一个自研 iOS 原生 AI 编程助手。用户自带 API Key，兼容所有 OpenAI 风格接口（DeepSeek / OpenAI / Kimi / 智谱 GLM / Ollama 本地等），支持流式对话、图片识别、本地文件读写、HTML 小程序编写与实时预览。界面采用 Liquid Glass（液态玻璃）视觉语言。

- **交付物**：完整 Xcode 工程 + `build.sh`（一键产出**未签名裸 IPA**）+ GitHub Actions 云构建工作流
- **签名**：本工程不含任何签名配置，IPA 由你自行签名（esign / Sideloadly / AltStore / 企业证书 / Xcode 手动签名均可）

---

## 1. 需求与功能清单

| 模块 | 功能 |
|---|---|
| API 接入 | 预设服务商 + 自定义 Base URL；API Key 存 Keychain；一键拉取 `/models` 模型列表并选择，也支持手动填模型名 |
| 对话 | 多会话管理、SSE 流式输出、Markdown 渲染、代码块（复制/存文件/HTML 预览）、停止与重新生成 |
| 省流/深度双模式 | 省流：精简系统提示 + 只带最近 8 条上下文 + 历史图片剔除（Token 消耗极低）；深度：全量上下文 + 开启文件工具 |
| 识图 | 相册选图（最多 3 张），压缩至 1568px/JPEG 后以 `image_url`（data URL）发送，兼容 OpenAI 视觉格式 |
| 文件工具（Agent） | 深度模式下通过 Function Calling 让模型调用 `list_files` / `read_file` / `write_file` / `delete_file`，在 App 文档目录内自主读写文件、写小程序 |
| 文件页 | 浏览/新建/重命名/删除/导入/导出，代码编辑器（等宽、行数统计、自动保存），HTML 实时预览（WKWebView，支持同目录相对资源） |
| 模型思考链 | 兼容 DeepSeek `reasoning_content`，气泡内折叠显示思考过程 |
| Token 统计 | 解析流式 `usage`，气泡下方显示 ↑prompt ↓completion |

## 2. 技术选型

| 项 | 决策 | 理由 |
|---|---|---|
| 最低系统 | iOS 17.0 | `PhotosPicker`、alert 内 TextField、`onChange` 双参等 API 均已稳定 |
| UI | SwiftUI + 自研液态玻璃主题 | `ultraThinMaterial` + 渐变描边 + 背景弥散光斑，不依赖 iOS 26 SDK，老 Xcode 也能编译 |
| 架构 | MVVM（ObservableObject） | 比 `@Observable` 宏更保守，编译零惊喜 |
| 网络 | URLSession + `bytes` AsyncSequence | 原生 SSE 流式，无第三方依赖 |
| 持久化 | 会话 JSON（`Documents/Conversations`）；Key 存 Keychain；其余 UserDefaults | 全部系统 API，无数据库依赖 |
| 依赖 | **零第三方依赖** | 保证离线可编译、无供应链风险 |
| 工程 | 手写 `project.pbxproj` + Scheme | 不依赖 xcodegen 等工具，clone 即用 |

## 3. 目录结构

```
LiuLi/
├── build.sh                     # 一键构建未签名 IPA（macOS）
├── LiuLi.xcodeproj/
│   ├── project.pbxproj
│   └── xcshareddata/xcschemes/LiuLi.xcscheme
├── LiuLi/                       # App 源码
│   ├── Info.plist
│   ├── Assets.xcassets/         # AppIcon / AccentColor / 启动底色
│   ├── LiuLiApp.swift           # @main 入口 + 全局初始化
│   ├── Theme.swift              # 液态玻璃主题（卡片修饰器、背景、渐变）
│   ├── Models.swift             # 会话/消息/工具调用等数据模型
│   ├── APITypes.swift           # 请求/响应/流式 DTO 与编码
│   ├── Settings.swift           # 设置存储 + Keychain
│   ├── SSEParser.swift          # SSE 行解析（纯逻辑，已测）
│   ├── MarkdownParser.swift     # Markdown 块级解析（纯逻辑，已测）
│   ├── AgentTools.swift         # 工具定义/执行/路径安全（纯逻辑，已测）
│   ├── APIClient.swift          # 模型列表 + 流式对话客户端
│   ├── ConversationStore.swift  # 会话持久化与修复
│   ├── ImageCompressor.swift   # 图片压缩转 data URL
│   ├── AppRouter.swift          # 全局路由（Tab 切换、文件转 AI）
│   └── Views/                   # RootView / 聊天 / 文件 / 设置
├── verification/                # SwiftPM 纯逻辑测试包（Linux 可跑）
└── .github/workflows/build-ipa.yml
```

## 4. 关键设计

### 4.1 API 兼容层
- 约定 `baseURL` 形如 `https://api.deepseek.com/v1`，App 拼 `/chat/completions` 与 `/models`。
- 流式请求体：`{"model", "messages", "stream": true, "temperature", "max_tokens", "tools", "tool_choice", "stream_options": {"include_usage": true}}`；`stream_options` 受设置开关控制（默认开，个别服务商不支持可关）。
- SSE 逐行解析 `data:` 前缀、`[DONE]` 结束、忽略 `:` 心跳行；chunk 内 `delta.content` / `delta.reasoning_content` / `delta.tool_calls[]`（按 `index` 累积 `id/name/arguments` 片段）、末块 `usage`。错误行尝试 `{"error": ...}` 双形态解码。
- 上下文重建：UI 消息 → API 消息。`assistant` 携带 `tool_calls`、`tool` 消息携带 `tool_call_id`，保证 Function Calling 协议闭环。

### 4.2 Agent 工具与安全
- 工具仅作用于 App 自身沙盒 `Documents`（开启文件共享后即"我的 iPhone/琉璃助手"目录），不触碰沙盒外任何数据——这是与 iOS 安全模型共存的合法形态。
- 路径安全：相对路径按段解析，`..` 归一化后**禁止逃逸根目录**；顶层 `Conversations/`（会话数据）列入黑名单不可访问；写入自动创建父目录；读取截断至 100k 字符防止上下文爆炸。
- 工具循环上限 8 轮，防死循环；每轮工具调用以独立气泡行呈现，结果回填给模型。

### 4.3 会话完整性自愈
流式中途被杀进程可能产生「assistant 带 tool_calls 但缺 tool 结果」的非法历史（重发会被 API 400）。存储层在**加载时与发送前**执行修复：移除尾部不完整的 assistant 及其后续消息，保证历史永远合法。

### 4.4 上下文裁剪（省流模式）
省流：系统提示精简 + 只保留最近 8 条 + 仅保留最后一条用户消息的图片；深度：最近 40 条全量（含图片）。

### 4.5 液态玻璃主题
- 全局背景：深色渐变 + 两枚弥散色斑（blur 60）；
- 卡片：`ultraThinMaterial` 底 + `LinearGradient` 1pt 描边 + 20pt 连续圆角；
- TabBar/导航栏 `toolbarBackground(.ultraThinMaterial)`；
- 动效仅用系统默认（保证流畅、零手写动画 bug）。

## 5. 测试与质量保障

1. **纯逻辑单元测试**（`verification/`，Linux `swift test` 实际执行）：
   - Markdown：标题/列表/引用/代码围栏/分割线/表格/嵌套；
   - SSE：多行 data、`\r\n`、`[DONE]`、心跳行、JSON 错误行；
   - 路径安全：`..` 逃逸、绝对路径、黑名单、Unicode 文件名；
   - 工具执行：读写删列全链路（临时目录）；
   - 上下文重建：协议字段正确性、图片剔除、轮次裁剪。
2. **全量语法校验**：所有 Swift 文件过 `swiftc -parse`（零语法错误才交付）。
3. **人工复审**：强制解包审查、Sendable/并发、退格与括号配平、pbxproj UUID 与文件一一对应、Info.plist 键完整性。

## 6. 构建（产出未签名 IPA）

```bash
# 在任意 Mac（Xcode 15+，含 Xcode Command Line Tools）上：
cd LiuLi
./build.sh
# 产物：build/LiuLi-unsigned.ipa
```

或 GitHub Actions：push 后手动触发 `build-ipa` 工作流，Artifacts 下载同款 IPA。

## 7. 签名（由你完成）

裸 IPA 不含签名，安装前需自签：
- **esign / SideStore / AltStore**：导入 IPA + 你的证书/Apple ID 一键签；
- **Sideloadly**（PC）或 **Xcode**：`Devices → +` 选择 IPA 对应 .app 安装；
- Bundle ID：`com.liulidev.assistant`（改 ID 请同步改 pbxproj `PRODUCT_BUNDLE_IDENTIFIER`）。

## 8. 已知边界（如实声明）

- 无法在 Linux 环境完成 iOS 编译，UI 层代码经语法校验 + 逐行人工复审，但不等同于真机编译验证；若首次构建报错，多为笔误级问题，按报错行号修正即可（纯逻辑层已全部实测试）。
- 识图要求所选模型本身支持视觉输入（如 `gpt-4o`、`glm-4v`；`deepseek-chat` 不支持）。
- Ollama 本地地址（http）依赖 Info.plist 中已开启的 ATS 放行。
- Function Calling 依赖服务商支持；DeepSeek `deepseek-reasoner` 不支持工具调用，深度文件操作请选 `deepseek-chat` 等支持 FC 的模型。
