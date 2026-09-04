import Foundation

// MARK: - 请求体（OpenAI 兼容）

struct APIPayloadImageURL: Encodable, Equatable {
    let url: String
}

struct APIPayloadContentPart: Encodable, Equatable {
    let type: String
    let text: String?
    let image_url: APIPayloadImageURL?

    static func text(_ t: String) -> APIPayloadContentPart {
        APIPayloadContentPart(type: "text", text: t, image_url: nil)
    }
    static func imageURL(_ url: String) -> APIPayloadContentPart {
        APIPayloadContentPart(type: "image_url", text: nil, image_url: APIPayloadImageURL(url: url))
    }
}

/// content 既可能是纯字符串，也可能是多模态数组
enum APIPayloadContent: Encodable, Equatable {
    case text(String)
    case parts([APIPayloadContentPart])

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text(let s):
            try container.encode(s)
        case .parts(let p):
            try container.encode(p)
        }
    }
}

struct APIPayloadFunction: Encodable {
    let name: String
    let arguments: String
}

struct APIPayloadToolCall: Encodable {
    let id: String
    let type: String
    let function: APIPayloadFunction
}

struct APIPayloadMessage: Encodable {
    let role: String
    let content: APIPayloadContent?
    let tool_calls: [APIPayloadToolCall]?
    let tool_call_id: String?

    init(role: String, content: APIPayloadContent?, toolCalls: [APIPayloadToolCall]? = nil, toolCallID: String? = nil) {
        self.role = role
        self.content = content
        self.tool_calls = toolCalls
        self.tool_call_id = toolCallID
    }

    static func system(_ text: String) -> APIPayloadMessage {
        APIPayloadMessage(role: "system", content: .text(text))
    }
}

// MARK: - 工具 Schema

struct ToolParamProperty: Encodable {
    let type: String
    let description: String?
}

struct ToolParameters: Encodable {
    let type: String
    let properties: [String: ToolParamProperty]
    let required: [String]?
}

struct ToolFunctionSchema: Encodable {
    let name: String
    let description: String
    let parameters: ToolParameters
}

struct ToolSchema: Encodable {
    let type: String
    let function: ToolFunctionSchema
}

// MARK: - 请求

struct StreamOptions: Encodable {
    let include_usage: Bool
}

struct ChatCompletionRequest: Encodable {
    let model: String
    let messages: [APIPayloadMessage]
    let stream: Bool
    let temperature: Double?
    let max_tokens: Int?
    let tools: [ToolSchema]?
    let tool_choice: String?
    let stream_options: StreamOptions?
}

// MARK: - 流式响应块

struct StreamChunk: Decodable {
    struct Choice: Decodable {
        struct Delta: Decodable {
            struct ToolCallDelta: Decodable {
                struct Fn: Decodable {
                    let name: String?
                    let arguments: String?
                }
                let index: Int?
                let id: String?
                let type: String?
                let function: Fn?
            }
            let role: String?
            let content: String?
            let reasoning_content: String?
            let tool_calls: [ToolCallDelta]?
        }
        let delta: Delta?
        let finish_reason: String?
    }
    struct UsageChunk: Decodable {
        let prompt_tokens: Int?
        let completion_tokens: Int?
        let total_tokens: Int?
    }
    let choices: [Choice]?
    let usage: UsageChunk?
}

// MARK: - SSE 行解析

enum SSEParser {
    /// 提取 data: 行的 payload；非 data 行返回 nil
    static func payloadIfDataLine(_ line: String) -> String? {
        guard line.hasPrefix("data:") else { return nil }
        var payload = String(line.dropFirst(5))
        if payload.hasPrefix(" ") { payload.removeFirst() }
        return payload
    }

    static func isDone(_ payload: String) -> Bool {
        payload.trimmingCharacters(in: .whitespaces) == "[DONE]"
    }

    static func isComment(_ line: String) -> Bool {
        line.hasPrefix(":")
    }
}

// MARK: - 错误体（{"error": {...}} 或 {"error": "..."}）

struct APIErrorBody: Decodable {
    let message: String

    private enum CodingKeys: String, CodingKey {
        case error, message
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let detail = try? container.decode(Detail.self, forKey: .error), let m = detail.message {
            message = m
            return
        }
        if let s = try? container.decode(String.self, forKey: .error) {
            message = s
            return
        }
        if let s = try? container.decode(String.self, forKey: .message) {
            message = s
            return
        }
        message = "未知错误"
    }

    struct Detail: Decodable {
        let message: String?
    }
}

// MARK: - 流式累积器

struct ToolCallAccumulated {
    var id: String = ""
    var name: String = ""
    var arguments: String = ""
}

final class StreamAccumulator {
    private(set) var content: String = ""
    private(set) var reasoning: String = ""
    private var toolCalls: [Int: ToolCallAccumulated] = [:]
    private(set) var usage: UsageInfo?
    private(set) var finishReason: String?

    var hasToolCalls: Bool { !toolCalls.isEmpty }

    func ingest(_ chunk: StreamChunk) {
        if let u = chunk.usage {
            usage = UsageInfo(promptTokens: u.prompt_tokens ?? 0, completionTokens: u.completion_tokens ?? 0)
        }
        guard let choice = chunk.choices?.first else { return }
        if let delta = choice.delta {
            if let c = delta.content { content += c }
            if let r = delta.reasoning_content { reasoning += r }
            if let tcs = delta.tool_calls {
                for tc in tcs {
                    let idx = tc.index ?? toolCalls.count
                    var acc = toolCalls[idx] ?? ToolCallAccumulated()
                    if let i = tc.id, !i.isEmpty, acc.id.isEmpty { acc.id = i }
                    if let fn = tc.function {
                        if let n = fn.name, !n.isEmpty, acc.name.isEmpty { acc.name = n }
                        if let a = fn.arguments { acc.arguments += a }
                    }
                    toolCalls[idx] = acc
                }
            }
        }
        if let f = choice.finish_reason {
            finishReason = f
        }
    }

    func orderedToolCalls() -> [ToolCallInfo] {
        toolCalls.keys.sorted().map { idx in
            let acc = toolCalls[idx] ?? ToolCallAccumulated()
            return ToolCallInfo(
                id: acc.id.isEmpty ? "call_\(idx)" : acc.id,
                name: acc.name,
                arguments: acc.arguments
            )
        }
    }
}
