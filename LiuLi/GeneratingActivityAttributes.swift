import Foundation
import ActivityKit

// MARK: - 生成中实时活动（灵动岛 / 锁屏）属性
// 本文件同时编译进主 App 与 Widget 扩展（双 target 共享）

struct GeneratingActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        /// 当前生成的最新文字片段
        var snippet: String
        /// 是否仍在生成
        var isStreaming: Bool
    }

    /// 模式名（快速 / 深度）
    var modeName: String
}
