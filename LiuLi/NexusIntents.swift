import Foundation
import AppIntents

// MARK: - Siri 快捷指令（App Shortcuts）
// 无需额外 target：主 App 内注册，系统自动出现在 Siri / 锁屏 / Spotlight 快捷指令里。
// 可用说法示例：
//   ·「Siri，用 Nexus 问 今天北京天气怎么样」
//   ·「Siri，用 Nexus 新对话」

extension Notification.Name {
    /// Siri 提问 → object = 问题文本
    static let nexusSiriPrompt = Notification.Name("NexusSiriPrompt")
    /// Siri 新建对话
    static let nexusSiriNewChat = Notification.Name("NexusSiriNewChat")
}

/// Siri / 快捷指令：向 Nexus 提问（打开 App 并自动填入输入框）
struct AskNexusIntent: AppIntent {
    static var title: LocalizedStringResource = "向 Nexus 提问"
    static let description = IntentDescription("打开 Nexus 并把问题填入输入框，可直接发送。")
    static let openAppWhenRun = true

    @Parameter(title: "问题", requestValueDialog: "你想问什么？")
    var question: String

    @MainActor
    func perform() async throws -> some IntentResult {
        NotificationCenter.default.post(name: .nexusSiriPrompt, object: question)
        return .result()
    }
}

/// Siri / 快捷指令：新建对话
struct NewNexusChatIntent: AppIntent {
    static var title: LocalizedStringResource = "新建 Nexus 对话"
    static let description = IntentDescription("打开 Nexus 并创建一个新对话。")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        NotificationCenter.default.post(name: .nexusSiriNewChat, object: nil)
        return .result()
    }
}

/// App 快捷指令注册（Siri 直接可说，无需手动添加）
struct NexusShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AskNexusIntent(),
            phrases: ["用\(.applicationName)问", "\(.applicationName)提问"],
            shortTitle: "提问",
            systemImageName: "bubble.left.and.text.bubble.right"
        )
        AppShortcut(
            intent: NewNexusChatIntent(),
            phrases: ["用\(.applicationName)新对话", "\(.applicationName)新建对话"],
            shortTitle: "新建对话",
            systemImageName: "plus.bubble"
        )
    }
}
