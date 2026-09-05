import SwiftUI

// MARK: - 消息视图 v2（液态玻璃版）
// - 用户：右侧玻璃气泡（品牌微染）或纯色气泡（设置可选）
// - AI：左侧小 logo 头像 + 无气泡直接排版 + 底部小灰图标操作栏
// - 长按消息 → contextMenu（复制 / 选择文本 / 分享 / 重新生成）

struct MessageBubble: View {
    let message: ChatMessage
    var isStreaming = false
    /// 是否是本轮生成的最后一条 assistant 消息（决定操作栏是否展示重新生成）
    var isLatestAssistant = false
    /// 思考链展开状态（由 ChatView 持有，LazyVStack 回收不丢失）
    var reasoningExpanded: Binding<Bool>? = nil
    /// 是否显示时间戳（设置项）
    var showTimestamp = false
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

    // MARK: 用户气泡（右对齐；玻璃风 / 纯色风可在设置切换）

    /// 用户气泡最大宽度：随屏幕自适应（屏宽的 82%，小屏不挤、大屏不散）
    private var userBubbleMaxWidth: CGFloat {
        (UIScreen.main.bounds.width - 28) * 0.82
    }

    /// iOS 聊天惯例：右下角小圆角作"尾巴"，其余大圆角
    private var userBubbleShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            cornerRadii: .init(
                topLeading: 18, bottomLeading: 18,
                bottomTrailing: 6, topTrailing: 18),
            style: .continuous
        )
    }

    private var userBubble: some View {
        VStack(alignment: .trailing, spacing: 5) {
            if !message.images.isEmpty {
                imageGrid
            }
            if !message.text.isEmpty {
                let text = Text(message.text)
                    .font(.system(size: settings.chatFontSize + 0.5))
                    .foregroundStyle(Color.onUserBubble)
                    .textSelection(.enabled)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)

                if settings.userBubbleStyle == 0 {
                    // 玻璃风：液态玻璃容器 + 品牌微染（折射底部弥散色）
                    text
                        .background(userBubbleShape.fill(Color.userBubbleFill))
                        .overlay(userBubbleShape.strokeBorder(Color.glassStroke, lineWidth: 1))
                        .frame(maxWidth: userBubbleMaxWidth, alignment: .trailing)
                } else {
                    // 纯色风：DeepSeek 式浅灰蓝实底
                    text
                        .background(userBubbleShape.fill(Color.userBubbleSolid))
                        .frame(maxWidth: userBubbleMaxWidth, alignment: .trailing)
                }
            }
            if showTimestamp {
                timestampText
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

    // MARK: AI 消息（DeepSeek 式：小头像 + 无气泡排版 + 小灰图标操作栏）

    private var assistantBubble: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 头像 + 名称（可在设置中关闭头像）
            HStack(spacing: 7) {
                if settings.showAIavatar {
                    aiAvatar
                }
                Text(AppInfo.displayName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.textTertiary)
                if isStreaming {
                    ThinkingIndicator()
                }
                Spacer()
            }

            // 思考链（折叠；展开状态由 ChatView 持有）
            if let reasoning = message.reasoning, !reasoning.isEmpty {
                ReasoningDisclosure(
                    text: reasoning,
                    expanded: reasoningExpanded ?? .constant(false),
                    isThinking: isStreaming
                )
            }

            // 正文（Markdown / 纯文本，随设置切换；无气泡）
            if !message.text.isEmpty {
                if settings.markdownEnabled {
                    MarkdownTextView(markdown: message.text, size: settings.chatFontSize)
                } else {
                    Text(message.text)
                        .font(.system(size: settings.chatFontSize))
                        .foregroundStyle(Color.textPrimary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
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
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(message.toolCalls) { call in
                        ToolCallRow(call: call)
                    }
                }
            }

            // 错误信息
            if let error = message.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Color.errorText)
            }

            // 本次花费（按设置页单价估算）
            if let usage = message.usage {
                let cost = usage.costYuan(
                    inputPerM: settings.inputPricePerM,
                    outputPerM: settings.outputPricePerM
                )
                Text("本次 \(UsageInfo.costText(cost))")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.textTertiary.opacity(0.8))
            }

            // 操作栏（DeepSeek 式：小灰图标，流式完成后显示）
            if !isStreaming && (isLatestAssistant || message.errorMessage != nil) {
                assistantActionBar
            }

            // 时间戳（设置项开启时展示）
            if showTimestamp {
                timestampText
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(isPresented: $showTextSelector) {
            TextSelectorView(title: "AI 回复", text: message.text)
        }
    }

    /// 消息时间戳（极小灰字）
    private var timestampText: some View {
        Text(Self.timestampFormatter.string(from: message.timestamp))
            .font(.system(size: 9.5))
            .foregroundStyle(Color.textTertiary.opacity(0.65))
    }

    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    private var aiAvatar: some View {
        ZStack {
            Circle().fill(Color.brandGradient)
            Text("N")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white)
        }
        .frame(width: 24, height: 24)
    }

    private var assistantActionBar: some View {
        HStack(spacing: 18) {
            Button {
                UIPasteboard.general.string = message.text
                Haptics.tap()
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.textTertiary)
            }
            .buttonStyle(PressableButtonStyle(scale: 0.85))

            if !message.text.isEmpty {
                Button {
                    showTextSelector = true
                } label: {
                    Image(systemName: "character.cursor.ibeam")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.textTertiary)
                }
                .buttonStyle(PressableButtonStyle(scale: 0.85))

                // 分享（系统分享面板）
                ShareLink(item: message.text) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.textTertiary)
                }
            }

            if isLatestAssistant, let onRegenerate {
                Button {
                    Haptics.tap()
                    onRegenerate()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.textTertiary)
                }
                .buttonStyle(PressableButtonStyle(scale: 0.85))
            }

            Spacer()
        }
        .padding(.top, 2)
    }

    // MARK: 工具结果行

    private var toolRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("工具 · \(message.toolName ?? "unknown")")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Color.textTertiary)
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
                .strokeBorder(Color.glassStroke, lineWidth: 1)
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

// MARK: - 思考中指示器（小灰点呼吸）

struct ThinkingIndicator: View {
    @State private var animating = false

    var body: some View {
        HStack(spacing: 3) {
            Circle()
                .fill(Color.brand)
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
            .fill(Color.brand.opacity(0.7))
            .frame(width: 6, height: 6)
            .offset(y: animating ? -3 : 2)
            .animation(
                .easeInOut(duration: 0.5).repeatForever(autoreverses: true).delay(delay),
                value: animating
            )
            .onAppear { animating = true }
    }
}

// MARK: - 思考链折叠（展开状态由 ChatView 持有，流式刷新 / 列表回收均不丢失）

struct ReasoningDisclosure: View {
    let text: String
    @Binding var expanded: Bool
    /// 是否仍在思考产出中（按钮加「思考中」呼吸态）
    var isThinking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Button {
                Haptics.tap()
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    expanded.toggle()
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "lightbulb")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(isThinking ? Color.brand : Color.textTertiary)
                    Text(expanded ? "收起思考" : "思考过程")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.textSecondary)
                        .contentTransition(.opacity)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(Color.textTertiary)
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.surfaceCard))
                .overlay(Capsule().strokeBorder(Color.glassStroke, lineWidth: 1))
            }
            .buttonStyle(PressableButtonStyle(scale: 0.95))

            if expanded {
                Text(text)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.textSecondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 10)
                    .padding(.vertical, 2)
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(Color.separator)
                            .frame(width: 2)
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

// MARK: - 工具调用行（品牌蓝淡底胶囊）

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
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(Color.brand)
            Text(displayName)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.textSecondary)
            if let path = pathArgument {
                Text(path)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.textTertiary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule().fill(Color.toolChipBG)
        )
        .overlay(Capsule().strokeBorder(Color.glassStroke, lineWidth: 1))
    }
}
