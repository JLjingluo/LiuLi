import Foundation

// MARK: - 会话模型与持久化

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

    @Published private(set) var conversations: [Conversation] = []
    @Published var currentID: UUID?

    private let fm = FileManager.default
    private lazy var directory: URL = {
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = docs.appendingPathComponent("Conversations", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    var current: Conversation? {
        get { conversations.first { $0.id == currentID } }
    }

    init() {
        loadAll()
        if currentID == nil {
            currentID = conversations.first?.id
        }
        // 冷启动无任何会话时自动建一个
        if conversations.isEmpty {
            let c = Conversation()
            conversations.append(c)
            currentID = c.id
            persist(c)
        }
    }

    // MARK: CRUD

    @discardableResult
    func create(mode: ChatMode = .lite) -> Conversation {
        let c = Conversation(mode: mode)
        conversations.insert(c, at: 0)
        currentID = c.id
        persist(c)
        return c
    }

    func select(_ id: UUID) {
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

    /// 更新会话（写入内存；persist=true 时立即落盘）
    func update(_ conversation: Conversation, persist: Bool = true) {
        if let idx = conversations.firstIndex(where: { $0.id == conversation.id }) {
            var c = conversation
            c.updatedAt = Date()
            conversations[idx] = c
            if persist {
                persistToDisk(c)
            }
        }
    }

    /// 强制落盘（流式结束/节流后调用）
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
                  let c = try? JSONDecoder().decode(Conversation.self, from: data) else {
                continue
            }
            loaded.append(c)
        }
        conversations = loaded.sorted { $0.updatedAt > $1.updatedAt }
    }

    private func persist(_ c: Conversation) {
        let url = fileURL(for: c.id)
        if let data = try? JSONEncoder().encode(c) {
            try? data.write(to: url, options: .atomic)
        }
    }
}
