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

                    // HTTP 错误：读取响应体里的服务商报错，转成中文建议
                    if let http = response as? HTTPURLResponse, (400...599).contains(http.statusCode) {
                        var raw = ""
                        for try await line in bytes.lines {
                            raw += line
                            if raw.utf8.count > 4000 { break }
                        }
                        let provider = (try? JSONDecoder().decode(APIErrorBody.self, from: Data(raw.utf8)))?.message
                        throw APIClientError(message: Self.friendlyError(status: http.statusCode, providerMessage: provider))
                    }

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
            var provider: String?
            if let data, !data.isEmpty {
                provider = (try? JSONDecoder().decode(APIErrorBody.self, from: data))?.message
                    ?? (String(data: data, encoding: .utf8).map { String($0.prefix(200)) })
            }
            throw APIClientError(message: friendlyError(status: http.statusCode, providerMessage: provider))
        }
    }
}

// MARK: - 错误中文化（所有对外报错均给中文建议）

extension APIClient {

    /// HTTP 状态码 → 中文建议（附服务商原始报错）
    static func friendlyError(status: Int, providerMessage: String?) -> String {
        let hint: String
        switch status {
        case 400:
            hint = "请求被服务商拒绝（400）。常见原因：模型名称不正确、该模型不支持识图或工具调用、参数不兼容。请到「设置」核对模型名。"
        case 401:
            hint = "API Key 无效或未授权（401）。请到「设置」检查 Key 是否填写正确。"
        case 402, 420:
            hint = "账户余额不足或已欠费（\(status)）。请到服务商控制台充值后重试。"
        case 403:
            hint = "没有访问该模型的权限（403）。可能此模型未对你的 Key 开放，请换个模型。"
        case 404:
            hint = "接口地址或模型不存在（404）。请到「设置」检查 Base URL 是否以 /v1 结尾、模型名是否正确。"
        case 408:
            hint = "请求超时（408）。网络不稳定，稍后重试即可。"
        case 413:
            hint = "请求内容过大（413）。请开启新对话或删减超长内容后重试。"
        case 429:
            hint = "请求过于频繁或额度受限（429）。请等几秒再发送。"
        case 500...599:
            hint = "服务商服务器故障（\(status)）。稍等片刻再试。"
        default:
            hint = "网络请求失败（\(status)）。"
        }
        if let m = providerMessage, !m.isEmpty {
            return hint + "（服务商返回：\(m)）"
        }
        return hint
    }

    /// 网络层错误（超时/断网/DNS…）→ 中文建议
    static func friendlyNetworkError(_ error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut:
                return "网络超时：服务器长时间没有响应，请重试。"
            case .notConnectedToInternet:
                return "设备未联网，请检查网络后重试。"
            case .networkConnectionLost:
                return "网络连接中断：Wi-Fi/蜂窝切换或信号波动导致，请重试。"
            case .cannotFindHost, .cannotConnectToHost:
                return "无法连接服务器：请到「设置」检查 Base URL 是否正确（需包含 /v1）。"
            case .badURL:
                return "接口地址无效：请到「设置」检查 Base URL 格式（例如 https://api.deepseek.com/v1）。"
            case .secureConnectionFailed:
                return "安全连接失败：HTTPS 握手出错，请稍后重试或更换网络。"
            case .cancelled:
                return "请求已取消。"
            default:
                return "网络异常：\(urlError.localizedDescription)"
            }
        }
        return error.localizedDescription
    }

    /// 统一错误文案（APIClientError 原样透传，其余网络错误中文化）
    static func describe(_ error: Error) -> String {
        (error as? APIClientError)?.message ?? friendlyNetworkError(error)
    }
}
