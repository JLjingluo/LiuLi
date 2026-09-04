import SwiftUI

// MARK: - 消息视图（对标豆包布局）
// - 用户：右侧品牌渐变气泡
// - AI：左侧头像 + 无气泡直接排版 + 底部操作栏（复制/重新生成/选择文本）
// - 长按消息 → contextMenu（复制 / 选择文本 / 重新生成）

struct MessageBubble: View {
    let message: ChatMessage
    var isStreaming = false
    /// 是否是本轮生成的最后一条 assistant 消息（决定操作栏是否展示重新生成）
    var isLatestAssistant = false
    var onRegenerate: (() -> Void)? = nil

    @EnvironmentObject private var settings: AppSettings
    @State private var showTextSelector = false

    var body: some View {
        switch message.role {
        case .user:
            userBubble
                .contextMenu {
                    Button {
                        UIPasteboard.general.string = message.text
                    } label: {
                        Label("复制", systemImage: "doc.on.doc")
                    }
                    if !message.text.isEmpty {
                        Button {
                            showTextSelector = true
                        } label: {
                            Label("选择文本", systemImage: "character.cursor.ibeam")
                        }
                    }
                }
        case .assistant:
            assistantBubble
                .contextMenu {
                    Button {
                        UIPasteboard.general.string = plainText
                    } label: {
                        Label("复制", systemImage: "doc.on.doc")
                    }
                    if !plainText.isEmpty {
                        Button {
                            showTextSelector = true
                        } label: {
                            Label("选择文本", systemImage: "character.cursor.ibeam")
                        }
                    }
                    if isLatestAssistant && !isStreaming, let onRegenerate {
                        Button {
                            onRegenerate()
                        } label: {
                            Label("重新生成", systemImage: "arrow.clockwise")
                        }
                    }
                }
        case .tool:
            toolRow
        case .note:
            noteRow
        }
    }

    /// 长按「选择文本」用的纯文本
    private var plainText: String {
        message.text
    }

    // MARK: 用户气泡（右对齐，豆包式品牌渐变）

    private var userBubble: some View {
        VStack(alignment: .trailing, spacing: 6) {
            if !message.images.isEmpty {
                imageGrid
            }
            if !message.text.isEmpty {
                Text(message.text)
                    .font(.system(size: 15.5))
                    .foregroundStyle(Color.onBrand)
                    .textSelection(.enabled)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 19, style: .continuous)
                            .fill(Color.brandGradient)
                    )
                    .frame(maxWidth: 286, alignment: .trailing)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .sheet(isPresented: $showTextSelector) {
            TextSelectorView(title: "我的消息", text: message.text)
        }
    }

    private var imageGrid: some View {
        VStack(alignment: .trailing, spacing: 6) {
            ForEach(Array(message.images.enumerated()), id: \.offset) { _, dataURL in
                if let ui = ImageCompressor.imageFromDataURL(dataURL) {
                    Image(uiImage: ui)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 168, height: 168)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Color.glassStroke, lineWidth: 1)
                        )
                }
            }
        }
    }

    // MARK: AI 消息（豆包式：左侧头像 + 无气泡排版 + 操作栏）

    private var assistantBubble: some View {
        VStack(alignment: .leading, spacing: 6) {
            // 头像 + 名称
            HStack(spacing: 8) {
                aiAvatar
                Text(AppInfo.displayName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.textSecondary)
                if isStreaming {
                    ThinkingIndicator()
                }
                Spacer()
            }

            // 思考链（折叠）
            if let reasoning = message.reasoning, !reasoning.isEmpty {
                ReasoningDisclosure(text: reasoning)
            }

            // 正文（Markdown，无气泡）
            if !message.text.isEmpty {
                MarkdownTextView(markdown: message.text)
            } else if message.toolCalls.isEmpty && !isStreaming && message.errorMessage == nil {
                HStack(spacing: 4) {
                    ForEach(0..<3, id: \.self) { i in
                        TypingDot(delay: Double(i) * 0.18)
                    }
                }
                .padding(.top, 4)
            }

            // 工具调用展示
            if !message.toolCalls.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(message.toolCalls) { call in
                        ToolCallRow(call: call)
                    }
                }
            }

            // 错误信息
            if let error = message.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Color.errorText)
            }

            // 本次花费（按设置页单价估算）
            if let usage = message.usage {
                let cost = usage.costYuan(
                    inputPerM: settings.inputPricePerM,
                    outputPerM: settings.outputPricePerM
                )
                HStack(spacing: 3) {
                    Image(systemName: "yensign.circle")
                        .font(.system(size: 9))
                    Text("本次 \(UsageInfo.costText(cost))")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundStyle(Color.textTertiary)
            }

            // 操作栏（豆包式：复制 / 重新生成，流式完成后显示）
            if !isStreaming && (isLatestAssistant || message.errorMessage != nil) {
                assistantActionBar
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(isPresented: $showTextSelector) {
            TextSelectorView(title: "AI 回复", text: message.text)
        }
    }

    private var aiAvatar: some View {
        ZStack {
            Circle()
                .fill(Color.brandGradient)
            Image(systemName: "sparkle")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.onBrand)
        }
        .frame(width: 26, height: 26)
    }

    private var assistantActionBar: some View {
        HStack(spacing: 2) {
            ActionIconButton(systemImage: "doc.on.doc", label: "复制") {
                UIPasteboard.general.string = message.text
            }
            if !message.text.isEmpty {
                ActionIconButton(systemImage: "character.cursor.ibeam", label: "选字") {
                    showTextSelector = true
                }
            }
            if isLatestAssistant, let onRegenerate {
                ActionIconButton(systemImage: "arrow.clockwise", label: "重答") {
                    onRegenerate()
                }
            }
            Spacer()
        }
        .padding(.top, 2)
    }

    // MARK: 工具结果行

    private var toolRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "wrench.and.screwdriver")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.liuliViolet)
                Text("工具结果 · \(message.toolName ?? "unknown")")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.textTertiary)
            }
            Text(message.text)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color.textSecondary)
                .lineLimit(8)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.toolChipBG)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.liuliViolet.opacity(0.25), lineWidth: 0.8)
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: 本地提示

    private var noteRow: some View {
        Text(message.text)
            .font(.system(size: 11))
            .foregroundStyle(Color.textTertiary)
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
            .padding(.vertical, 4)
    }
}

// MARK: - 操作栏小按钮（豆包式轻量操作）

struct ActionIconButton: View {
    let systemImage: String
    let label: String
    let action: () -> Void
    @State private var pressed = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .medium))
                Text(label)
                    .font(.system(size: 11.5, weight: .medium))
            }
            .foregroundStyle(Color.textTertiary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(pressed ? Color.textPrimary.opacity(0.10) : Color.surfaceCard)
            )
        }
        .buttonStyle(.plain)
        .onLongPressGesture(minimumDuration: .infinity) {} onPressingChanged: { v in
            withAnimation(.easeInOut(duration: 0.12)) { pressed = v }
        }
    }
}

// MARK: - 思考中指示器（豆包式渐变呼吸点）

struct ThinkingIndicator: View {
    @State private var animating = false

    var body: some View {
        HStack(spacing: 3) {
            Circle()
                .fill(Color.liuliAccent)
                .frame(width: 4, height: 4)
                .scaleEffect(animating ? 1.0 : 0.55)
                .opacity(animating ? 1.0 : 0.5)
            Text("思考中")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Color.textTertiary)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                animating = true
            }
        }
    }
}

// MARK: - 打字动画圆点

struct TypingDot: View {
    let delay: Double
    @State private var animating = false

    var body: some View {
        Circle()
            .fill(Color.liuliAccent)
            .frame(width: 6, height: 6)
            .offset(y: animating ? -3 : 2)
            .animation(
                .easeInOut(duration: 0.5).repeatForever(autoreverses: true).delay(delay),
                value: animating
            )
            .onAppear { animating = true }
    }
}

// MARK: - 思考链折叠

struct ReasoningDisclosure: View {
    let text: String
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 10, weight: .semibold))
                    Text(expanded ? "收起思考过程" : "思考过程")
                        .font(.system(size: 11, weight: .medium))
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                }
                .foregroundStyle(Color.textTertiary)
            }
            .buttonStyle(.plain)

            if expanded {
                Text(text)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.textSecondary)
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.surfaceCard)
                    )
            }
        }
    }
}

// MARK: - 工具调用行

struct ToolCallRow: View {
    let call: ToolCallInfo

    private var icon: String {
        switch call.name {
        case "list_files": return "folder"
        case "read_file": return "doc.text"
        case "write_file": return "square.and.pencil"
        case "delete_file": return "trash"
        default: return "terminal"
        }
    }

    private var displayName: String {
        switch call.name {
        case "list_files": return "列出文件"
        case "read_file": return "读取文件"
        case "write_file": return "写入文件"
        case "delete_file": return "删除文件"
        default: return call.name
        }
    }

    private var pathArgument: String? {
        guard let data = call.arguments.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let path = obj["path"] as? String, !path.isEmpty else { return nil }
        return path.isEmpty ? "(根目录)" : path
    }

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.liuliTeal)
            Text(displayName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.textSecondary)
            if let path = pathArgument {
                Text(path)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.liuliAccent.opacity(0.9))
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.toolChipBG)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.liuliTeal.opacity(0.22), lineWidth: 0.8)
        )
    }
}
