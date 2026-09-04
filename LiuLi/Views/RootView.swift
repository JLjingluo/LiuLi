import SwiftUI

// MARK: - 根视图（Tab 容器 · 液态玻璃）
// iOS 26：系统 TabBar 自动为 Liquid Glass 材质
// iOS 17~25：磨砂材质 + 背景（RootView 的 LiquidGlassBackground 提供折射内容）
// 主题切换即时生效：tint / 背景弥散斑 / 全局强调色一并过渡

struct RootView: View {
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var settings: AppSettings

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
        // 动态主题色（切主题后导航/Tab 高亮同步过渡）
        .tint(settings.theme.brand)
        .animation(.easeInOut(duration: 0.3), value: settings.themeID)
    }
}
