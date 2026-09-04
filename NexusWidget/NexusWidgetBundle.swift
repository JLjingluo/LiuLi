import WidgetKit
import SwiftUI

// MARK: - Widget 扩展（灵动岛 / 锁屏实时活动 UI）
// 主 App 通过 ActivityKit 发起/更新，本扩展负责渲染。

@main
struct NexusWidgetBundle: WidgetBundle {
    var body: some Widget {
        GeneratingActivityWidget()
    }
}

struct GeneratingActivityWidget: Widget {
    private let brand = Color(red: 0.302, green: 0.420, blue: 0.996)

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: GeneratingActivityAttributes.self) { context in
            // 锁屏 / 灵动岛展开态共用卡片
            HStack(spacing: 10) {
                Image(systemName: "bubble.left.and.text.bubble.right.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(brand))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Nexus · \(context.attributes.modeName)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(context.state.snippet)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                if context.state.isStreaming {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
            .padding(12)
            .activityBackgroundTint(Color(red: 0.97, green: 0.97, blue: 0.99))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.snippet)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(2)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if context.state.isStreaming {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.white)
                    }
                }
            } compactLeading: {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
            } compactTrailing: {
                if context.state.isStreaming {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.white)
                }
            } minimal: {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
    }
}
