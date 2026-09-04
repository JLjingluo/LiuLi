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
                // 跟随系统深浅色（液态玻璃两套材质均已适配）
                .preferredColorScheme(nil)
                .tint(Color.liuliAccent)
        }
    }
}
