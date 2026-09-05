import Foundation
import SwiftUI

// MARK: - 待发送图片（识图）

struct PendingImage: Identifiable, Equatable {
    let id = UUID()
    let dataURL: String

    var thumbnail: UIImage? {
        ImageCompressor.imageFromDataURL(dataURL)
    }
}

// MARK: - 流式内容缓冲（v3 架构核心）
//
// DeepSeek 式流畅的关键：正在生成的文字放在独立的 @Published 缓冲里，
// 由正在流式的那一条消息气泡内部的子视图单独订阅（其余气泡不订阅、零开销）。
// 流式结束后一次性固化进 store 完成持久化。

@MainActor
final class StreamBuffer: ObservableObject {
    /// 正在流式生成的 assistant 消息 id（nil = 无流式）
    @Published private(set) var activeID: UUID?
    /// 流式正文（增量累积）
    @Published private(set) var text: String = ""
    /// 流式思考链（增量累积）
    @Published private(set) var reasoning: String = ""
    /// 是否已开始产出正文（区分「排队中」与「正在输出」两种等待态）
    @Published private(set) var hasContent: Bool = false

    // token 到着先落待刷新区，~20fps 合并发布：
    // 订阅视图每秒最多重绘 20 次（DeepSeek 式平滑打字，同时杜绝高频刷新带来的主线程压力）
    private var pendingText = ""
    private var pendingReasoning = ""
    private var flushScheduled = false

    func begin(id: UUID) {
        activeID = id
        text = ""
        reasoning = ""
        hasContent = false
        pendingText = ""
        pendingReasoning = ""
        flushScheduled = false
    }

    func append(content: String?, reasoningPart: String?) {
        if let r = reasoningPart, !r.isEmpty { pendingReasoning += r }
        if let c = content, !c.isEmpty { pendingText += c }
        scheduleFlush()
    }

    private func scheduleFlush() {
        guard !flushScheduled else { return }
        flushScheduled = true
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms ≈ 20fps
            guard let self, !Task.isCancelled else { return }
            self.flush()
        }
    }

    /// 立即把待刷新区并入已发布区（收尾/固化前调用，保证最后一个 token 不丢）
    func flush() {
        flushScheduled = false
        if !pendingReasoning.isEmpty {
            reasoning += pendingReasoning
            pendingReasoning = ""
        }
        if !pendingText.isEmpty {
            text += pendingText
            pendingText = ""
            hasContent = true
        }
    }

    func finish() {
        activeID = nil
        text = ""
        reasoning = ""
        hasContent = false
        pendingText = ""
        pendingReasoning = ""
        flushScheduled = false
    }
}

// MARK: - 聊天视图模型 v3（流式 + Agent 工具循环）

@MainActor
final class ChatViewModel: ObservableObject {

    // 输入区
    @Published var draft: String = ""
    @Published var pendingImages: [PendingImage] = []

    // 生成状态
    @Published private(set) var isStreaming = false
    /// 滚动跟随信号（节流 ~8 次/秒，视图据此回底）
    @Published private(set) var scrollTick: Int = 0

    // 识图提示
    @Published var visionWarning: String?

    // 提示词优化
    @Published private(set) var isOptimizing = false
    @Published private(set) var undoableOptimizedText: String?

    /// 流式内容缓冲（视图单独订阅）
    let stream = StreamBuffer()

    // 依赖与内部状态
    private let store: ConversationStore
    private let settings: AppSettings
    private let toolBox: AgentToolBox
    private var streamTask: Task<Void, Never>?
    private var lastTickAt = Date.distantPast
    private var lastChunkAt = Date()
    private var bgTask: UIBackgroundTaskIdentifier = .invalid
    private var latestSnapshot: Conversation?

    static let maxToolRounds = 8

    init(store: ConversationStore, settings: AppSettings) {
        self.store = store
        self.settings = settings
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        self.toolBox = AgentToolBox(root: docs)
    }

    // MARK: 发送

    var canSend: Bool {
        !isStreaming && settings.isConfigured &&
        (!draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !pendingImages.isEmpty)
    }

    var modelSupportsVision: Bool {
        VisionCapability.likelySupportsVision(modelID: settings.model)
    }

    func send() {
        guard canSend else { return }
        let prompt = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let images = pendingImages.map { $0.dataURL }
        draft = ""
        pendingImages = []

        guard var conv = store.snapshot() else { return }
        conv.messages.append(ChatMessage(role: .user, text: prompt, images: images))
        if conv.title == "新对话", !prompt.isEmpty {
            conv.title = String(prompt.prefix(18))
        }
        store.commit(conv, persist: true)
        startGeneration()
    }

    /// 重新生成：移除末尾 assistant 组，重新请求
    func regenerate() {
        guard !isStreaming else { return }
        guard let conv = store.trimTrailingAssistantGroup() else { return }
        guard conv.messages.contains(where: { $0.role == .user }) else { return }
        startGeneration()
    }

    // MARK: 停止

    func stop() {
        streamTask?.cancel()
        streamTask = nil
    }

    /// 前台恢复检查：后台挂起导致的僵死流自动收尾
    func recoverIfNeeded() {
        guard isStreaming else { return }
        guard Date().timeIntervalSince(lastChunkAt) > 30 else { return }
        streamTask?.cancel()
        streamTask = nil
    }

    // MARK: 提示词优化

    private static let optimizerSystemPrompt = """
    你是提示词优化专家。把用户给你的原句改写成一条清晰、具体、可直接发给 AI 助手的中文提示词：
    - 补全缺失的上下文、目标与期望的输出形式（如字数、格式、风格）
    - 忠于用户原意，不臆造额外约束
    - 直接输出优化后的提示词本身，不要任何解释、前后缀或引号包裹
    """

    /// 优化输入框草稿；成功返回 nil 并写入 draft（可撤销），失败返回中文错误描述
    @discardableResult
    func optimizeDraft() async -> String? {
        let raw = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return "请先输入要优化的内容" }
        guard !isOptimizing else { return nil }
        guard !isStreaming else { return "正在生成回复，请等结束后再优化" }
        guard settings.isConfigured else { return "请先在「设置」中完成 API 配置，才能使用提示词优化" }

        isOptimizing = true
        defer { isOptimizing = false }

        let client = APIClient(
            endpoint: APIClient.Endpoint(
                base: settings.baseURL ?? URL(fileURLWithPath: "/"),
                apiKey: settings.apiKey
            ),
            includeUsage: false
        )
        let payload = ChatCompletionRequest(
            model: settings.model,
            messages: [
                .system(Self.optimizerSystemPrompt),
                APIPayloadMessage(role: "user", content: .text(raw))
            ],
            stream: false,
            temperature: 0.3,
            max_tokens: 512,
            tools: nil,
            tool_choice: nil,
            stream_options: nil
        )

        do {
            let optimized = try await client.completeChat(request: payload)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !optimized.isEmpty else {
                undoableOptimizedText = nil
                return "模型未返回优化结果，请重试"
            }
            undoableOptimizedText = raw
            draft = optimized
            return nil
        } catch {
            undoableOptimizedText = nil
            return "优化失败：\(APIClient.describe(error))"
        }
    }

    func undoOptimize() {
        guard let original = undoableOptimizedText else { return }
        draft = original
        undoableOptimizedText = nil
    }

    func dismissOptimizeState() {
        undoableOptimizedText = nil
    }

    private var contextOptions: ContextBuildOptions {
        let lite = settings.systemPromptLite.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? AppSettings.defaultLiteSystemPrompt : settings.systemPromptLite
        let deep = settings.systemPromptDeep.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? AppSettings.defaultDeepSystemPrompt : settings.systemPromptDeep
        return ContextBuildOptions(liteSystemPrompt: lite, deepSystemPrompt: deep)
    }

    // MARK: 后台任务断言

    private func beginBackgroundWork() {
        guard bgTask == .invalid else { return }
        bgTask = UIApplication.shared.beginBackgroundTask(withName: "NexusGeneration") { [weak self] in
            Task { @MainActor in
                if let snap = self?.latestSnapshot {
                    self?.store.persistToDisk(snap)
                }
                self?.endBackgroundWork()
            }
        }
    }

    private func endBackgroundWork() {
        guard bgTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(bgTask)
        bgTask = .invalid
    }

    // MARK: 生成主循环

    private func startGeneration() {
        guard let snapshot = store.snapshot() else { return }

        isStreaming = true
        lastChunkAt = Date()
        GenerationActivityCenter.shared.start(modeName: snapshot.mode.displayName)
        beginBackgroundWork()

        streamTask = Task { [weak self] in
            guard let self else { return }
            var working = snapshot
            await self.generationLoop(working: &working)
            // 收尾（正常完成 / 取消 / 异常都走这里）
            // 顺序：先固化进 store，再停缓冲、再落 isStreaming——
            // 同一 runloop 内合并为一次视图更新，气泡直接从「流式态」切到「完整正文」，无空帧
            self.store.commit(working, persist: true)
            self.stream.finish()
            self.isStreaming = false
            self.latestSnapshot = nil
            self.endBackgroundWork()
            GenerationActivityCenter.shared.end()
        }
    }

    private func generationLoop(working: inout Conversation) async {
        let mode = working.mode
        let client = APIClient(
            endpoint: APIClient.Endpoint(
                base: settings.baseURL ?? URL(fileURLWithPath: "/"),
                apiKey: settings.apiKey
            ),
            includeUsage: settings.includeUsage
        )

        for _ in 0..<Self.maxToolRounds {
            if Task.isCancelled { finalizeStopped(working: &working); return }

            let context = ContextBuilder.buildContext(
                messages: working.messages, mode: mode, options: contextOptions
            )
            let payload = ChatCompletionRequest(
                model: settings.model,
                messages: context,
                stream: true,
                temperature: mode == .lite ? 0.5 : 0.7,
                max_tokens: nil,
                tools: mode == .deep ? AgentToolBox.toolSchemas() : nil,
                tool_choice: mode == .deep ? "auto" : nil,
                stream_options: nil
            )

            // 流式占位：空壳 assistant 进 store（结构变化一次），内容走 StreamBuffer
            // 顺序：先 begin 再 commit——视图因结构插入重算时 activeID 已就位，气泡即刻进入流式态
            let assistantID = UUID()
            stream.begin(id: assistantID)
            working.messages.append(ChatMessage(id: assistantID, role: .assistant))
            store.commit(working, persist: false)
            emitTick(immediate: true)

            let accumulator = StreamAccumulator()
            var streamError: Error?

            do {
                for try await chunk in client.streamChat(request: payload) {
                    if Task.isCancelled { break }
                    lastChunkAt = Date()
                    accumulator.ingest(chunk)
                    let delta = chunk.choices?.first?.delta
                    stream.append(content: delta?.content, reasoningPart: delta?.reasoning_content)
                    GenerationActivityCenter.shared.update(stream.text)
                    emitTick()
                }
            } catch {
                streamError = error
            }
            latestSnapshot = working

            if Task.isCancelled {
                finalizeStopped(working: &working, assistantID: assistantID)
                return
            }

            // 工具调用分支：固化本轮 assistant → 执行工具 → 追加 tool 结果 → 下一轮
            if accumulator.hasToolCalls {
                let calls = accumulator.orderedToolCalls()
                mutate(working: &working, id: assistantID) { m in
                    m.text = accumulator.content
                    m.reasoning = accumulator.reasoning.isEmpty ? nil : accumulator.reasoning
                    m.toolCalls = calls
                    m.usage = accumulator.usage
                }
                store.commit(working, persist: false)
                for call in calls {
                    if Task.isCancelled { finalizeStopped(working: &working); return }
                    let result = toolBox.execute(name: call.name, argumentsJSON: call.arguments)
                    working.messages.append(ChatMessage(
                        role: .tool, text: result, toolCallID: call.id, toolName: call.name
                    ))
                    store.commit(working, persist: false)
                }
                emitTick(immediate: true)
                continue
            }

            // 普通完成：缓冲固化进消息（先冲刷待刷新区，最后一个 token 不丢）
            stream.flush()
            mutate(working: &working, id: assistantID) { m in
                let finalText = accumulator.content.isEmpty ? stream.text : accumulator.content
                m.text = finalText
                m.reasoning = accumulator.reasoning.isEmpty
                    ? (stream.reasoning.isEmpty ? nil : stream.reasoning)
                    : accumulator.reasoning
                m.usage = accumulator.usage
                if let streamError {
                    let message = APIClient.describe(streamError)
                    m.errorMessage = finalText.isEmpty ? message : "（生成中断：\(message)）"
                }
                if m.text.isEmpty && streamError == nil && m.toolCalls.isEmpty {
                    m.text = "（模型未返回内容）"
                }
            }
            return
        }

        working.messages.append(ChatMessage(
            role: .note,
            text: "已达到工具调用轮数上限（\(Self.maxToolRounds)），已停止以避免循环。"
        ))
    }

    /// 用户主动停止 / 后台僵死：把缓冲内容固化，保留已生成部分
    private func finalizeStopped(working: inout Conversation, assistantID: UUID? = nil) {
        stream.flush()
        if let assistantID,
           let idx = working.messages.firstIndex(where: { $0.id == assistantID }) {
            working.messages[idx].text = stream.text.isEmpty ? "（已停止）" : stream.text
            working.messages[idx].reasoning = stream.reasoning.isEmpty ? nil : stream.reasoning
        } else if let last = working.messages.last, last.role == .assistant, last.text.isEmpty {
            let idx = working.messages.count - 1
            working.messages[idx].text = "（生成中断，请点重新生成）"
        }
    }

    private func mutate(working: inout Conversation, id: UUID, _ mutate: (inout ChatMessage) -> Void) {
        guard let idx = working.messages.firstIndex(where: { $0.id == id }) else { return }
        mutate(&working.messages[idx])
    }

    // MARK: 滚动跟随信号（节流 ~8 次/秒）

    private func emitTick(immediate: Bool = false) {
        guard immediate || Date().timeIntervalSince(lastTickAt) >= 0.12 else { return }
        lastTickAt = Date()
        scrollTick &+= 1
    }
}
