import SwiftUI

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
