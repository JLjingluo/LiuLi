# 琉璃助手 LiuLi

iOS 液态玻璃风 AI 编程助手 · 自带 API Key · 零第三方依赖

## 功能
- **自选 API**：预设 DeepSeek / OpenAI / Kimi / 智谱 / Ollama + 自定义；自动拉取模型列表
- **双模式对话**：省流（极低 Token）/ 深度（全量 + 文件工具），流式输出、思考链折叠、Token 统计
- **识图**：相册图片 → 压缩 → 视觉模型
- **文件工作区**：浏览/编辑/导入/导出；深度模式下 **AI 可自主读写文件、写 HTML 小程序**
- **HTML 实时预览**：编辑器与聊天代码块均可预览，支持同目录相对资源
- 文件同步显示在 iOS「文件」App → 我的 iPhone → 琉璃助手

## 构建（需要 macOS + Xcode 15+）
```bash
./build.sh        # → build/LiuLi-unsigned.ipa（未签名）
```
无 Mac？把仓库推到 GitHub，手动触发 Actions `build-ipa`，在 Artifacts 下载 IPA。

## 签名
IPA 未签名。用 esign / Sideloadly / AltStore / 自有证书签名后安装。

## 使用
1. 设置 → 选服务商（或自定义）→ 填 Base URL + API Key → 获取模型列表 → 选模型
2. 聊天：右上切 省流/深度；📎 选图；深度模式下 AI 可直接读写文件
3. 文件页新建 `index.html` → 编辑 → 预览，或让 AI 直接写

## 系统要求
iOS 17.0+，iPhone。详见 `DEVELOPMENT.md`。
