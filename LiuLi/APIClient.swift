import Foundation

// MARK: - API 客户端（模型列表 + 流式对话）

struct APIClientError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

final class APIClient {

    struct Endpoint {
        var base: URL
        var apiKey: String

        var chatURL: URL { base.appendingPathComponent("chat/completions") }
        var modelsURL: URL { base.appendingPathComponent("models") }
    }

    private let endpoint: Endpoint
    private let session: URLSession
    private let includeUsage: Bool

    init(endpoint: Endpoint, includeUsage: Bool) {
        self.endpoint = endpoint
        self.includeUsage = includeUsage
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 600
        self.session = URLSession(configuration: config)
    }

    // MARK: 请求头

    private var headers: [String: String] {
        var h = ["Content-Type": "application/json"]
        let key = endpoint.apiKey.trimmingCharacters(in: .whitespaces)
        if !key.isEmpty {
            h["Authorization"] = "Bearer \(key)"
        }
        return h
    }

    // MARK: 模型列表

    /// GET {base}/models → [模型 id]
    func fetchModels() async throws -> [String] {
        var request = URLRequest(url: endpoint.modelsURL)
        request.httpMethod = "GET"
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }

        let (data, response) = try await session.data(for: request)
        try Self.checkHTTP(response, data: data)

        struct ModelsResponse: Decodable {
            struct Item: Decodable { let id: String }
            let data: [Item]?
        }
        if let decoded = try? JSONDecoder().decode(ModelsResponse.self, from: data),
           let list = decoded.data {
            let ids = list.map { $0.id }.filter { !$0.isEmpty }
            if !ids.isEmpty {
                return ids.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            }
        }
        // 兼容直接返回数组的网关
        if let array = try? JSONDecoder().decode([ModelsResponse.Item].self, from: data) {
            let ids = array.map { $0.id }.filter { !$0.isEmpty }
            if !ids.isEmpty { return ids }
        }
        throw APIClientError(message: "模型列表响应格式无法识别")
    }

    // MARK: 流式对话

    /// 发起流式 chat/completions，以事件流形式产出 SSE chunk。
    /// 消费端（MainActor）直接迭代；取消消费即取消底层请求。
    func streamChat(request payload: ChatCompletionRequest) -> AsyncThrowingStream<StreamChunk, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = URLRequest(url: endpoint.chatURL)
                    request.httpMethod = "POST"
                    for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }

                    let body = ChatCompletionRequest(
                        model: payload.model,
                        messages: payload.messages,
                        stream: true,
                        temperature: payload.temperature,
                        max_tokens: payload.max_tokens,
                        tools: payload.tools,
                        tool_choice: payload.tool_choice,
                        stream_options: includeUsage ? StreamOptions(include_usage: true) : nil
                    )
                    request.httpBody = try JSONEncoder().encode(body)

                    let (bytes, response) = try await session.bytes(for: request)
                    try Self.checkHTTP(response, data: nil)

                    for try await rawLine in bytes.lines {
                        var line = rawLine
                        if line.hasSuffix("\r") { line.removeLast() } // CRLF 容错
                        guard !line.isEmpty, !SSEParser.isComment(line) else { continue }
                        guard let payload = SSEParser.payloadIfDataLine(line) else { continue }
                        if SSEParser.isDone(payload) { break }
                        guard let data = payload.data(using: .utf8) else { continue }
                        guard let chunk = try? JSONDecoder().decode(StreamChunk.self, from: data) else {
                            // 可能是错误体（部分网关在流中以 JSON 返回错误）
                            if let err = try? JSONDecoder().decode(APIErrorBody.self, from: data) {
                                throw APIClientError(message: err.message)
                            }
                            continue
                        }
                        continuation.yield(chunk)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    // MARK: HTTP 状态检查

    static func checkHTTP(_ response: URLResponse, data: Data?) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard !(400...599).contains(http.statusCode) else {
            if let data, !data.isEmpty {
                if let body = try? JSONDecoder().decode(APIErrorBody.self, from: data) {
                    throw APIClientError(message: "HTTP \(http.statusCode)：\(body.message)")
                }
                if let raw = String(data: data, encoding: .utf8), raw.count < 400 {
                    throw APIClientError(message: "HTTP \(http.statusCode)：\(raw)")
                }
            }
            throw APIClientError(message: "HTTP \(http.statusCode)")
        }
    }
}
