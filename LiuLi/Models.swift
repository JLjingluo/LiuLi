import Foundation

// MARK: - 聊天数据模型（纯逻辑层，App 与测试共用）

/// 对话模式：快速（低 Token）/ 深度（全量 + 文件工具）
enum ChatMode: String, Codable {
    case lite
    case deep

    var displayName: String {
        switch self {
        case .lite: return "快速模式"
        case .deep: return "深度模式"
        }
    }
}

/// 一次模型发起的工具调用
struct ToolCallInfo: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var arguments: String
}

/// Token 用量
struct UsageInfo: Codable, Equatable {
    var promptTokens: Int
    var completionTokens: Int

    /// 按元/百万 tokens 单价估算本次花费（元）
    func costYuan(inputPerM: Double, outputPerM: Double) -> Double {
        (Double(promptTokens) * inputPerM + Double(completionTokens) * outputPerM) / 1_000_000
    }

    /// 费用展示文本：智能精度 + 去尾零（¥0.0123 / ¥1.05 / 免费）
    static func costText(_ yuan: Double) -> String {
        if yuan <= 0 { return "¥0" }
        var text: String
        if yuan >= 1 { text = String(format: "%.2f", yuan) }
        else if yuan >= 0.01 { text = String(format: "%.4f", yuan) }
        else { text = String(format: "%.6f", yuan) }
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return "¥\(text)"
    }
}

/// 消息角色：user / assistant / tool 参与协议；note 仅本地展示
enum MessageRole: String, Codable {
    case user
    case assistant
    case tool
    case note
}

/// 单条消息（扁平结构，便于持久化与渲染）
struct ChatMessage: Codable, Equatable, Identifiable {
    var id: UUID
    var role: MessageRole
    var text: String
    var reasoning: String?            // DeepSeek 思考链
    var images: [String]               // data URL，仅 user 消息
    var toolCalls: [ToolCallInfo]      // 仅 assistant 消息
    var toolCallID: String?           // 仅 tool 消息，对应 assistant.toolCalls[].id
    var toolName: String?              // 仅 tool 消息，展示用
    var usage: UsageInfo?              // 仅 assistant 消息
    var timestamp: Date
    var errorMessage: String?          // 仅 assistant 消息（当次生成失败）

    init(
        id: UUID = UUID(),
        role: MessageRole,
        text: String = "",
        reasoning: String? = nil,
        images: [String] = [],
        toolCalls: [ToolCallInfo] = [],
        toolCallID: String? = nil,
        toolName: String? = nil,
        usage: UsageInfo? = nil,
        timestamp: Date = Date(),
        errorMessage: String? = nil
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.reasoning = reasoning
        self.images = images
        self.toolCalls = toolCalls
        self.toolCallID = toolCallID
        self.toolName = toolName
        self.usage = usage
        self.timestamp = timestamp
        self.errorMessage = errorMessage
    }
}
