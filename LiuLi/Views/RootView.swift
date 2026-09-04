import SwiftUI

// MARK: - 根视图（液态玻璃 Tab 容器）
// iOS 26：原生 TabBar 已是 Liquid Glass 材质，直接使用
// iOS 17~25：系统 TabBar + ultraThinMaterial 后台弥散背景

struct RootView: View {
    @EnvironmentObject private var router: AppRouter

    var body: some View {
        ZStack {
            LiquidGlassBackground()

            TabView(selection: $router.selectedTab) {
                ChatView()
                    .tabItem {
                        Label("对话", systemImage: "bubble.left.and.bubble.right.fill")
                    }
                    .tag(AppTab.chat)

                FilesView()
                    .tabItem {
                        Label("文件", systemImage: "folder.fill")
                    }
                    .tag(AppTab.files)

                SettingsView()
                    .tabItem {
                        Label("设置", systemImage: "gearshape.fill")
                    }
                    .tag(AppTab.settings)
            }
        }
    }
}
