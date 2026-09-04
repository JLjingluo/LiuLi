import SwiftUI

// MARK: - 全局路由
// 负责主 Tab 切换与跨页跳转（如：文件页 → 让 AI 编辑该文件）

enum AppTab: Hashable {
    case chat
    case files
    case settings
}

@MainActor
final class AppRouter: ObservableObject {
    @Published var selectedTab: AppTab = .chat

    /// 待发送给 AI 的指令（从文件页跳转携带）
    @Published var pendingPrompt: String?

    /// 指定文件被请求编辑时跳到聊天并预填指令
    func askAI(aboutFile path: String) {
        pendingPrompt = "请帮我编辑工作区文件 \(path)："
        selectedTab = .chat
    }
}
