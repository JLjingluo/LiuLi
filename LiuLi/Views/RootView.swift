import SwiftUI

// MARK: - 根视图（Tab 容器 · 液态玻璃）
// iOS 26：系统 TabBar 自动为 Liquid Glass 材质
// iOS 17~25：磨砂材质 + 背景（RootView 的 LiquidGlassBackground 提供折射内容）

struct RootView: View {
    @EnvironmentObject private var router: AppRouter

    var body: some View {
        ZStack {
            LiquidGlassBackground()

            TabView(selection: $router.selectedTab) {
                ChatView()
                    .tabItem {
                        Label("对话", systemImage: "bubble.left")
                    }
                    .tag(AppTab.chat)

                FilesView()
                    .tabItem {
                        Label("文件", systemImage: "folder")
                    }
                    .tag(AppTab.files)

                SettingsView()
                    .tabItem {
                        Label("设置", systemImage: "gearshape")
                    }
                    .tag(AppTab.settings)
            }
        }
    }
}
