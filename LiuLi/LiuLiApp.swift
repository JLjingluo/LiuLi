import SwiftUI

@main
struct LiuLiApp: App {
    @StateObject private var settings = AppSettings.shared
    @StateObject private var router = AppRouter()
    @StateObject private var store = ConversationStore.shared

    init() {
        // 确保工作区与模型会话目录存在
        let fm = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        for sub in ["Conversations"] {
            try? fm.createDirectory(
                at: docs.appendingPathComponent(sub, isDirectory: true),
                withIntermediateDirectories: true
            )
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(settings)
                .environmentObject(router)
                .environmentObject(store)
                // 默认浅色系（对标 DeepSeek；深色模式仍完整适配）
                // tint 由 RootView 按当前主题动态下发（主题切换即时生效）
                .preferredColorScheme(.light)
        }
    }
}
