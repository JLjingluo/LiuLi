import SwiftUI

// MARK: - 消息气泡

struct MessageBubble: View {
    let message: ChatMessage
    var isStreaming = false

    var body: some View {
        switch message.role {
        case .user:
            userBubble
        case .assistant:
            assistantBubble
        case .tool:
            toolRow
        case .note:
            noteRow
        }
    }

    // MARK: 用户气泡（右对齐，玻璃卡片）

    private var userBubble: some View {
        VStack(alignment: .trailing, spacing: 8) {
            if !message.images.isEmpty {
                imageGrid
            }
            if !message.text.isEmpty {
                Text(message.text)
                    .font(.system(size: 15))
                    .foregroundStyle(.white)
                    .textSelection(.enabled)
                    .glassCard(cornerRadius: 18, padding: 12)
                    .frame(maxWidth: 300, alignment: .trailing)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
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
                                .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                        )
                }
            }
        }
    }

    // MARK: AI 气泡（左对齐，全宽玻璃卡片 + Markdown）

    private var assistantBubble: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.liuliAccent)
                Text("琉璃")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.liuliTextTertiary)
                if isStreaming {
                    ProgressView()
                        .scaleEffect(0.6)
                }
                Spacer()
            }

            // 思考链（折叠）
            if let reasoning = message.reasoning, !reasoning.isEmpty {
                ReasoningDisclosure(text: reasoning)
            }

            // 正文
            if !message.text.isEmpty {
                MarkdownTextView(markdown: message.text)
            } else if message.toolCalls.isEmpty && isStreaming == false && message.errorMessage == nil {
                // 流式刚开始，尚无内容
                HStack(spacing: 4) {
                    ForEach(0..<3, id: \.self) { i in
                        TypingDot(delay: Double(i) * 0.18)
                    }
                }
                .padding(.top, 2)
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
                    .font(.system(size: 12))
                    .foregroundStyle(Color(red: 1.0, green: 0.6, blue: 0.5))
            }

            // Token 用量
            if let usage = message.usage {
                HStack(spacing: 4) {
                    Text("↑\(usage.promptTokens) ↓\(usage.completionTokens) tokens")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.liuliTextTertiary)
                }
            }
        }
        .padding(.horizontal, 4)
        .glassCard(cornerRadius: 20, padding: 12)
        .frame(maxWidth: .infinity, alignment: .leading)
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
                    .foregroundStyle(Color.liuliTextTertiary)
            }
            Text(message.text)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color.liuliTextSecondary)
                .lineLimit(8)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.045))
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
            .foregroundStyle(Color.liuliTextTertiary)
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
            .padding(.vertical, 4)
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
                .foregroundStyle(Color.liuliTextTertiary)
            }
            .buttonStyle(.plain)

            if expanded {
                Text(text)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.liuliTextSecondary)
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.white.opacity(0.04))
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
                .foregroundStyle(Color.liuliTextSecondary)
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
                .fill(Color.liuliTeal.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.liuliTeal.opacity(0.22), lineWidth: 0.8)
        )
    }
}
