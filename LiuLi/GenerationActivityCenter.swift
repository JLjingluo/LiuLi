import Foundation
import ActivityKit

// MARK: - 实时活动桥（主 App 侧）
// 生成开始 → 灵动岛/锁屏出现「正在生成」；流式期间每秒刷新片段；结束自动消失。

@MainActor
final class GenerationActivityCenter {
    static let shared = GenerationActivityCenter()

    private var activity: Activity<GeneratingActivityAttributes>?
    private var lastUpdateAt = Date.distantPast

    /// 开始生成：发起实时活动（用户未开启/设备不支持时静默跳过）
    func start(modeName: String) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        end()
        let attributes = GeneratingActivityAttributes(modeName: modeName)
        let state = GeneratingActivityAttributes.ContentState(snippet: "正在思考…", isStreaming: true)
        activity = try? Activity.request(
            attributes: attributes,
            content: ActivityContent(state: state, staleDate: nil)
        )
    }

    /// 流式更新（内部 1s 节流，避免超出系统更新配额）
    func update(_ text: String) {
        guard let activity else { return }
        guard Date().timeIntervalSince(lastUpdateAt) >= 1.0 else { return }
        lastUpdateAt = Date()
        let cleaned = text.replacingOccurrences(of: "\n", with: " ")
        let snippet = cleaned.isEmpty ? "正在思考…" : String(cleaned.suffix(48))
        let state = GeneratingActivityAttributes.ContentState(snippet: snippet, isStreaming: true)
        Task { await activity.update(ActivityContent(state: state, staleDate: nil)) }
    }

    /// 结束：立即消失
    func end() {
        guard let activity else { return }
        self.activity = nil
        let state = GeneratingActivityAttributes.ContentState(snippet: "已生成完毕", isStreaming: false)
        Task { await activity.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: .immediate) }
    }
}
