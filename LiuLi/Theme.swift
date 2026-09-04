import SwiftUI
import UIKit

// MARK: - 应用信息（改名只改这里 + Info.plist 的 CFBundleDisplayName）

enum AppInfo {
    static let displayName = "琉璃"
    static let tagline = "AI 编程与对话助手"
}

// MARK: - 液态玻璃主题（Liquid Glass · 深浅色自适应）
// 对标豆包布局规范 + iOS 26 Liquid Glass：
// - iOS 26+（Xcode 26 SDK 编译）使用原生 glassEffect
// - iOS 17~25 降级为 ultraThinMaterial + 渐变描边模拟
// - 全部颜色跟随系统深浅色模式

extension Color {
    // MARK: 品牌色（不随模式改变色相，透明度自适应）

    static let liuliTeal = Color(red: 0.20, green: 0.72, blue: 0.78)
    static let liuliIndigo = Color(red: 0.38, green: 0.34, blue: 0.90)
    static let liuliViolet = Color(red: 0.62, green: 0.36, blue: 0.94)
    static let liuliAccent = Color(red: 0.35, green: 0.78, blue: 0.86)

    /// 用户气泡 / 发送按钮渐变（豆包式品牌蓝）
    static var brandGradient: LinearGradient {
        LinearGradient(colors: [liuliTeal, liuliIndigo],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    // MARK: 语义色（深浅色自适应）

    private static func dyn(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark ? dark : light
        })
    }

    /// 页面背景（浅：近白冷灰 / 深：近黑）
    static let appBackground = dyn(
        light: UIColor(red: 0.965, green: 0.970, blue: 0.980, alpha: 1),
        dark: UIColor(red: 0.043, green: 0.055, blue: 0.11, alpha: 1))

    /// 顶部/底部栏玻璃底色调
    static let barTint = dyn(
        light: UIColor(red: 1, green: 1, blue: 1, alpha: 0.72),
        dark: UIColor(red: 0.06, green: 0.07, blue: 0.13, alpha: 0.72))

    /// 卡片 / 玻璃层
    static let surfaceCard = dyn(
        light: UIColor(red: 1, green: 1, blue: 1, alpha: 0.82),
        dark: UIColor(red: 1, green: 1, blue: 1, alpha: 0.06))

    /// 玻璃描边
    static var glassStroke: Color {
        Color.uiAdaptive(light: Color.black.opacity(0.08), dark: Color.white.opacity(0.16))
    }

    /// 主文本（浅：近黑 / 深：近白）
    static let textPrimary = dyn(
        light: UIColor(red: 0.11, green: 0.12, blue: 0.14, alpha: 1),
        dark: UIColor(red: 0.95, green: 0.96, blue: 0.98, alpha: 1))

    /// 次级文本
    static let textSecondary = dyn(
        light: UIColor(red: 0.36, green: 0.38, blue: 0.42, alpha: 1),
        dark: UIColor(red: 0.72, green: 0.74, blue: 0.80, alpha: 1))

    /// 弱化文本 / 占位
    static let textTertiary = dyn(
        light: UIColor(red: 0.55, green: 0.57, blue: 0.62, alpha: 1),
        dark: UIColor(red: 0.48, green: 0.50, blue: 0.56, alpha: 1))

    /// 分隔线
    static let separator = dyn(
        light: UIColor(red: 0, green: 0, blue: 0, alpha: 0.08),
        dark: UIColor(red: 1, green: 1, blue: 1, alpha: 0.10))

    /// 工具调用底色
    static let toolChipBG = dyn(
        light: UIColor(red: 0.13, green: 0.45, blue: 0.50, alpha: 0.08),
        dark: UIColor(red: 0.13, green: 0.55, blue: 0.62, alpha: 0.10))

    /// 错误色
    static let errorText = dyn(
        light: UIColor(red: 0.80, green: 0.22, blue: 0.18, alpha: 1),
        dark: UIColor(red: 1.0, green: 0.52, blue: 0.46, alpha: 1))

    /// 用户气泡内文字（始终白色，气泡为品牌渐变）
    static let onBrand = Color.white

    /// 代码块底色
    static let codeBG = dyn(
        light: UIColor(red: 0.95, green: 0.96, blue: 0.97, alpha: 1),
        dark: UIColor(red: 0.10, green: 0.11, blue: 0.15, alpha: 1))

    // 旧 API 兼容（渐进迁移期保持可编译）
    static let liuliTextPrimary = Color.textPrimary
    static let liuliTextSecondary = Color.textSecondary
    static let liuliTextTertiary = Color.textTertiary

    /// 任意 Color 的深浅适配包装
    static func uiAdaptive(light: Color, dark: Color) -> Color {
        let uiLight = UIColor(light)
        let uiDark = UIColor(dark)
        return Color(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark ? uiDark : uiLight
        })
    }
}

// MARK: - 液态玻璃修饰器（iOS 26 原生 / 旧版降级）

struct LiquidGlassStyle: ViewModifier {
    var cornerRadius: CGFloat = 18
    var padding: CGFloat = 0
    /// iOS 26 原生玻璃 interactive（点击有液态反馈）
    var interactive = false

    func body(content: Content) -> some View {
        let shaped = content
            .padding(padding)

        // Xcode 26（Swift 6.2 + iOS 26 SDK）使用原生 Liquid Glass；否则降级
        #if compiler(>=6.2) && canImport(UIKit)
        if #available(iOS 26.0, *) {
            modified26(shaped)
        } else {
            legacy(shaped)
        }
        #else
        legacy(shaped)
        #endif
    }

    #if compiler(>=6.2) && canImport(UIKit)
    @ViewBuilder
    private func modified26(_ content: some View) -> some View {
        if interactive {
            content
                .glassEffect(.regular.interactive(),
                             in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            content
                .glassEffect(.regular,
                             in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }
    #endif

    /// iOS 17~25 降级：磨砂 + 高光渐变描边
    private func legacy(_ content: some View) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.35),
                                Color.white.opacity(0.06),
                                Color.white.opacity(0.0),
                                Color.white.opacity(0.14)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
    }
}

extension View {
    /// 液态玻璃容器（iOS 26 原生 glassEffect，旧系统降级磨砂）
    func liquidGlass(cornerRadius: CGFloat = 18, padding: CGFloat = 0, interactive: Bool = false) -> some View {
        modifier(LiquidGlassStyle(cornerRadius: cornerRadius, padding: padding, interactive: interactive))
    }
}

// MARK: - 全局弥散背景（深浅色两套色斑）

struct LiquidGlassBackground: View {
    @State private var animate = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            let blobOpacity: Double = scheme == .dark ? 1.0 : 0.16

            Circle()
                .fill(Color.liuliTeal)
                .frame(width: 340, height: 340)
                .blur(radius: 90)
                .opacity(0.30 * blobOpacity)
                .offset(x: animate ? -70 : -110, y: animate ? -140 : -90)

            Circle()
                .fill(Color.liuliViolet)
                .frame(width: 380, height: 380)
                .blur(radius: 100)
                .opacity(0.26 * blobOpacity)
                .offset(x: animate ? 150 : 110, y: animate ? 260 : 320)

            Circle()
                .fill(Color.liuliIndigo)
                .frame(width: 300, height: 300)
                .blur(radius: 90)
                .opacity(0.22 * blobOpacity)
                .offset(x: animate ? 40 : -30, y: animate ? 420 : 470)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 9).repeatForever(autoreverses: true)) {
                animate = true
            }
        }
    }
}

// MARK: - 品牌胶囊按钮（豆包式）

struct BrandCapsuleButton: View {
    let title: String
    var systemImage: String? = nil
    var prominent = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 13, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 9)
            .foregroundStyle(prominent ? Color.onBrand : Color.textPrimary)
            .background(
                Capsule().fill(
                    prominent
                        ? AnyShapeStyle(Color.brandGradient)
                        : AnyShapeStyle(.ultraThinMaterial)
                )
            )
            .overlay(
                Capsule().strokeBorder(Color.glassStroke, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 徽章

struct GlassBadge: View {
    let text: String
    var tint: Color = .liuliAccent

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .foregroundStyle(tint)
            .background(Capsule().fill(tint.opacity(0.14)))
            .overlay(Capsule().strokeBorder(tint.opacity(0.38), lineWidth: 0.8))
    }
}

// MARK: - 旧 API 兼容（渐进迁移）

extension View {
    @available(*, deprecated, renamed: "liquidGlass(cornerRadius:padding:)")
    func glassCard(cornerRadius: CGFloat = 20, padding: CGFloat = 14) -> some View {
        liquidGlass(cornerRadius: cornerRadius, padding: padding)
    }
}

struct GlassCapsuleButton: View {
    let title: String
    var systemImage: String? = nil
    var prominent = false
    let action: () -> Void

    var body: some View {
        BrandCapsuleButton(title: title, systemImage: systemImage, prominent: prominent, action: action)
    }
}
