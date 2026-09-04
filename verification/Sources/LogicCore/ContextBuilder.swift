import Foundation

// MARK: - 上下文构建（会话消息 → API 消息，纯逻辑，Linux 已测）

struct ContextBuildOptions {
    var liteSystemPrompt: String
    var deepSystemPrompt: String
    var liteWindow: Int = 8
    var deepWindow: Int = 40
}

enum ContextBuilder {

    /// 清理历史，保证 Function Calling 协议合法：
    /// - 移除尾部「带 tool_calls 但缺少对应 tool 结果」的 assistant 消息（流式中断/进程被杀的残局）
    /// - 丢弃悬空的 tool 结果
    static func sanitize(_ messages: [ChatMessage]) -> [ChatMessage] {
        var out: [ChatMessage] = []
        var pendingToolIDs: [String] = []

        for m in messages {
            switch m.role {
            case .note:
                out.append(m)
            case .assistant:
                if !pendingToolIDs.isEmpty {
                    return trimTrailingIncomplete(out)
                }
                out.append(m)
                pendingToolIDs = m.toolCalls.map { $0.id }
            case .tool:
                if let id = m.toolCallID, let i = pendingToolIDs.firstIndex(of: id) {
                    pendingToolIDs.remove(at: i)
                    out.append(m)
                } else {
                    return trimTrailingIncomplete(out)
                }
            case .user:
                if !pendingToolIDs.isEmpty {
                    return trimTrailingIncomplete(out)
                }
                out.append(m)
            }
        }
        if !pendingToolIDs.isEmpty {
            return trimTrailingIncomplete(out)
        }
        return out
    }

    private static func trimTrailingIncomplete(_ messages: [ChatMessage]) -> [ChatMessage] {
        var arr = messages
        while let last = arr.last {
            if last.role == .note { break }
            if last.role == .assistant && !last.toolCalls.isEmpty { arr.removeLast(); continue }
            if last.role == .tool { arr.removeLast(); continue }
            break
        }
        return arr
    }

    /// 构建发送给 API 的消息序列（含系统提示与上下文裁剪）
    static func buildContext(
        messages: [ChatMessage],
        mode: ChatMode,
        options: ContextBuildOptions
    ) -> [APIPayloadMessage] {
        let cleaned = sanitize(messages.filter { $0.role != .note })
        let window = mode == .lite ? options.liteWindow : options.deepWindow
        let history = Array(cleaned.suffix(max(0, window)))
        let lastUserID = cleaned.last(where: { $0.role == .user })?.id

        var out: [APIPayloadMessage] = [
            .system(mode == .lite ? options.liteSystemPrompt : options.deepSystemPrompt)
        ]

        for m in history {
            switch m.role {
            case .user:
                let includeImages = (mode == .deep) || (m.id == lastUserID)
                if m.images.isEmpty {
                    out.append(APIPayloadMessage(role: "user", content: .text(m.text)))
                } else {
                    var parts: [APIPayloadContentPart] = []
                    if !m.text.isEmpty {
                        parts.append(.text(m.text))
                    }
                    if includeImages {
                        for img in m.images {
                            parts.append(.imageURL(img))
                        }
                    }
                    if parts.isEmpty {
                        // 省流模式下历史消息被剥离图片后为空：跳过该条
                        continue
                    }
                    out.append(APIPayloadMessage(role: "user", content: .parts(parts)))
                }
            case .assistant:
                let calls = m.toolCalls.map {
                    APIPayloadToolCall(id: $0.id, type: "function", function: APIPayloadFunction(name: $0.name, arguments: $0.arguments))
                }
                let content: APIPayloadContent? = m.text.isEmpty ? nil : .text(m.text)
                out.append(APIPayloadMessage(
                    role: "assistant",
                    content: content,
                    toolCalls: calls.isEmpty ? nil : calls,
                    toolCallID: nil
                ))
            case .tool:
                out.append(APIPayloadMessage(
                    role: "tool",
                    content: .text(m.text),
                    toolCalls: nil,
                    toolCallID: m.toolCallID
                ))
            case .note:
                continue
            }
        }
        return out
    }
}
