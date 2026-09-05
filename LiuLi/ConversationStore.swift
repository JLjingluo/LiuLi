import Foundation

// MARK: - 会话模型与持久化 v3
//
// 设计铁律（对标 DeepSeek 流畅度的根基）：
// 1. 会话列表是会话数组：只有「结构变化」（增删消息 / 改标题 / 改模式）才整体刷新
// 2. 流式文字永不写入 store —— 由 ChatViewModel.StreamBuffer 独立承载，
//    流式结束才一次性固化进消息。由此消灭「每 token 全量重建列表」的卡顿与崩溃根因
// 3. 每个会话一个 JSON 文件，原子写，App 被杀也不丢历史

struct Conversation: Codable, Identifiable, Equatable {
    var id: UUID
    var title: String
    var mode: ChatMode
    var messages: [ChatMessage]
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), title: String = "新对话", mode: ChatMode = .lite, messages: [ChatMessage] = []) {
        self.id = id
        self.title = title
        self.mode = mode
        self.messages = messages
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

@MainActor
final class ConversationStore: ObservableObject {

    static let shared = ConversationStore()

    /// 全部会话（按 updatedAt 倒序；结构变化才发布）
    @Published private(set) var conversations: [Conversation] = []
    /// 当前会话 id
    @Published var currentID: UUID?

    var current: Conversation? {
        conversations.first { $0.id == currentID }
    }

    private let fm = FileManager.default
    private lazy var directory: URL = {
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = docs.appendingPathComponent("Conversations", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    init() {
        loadAll()
        if conversations.isEmpty {
            let c = Conversation()
            conversations = [c]
            currentID = c.id
            persist(c)
        } else if currentID == nil || !conversations.contains(where: { $0.id == currentID }) {
            currentID = conversations.first?.id
        }
    }

    // MARK: 会话 CRUD

    @discardableResult
    func create(mode: ChatMode = .lite) -> Conversation {
        let c = Conversation(mode: mode)
        conversations.insert(c, at: 0)
        currentID = c.id
        persist(c)
        return c
    }

    func select(_ id: UUID) {
        guard conversations.contains(where: { $0.id == id }) else { return }
        currentID = id
    }

    func delete(_ id: UUID) {
        if let idx = conversations.firstIndex(where: { $0.id == id }) {
            let c = conversations.remove(at: idx)
            try? fm.removeItem(at: fileURL(for: c.id))
        }
        if currentID == id {
            currentID = conversations.first?.id
        }
        if conversations.isEmpty {
            create(mode: .lite)
        }
    }

    func rename(_ id: UUID, to title: String) {
        let t = String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(30))
        guard !t.isEmpty, var conv = conversations.first(where: { $0.id == id }) else { return }
        conv.title = t
        update(conv)
    }

    func setMode(_ id: UUID, mode: ChatMode) {
        guard var conv = conversations.first(where: { $0.id == id }) else { return }
        conv.mode = mode
        update(conv)
    }

    /// 结构变化整体更新（改标题/模式/增删消息）：刷新列表顺序并落盘
    func update(_ conversation: Conversation, persist persistToDisk: Bool = true) {
        guard let idx = conversations.firstIndex(where: { $0.id == conversation.id }) else { return }
        var c = conversation
        c.updatedAt = Date()
        conversations[idx] = c
        // 最近活跃的会话浮到列表顶部
        if idx != 0 {
            conversations.sort { $0.updatedAt > $1.updatedAt }
        }
        if persistToDisk { persist(c) }
    }

    // MARK: 消息级操作（当前会话）

    /// 追加一条消息（结构变化，视图整列刷新一次——低频操作）
    @discardableResult
    func append(_ message: ChatMessage) -> Conversation? {
        guard var conv = current else { return nil }
        conv.messages.append(message)
        update(conv, persist: false)
        return conv
    }

    /// 细粒度改写当前会话里某一条消息（供流式固化 / 工具轮次回写）
    @discardableResult
    func mutateMessage(_ id: UUID, _ mutate: (inout ChatMessage) -> Void) -> Conversation? {
        guard var conv = current else { return nil }
        guard let midx = conv.messages.firstIndex(where: { $0.id == id }) else { return nil }
        mutate(&conv.messages[midx])
        update(conv, persist: false)
        return conv
    }

    /// 移除当前会话末尾的最后一条 assistant 消息组（重新生成用）
    @discardableResult
    func trimTrailingAssistantGroup() -> Conversation? {
        guard var conv = current else { return nil }
        while let last = conv.messages.last, last.role != .user {
            conv.messages.removeLast()
        }
        update(conv, persist: false)
        return conv
    }

    /// 当前会话快照（生成管线持有，避免与视图刷新读写竞争）
    func snapshot() -> Conversation? { current }

    /// 生成管线回写快照（结构变化，低频）
    func commit(_ conversation: Conversation, persist persistToDisk: Bool = false) {
        update(conversation, persist: persistToDisk)
    }

    /// 强制落盘
    func persistToDisk(_ conversation: Conversation) {
        persist(conversation)
    }

    // MARK: 持久化

    private func fileURL(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).json")
    }

    private func loadAll() {
        guard let files = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        var loaded: [Conversation] = []
        for file in files where file.pathExtension == "json" {
            guard let data = fm.contents(atPath: file.path),
                  let c = try? JSONDecoder().decode(Conversation.self, from: data) else { continue }
            loaded.append(c)
        }
        conversations = loaded.sorted { $0.updatedAt > $1.updatedAt }
    }

    private func persist(_ c: Conversation) {
        guard let data = try? JSONEncoder().encode(c) else { return }
        try? data.write(to: fileURL(for: c.id), options: .atomic)
    }
}
