import Foundation
import SwiftUI

// MARK: - 待发送图片（识图）

struct PendingImage: Identifiable, Equatable {
    let id: UUID
    let dataURL: String

    var thumbnail: UIImage? {
        ImageCompressor.imageFromDataURL(dataURL)
    }
}

// MARK: - 聊天视图模型（流式 + Agent 工具循环）

@MainActor
final class ChatViewModel: ObservableObject {

    // 绑定数据
    @Published var draft: String = ""
    @Published var pendingImages: [PendingImage] = []
    @Published var isStreaming = false
    @Published var visionWarning: String?

    // 依赖
    private let store: ConversationStore
    private let settings: AppSettings
    private let toolBox: AgentToolBox
    private var streamTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?

    /// 工具循环最大轮数（防死循环）
    static let maxToolRounds = 8

    init(store: ConversationStore, settings: AppSettings) {
        self.store = store
        self.settings = settings
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        self.toolBox = AgentToolBox(root: docs)
    }

    // MARK: 系统提示

    private static let liteSystemPrompt = """
    你是「琉璃」，一个简洁高效的手机助手。请用简体中文回答，直击要点，默认不使用 Markdown 标题与加粗，短问题给短答案。
    """

    private static let deepSystemPrompt = """
    你是「琉璃」，一个专业的 AI 编程与文件助手。工作区内文件可通过工具访问。回答使用 Markdown；代码放入代码块并标注语言；涉及文件操作时优先使用工具完成而非只给建议。
    """

    private var contextOptions: ContextBuildOptions {
        ContextBuildOptions(
            liteSystemPrompt: Self.liteSystemPrompt,
            deepSystemPrompt: Self.deepSystemPrompt
        )
    }

    // MARK: 发送

    var canSend: Bool {
        !isStreaming && settings.isConfigured &&
        (!draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !pendingImages.isEmpty)
    }

    /// 识图能力预检：当前模型不支持视觉时给出提示
    var modelSupportsVision: Bool {
        VisionCapability.likelySupportsVision(modelID: settings.model)
    }

    func send() {
        guard canSend else { return }

        let prompt = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let images = pendingImages.map { $0.dataURL }
        draft = ""
        pendingImages = []

        // 用户已通过附图时的多模态提示确认，这里直接发送

        guard let conv = store.current else { return }
        var conversation = conv

        // 用户消息
        conversation.messages.append(ChatMessage(role: .user, text: prompt, images: images))
        // 会话标题：取首条用户消息前 18 字
        if conversation.title == "新对话", !prompt.isEmpty {
            conversation.title = String(prompt.prefix(18))
        }
        store.update(conversation)

        runGeneration()
    }

    /// 重新生成：移除末尾 assistant 组，重新请求
    func regenerate() {
        guard !isStreaming, let conv = store.current else { return }
        var conversation = conv
        // 去掉末尾连续的 assistant/tool 消息（保留最后的用户消息）
        while let last = conversation.messages.last, last.role != .user {
            conversation.messages.removeLast()
        }
        guard conversation.messages.contains(where: { $0.role == .user }) else { return }
        store.update(conversation)
        runGeneration()
    }

    // MARK: 停止

    func stop() {
        streamTask?.cancel()
        streamTask = nil
        isStreaming = false
    }

    // MARK: 生成主循环

    private func runGeneration() {
        guard let conv = store.current else { return }
        var conversation = conv
        let mode = conversation.mode

        isStreaming = true
        streamTask = Task { [weak self] in
            guard let self else { return }
            defer {
                self.isStreaming = false
                self.store.persistToDisk(conversation) // 最终落盘
            }

            let client = APIClient(
                endpoint: APIClient.Endpoint(
                    base: self.settings.baseURL ?? URL(fileURLWithPath: "/"),
                    apiKey: self.settings.apiKey
                ),
                includeUsage: self.settings.includeUsage
            )

            for round in 0..<Self.maxToolRounds {
                if Task.isCancelled { return }

                // 1. 构建上下文（含历史修复）
                let context = ContextBuilder.buildContext(
                    messages: conversation.messages,
                    mode: mode,
                    options: self.contextOptions
                )

                // 2. 请求（深度模式带文件工具）
                let payload = ChatCompletionRequest(
                    model: self.settings.model,
                    messages: context,
                    stream: true,
                    temperature: mode == .lite ? 0.5 : 0.7,
                    max_tokens: nil,
                    tools: mode == .deep ? AgentToolBox.toolSchemas() : nil,
                    tool_choice: mode == .deep ? "auto" : nil,
                    stream_options: nil
                )

                // 3. 流式占位 assistant 消息
                var assistantMessage = ChatMessage(role: .assistant)
                conversation.messages.append(assistantMessage)
                let assistantIndex = conversation.messages.count - 1
                self.refresh(conversation)

                let accumulator = StreamAccumulator()
                var streamError: Error?

                do {
                    for try await chunk in client.streamChat(request: payload) {
                        if Task.isCancelled { break }
                        accumulator.ingest(chunk)
                        // 增量更新占位消息（直接改内存，节流落盘）
                        if let delta = chunk.choices?.first?.delta {
                            if let c = delta.content, !c.isEmpty {
                                conversation.messages[assistantIndex].text += c
                            }
                            if let r = delta.reasoning_content, !r.isEmpty {
                                conversation.messages[assistantIndex].reasoning =
                                    (conversation.messages[assistantIndex].reasoning ?? "") + r
                            }
                        }
                        self.refresh(conversation)
                    }
                } catch {
                    streamError = error
                }

                if Task.isCancelled {
                    // 用户主动停止：保留已有内容
                    conversation.messages[assistantIndex].text =
                        conversation.messages[assistantIndex].text.isEmpty
                            ? "（已停止）"
                            : conversation.messages[assistantIndex].text
                    self.refresh(conversation)
                    return
                }

                // 4. 工具调用分支
                if accumulator.hasToolCalls {
                    let calls = accumulator.orderedToolCalls()
                    // 4a. 固化 assistant 工具消息
                    conversation.messages[assistantIndex].toolCalls = calls
                    conversation.messages[assistantIndex].text = accumulator.content
                    conversation.messages[assistantIndex].reasoning = accumulator.reasoning.isEmpty ? nil : accumulator.reasoning
                    conversation.messages[assistantIndex].usage = accumulator.usage
                    self.refresh(conversation)

                    // 4b. 逐个执行工具并回填结果
                    for call in calls {
                        let result = self.toolBox.execute(name: call.name, argumentsJSON: call.arguments)
                        conversation.messages.append(ChatMessage(
                            role: .tool,
                            text: result,
                            toolCallID: call.id,
                            toolName: call.name
                        ))
                        self.refresh(conversation)
                    }
                    continue // 下一轮
                }

                // 5. 普通完成
                conversation.messages[assistantIndex].text = accumulator.content.isEmpty
                    ? conversation.messages[assistantIndex].text
                    : accumulator.content
                conversation.messages[assistantIndex].reasoning = accumulator.reasoning.isEmpty
                    ? conversation.messages[assistantIndex].reasoning
                    : accumulator.reasoning
                conversation.messages[assistantIndex].usage = accumulator.usage

                if let error = streamError {
                    let hasPartial = !conversation.messages[assistantIndex].text.isEmpty
                    conversation.messages[assistantIndex].errorMessage = hasPartial
                        ? "（生成中断：\(error.localizedDescription)）"
                        : error.localizedDescription
                }
                if accumulator.content.isEmpty && streamError == nil && conversation.messages[assistantIndex].text.isEmpty {
                    conversation.messages[assistantIndex].text = "（模型未返回内容）"
                }
                self.refresh(conversation)
                return
            }

            // 工具轮数耗尽
            conversation.messages.append(ChatMessage(
                role: .note,
                text: "已达到工具调用轮数上限（\(Self.maxToolRounds)），已停止以避免循环。"
            ))
            self.refresh(conversation)
        }
    }

    /// 内存即时更新 + 节流落盘（流式期间避免每 token 写盘）
    private func refresh(_ conversation: Conversation) {
        store.update(conversation, persist: false)
        schedulePersist(conversation)
    }

    private func schedulePersist(_ conversation: Conversation) {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 900_000_000) // 0.9s 防抖
            guard !Task.isCancelled, let self else { return }
            self.store.persistToDisk(conversation)
        }
    }
}
