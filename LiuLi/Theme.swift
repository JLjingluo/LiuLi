import SwiftUI
import UIKit

// MARK: - 应用信息

enum AppInfo {
    static let displayName = "Nexus"
    static let version = "3.0.0"
}

// MARK: - 多主题系统 v3
//
// 设计原则（对标 DeepSeek 的干净 + iOS 26 液态玻璃语言）：
// 1. 全 App 单一强调色（8 套主题，即时切换）
// 2. 近白微灰背景 + 极淡主题色弥散（为玻璃提供折射内容，肉眼几乎不可见）
// 3. 用户消息纯色浅灰气泡（DeepSeek 式）或玻璃微染气泡（设置可切）
// 4. 悬浮层（输入胶囊 / 回底按钮 / 代码块）：液态玻璃
// 5. 玻璃强度三档（弱 / 标准 / 强），全局即时生效

struct ThemePalette: Identifiable, Equatable {
    let id: String
    let name: String
    /// 唯一强调色（按钮 / 图标 / 高亮）
    let brand: Color
    /// 品牌色浅端（渐变用）
    let brandLight: Color

    static func == (lhs: ThemePalette, rhs: ThemePalette) -> Bool { lhs.id == rhs.id }
}

extension ThemePalette {

    static let all: [ThemePalette] = [
        ThemePalette(id: "nexus", name: "晴空蓝",
                     brand: Color(red: 0.302, green: 0.420, blue: 0.996),
                     brandLight: Color(red: 0.490, green: 0.706, blue: 1.000)),
        ThemePalette(id: "indigo", name: "靛夜紫",
                     brand: Color(red: 0.431, green: 0.353, blue: 0.902),
                     brandLight: Color(red: 0.596, green: 0.545, blue: 0.980)),
        ThemePalette(id: "mint", name: "青竹碧",
                     brand: Color(red: 0.055, green: 0.639, blue: 0.467),
                     brandLight: Color(red: 0.208, green: 0.796, blue: 0.690)),
        ThemePalette(id: "coral", name: "落日橙",
                     brand: Color(red: 0.976, green: 0.420, blue: 0.290),
                     brandLight: Color(red: 1.000, green: 0.651, blue: 0.420)),
        ThemePalette(id: "sakura", name: "樱花粉",
                     brand: Color(red: 0.906, green: 0.357, blue: 0.573),
                     brandLight: Color(red: 1.000, green: 0.620, blue: 0.733)),
        ThemePalette(id: "gold", name: "琥珀金",
                     brand: Color(red: 0.847, green: 0.596, blue: 0.176),
                     brandLight: Color(red: 0.976, green: 0.812, blue: 0.522)),
        ThemePalette(id: "graphite", name: "静谧墨",
                     brand: Color(red: 0.235, green: 0.251, blue: 0.286),
                     brandLight: Color(red: 0.510, green: 0.537, blue: 0.580)),
        ThemePalette(id: "ocean", name: "深海青",
                     brand: Color(red: 0.000, green: 0.476, blue: 0.616),
                     brandLight: Color(red: 0.220, green: 0.710, blue: 0.870))
    ]

    static func palette(for id: String) -> ThemePalette {
        all.first { $0.id == id } ?? all[0]
    }
}

/// 当前主题的全局持有者（线程安全；AppSettings 变更时写入，Color 扩展读取）
enum CurrentTheme {
    private static let lock = NSLock()
    private static var _palette: ThemePalette = .palette(for: "nexus")
    /// 玻璃强度倍率（0.55 弱 / 1.0 标准 / 1.45 强）
    private static var _glassBoost: Double = 1.0

    static var palette: ThemePalette {
        get { lock.lock(); defer { lock.unlock() }; return _palette }
        set { lock.lock(); defer { lock.unlock() }; _palette = newValue }
    }

    static var glassBoost: Double {
        get { lock.lock(); defer { lock.unlock() }; return _glassBoost }
        set { lock.lock(); defer { lock.unlock() }; _glassBoost = newValue }
    }
}

extension Color {

    // MARK: 主题色

    static var brand: Color { CurrentTheme.palette.brand }

    static var brandGradient: LinearGradient {
        LinearGradient(colors: [CurrentTheme.palette.brand, CurrentTheme.palette.brandLight],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// 主题色淡底（选中态 / 提示底色）
    static var brandSoft: Color {
        uiAdaptive(light: CurrentTheme.palette.brand.opacity(0.11),
                   dark: CurrentTheme.palette.brand.opacity(0.24))
    }

    // MARK: 语义色

    private static func dyn(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark ? dark : light
        })
    }

    /// 页面背景（浅：#F7F8FA 近白微灰 / 深：近黑蓝）
    static let appBackground = dyn(
        light: UIColor(red: 0.969, green: 0.973, blue: 0.980, alpha: 1),
        dark: UIColor(red: 0.047, green: 0.055, blue: 0.075, alpha: 1))

    /// 卡片 / 浮层底
    static let surfaceCard = dyn(
        light: UIColor(red: 1, green: 1, blue: 1, alpha: 0.80),
        dark: UIColor(red: 1, green: 1, blue: 1, alpha: 0.07))

    /// 玻璃描边（随玻璃强度缩放）
    static var glassStroke: Color {
        let b = CurrentTheme.glassBoost
        return uiAdaptive(light: Color.black.opacity(0.07 * b),
                          dark: Color.white.opacity(0.14 * b))
    }

    static let textPrimary = dyn(
        light: UIColor(red: 0.11, green: 0.12, blue: 0.15, alpha: 1),
        dark: UIColor(red: 0.94, green: 0.95, blue: 0.97, alpha: 1))

    static let textSecondary = dyn(
        light: UIColor(red: 0.37, green: 0.40, blue: 0.45, alpha: 1),
        dark: UIColor(red: 0.70, green: 0.73, blue: 0.79, alpha: 1))

    static let textTertiary = dyn(
        light: UIColor(red: 0.58, green: 0.61, blue: 0.66, alpha: 1),
        dark: UIColor(red: 0.47, green: 0.50, blue: 0.56, alpha: 1))

    static let separator = dyn(
        light: UIColor(red: 0, green: 0, blue: 0, alpha: 0.06),
        dark: UIColor(red: 1, green: 1, blue: 1, alpha: 0.08))

    /// 用户气泡（玻璃风：品牌色微染）
    static var userBubbleFill: Color {
        uiAdaptive(light: CurrentTheme.palette.brand.opacity(0.10),
                   dark: CurrentTheme.palette.brand.opacity(0.18))
    }

    /// 用户气泡纯色风（DeepSeek 式浅灰蓝）
    static let userBubbleSolid = dyn(
        light: UIColor(red: 0.930, green: 0.942, blue: 0.965, alpha: 1),
        dark: UIColor(red: 0.13, green: 0.14, blue: 0.18, alpha: 1))

    static let onUserBubble = dyn(
        light: UIColor(red: 0.11, green: 0.12, blue: 0.15, alpha: 1),
        dark: UIColor(red: 0.94, green: 0.95, blue: 0.97, alpha: 1))

    /// 工具调用淡底
    static var toolChipBG: Color {
        uiAdaptive(light: CurrentTheme.palette.brand.opacity(0.07),
                   dark: CurrentTheme.palette.brand.opacity(0.14))
    }

    static let errorText = dyn(
        light: UIColor(red: 0.78, green: 0.22, blue: 0.18, alpha: 1),
        dark: UIColor(red: 1.0, green: 0.52, blue: 0.46, alpha: 1))

    static let onBrand = Color.white

    static func uiAdaptive(light: Color, dark: Color) -> Color {
        let uiLight = UIColor(light)
        let uiDark = UIColor(dark)
        return Color(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark ? uiDark : uiLight
        })
    }
}

// MARK: - 触感反馈（受设置开关控制）

@MainActor
enum Haptics {
    static func tap() {
        guard AppSettings.shared.hapticsEnabled else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    static func success() {
        guard AppSettings.shared.hapticsEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
    static func warning() {
        guard AppSettings.shared.hapticsEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
}

// MARK: - 按压反馈按钮样式

struct PressableButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.90

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.75), value: configuration.isPressed)
    }
}

// MARK: - 液态玻璃系统
//
// iOS 26+：原生 glassEffect（实时折射、高光、形变融合；interactive 提供点击液态反馈）
// iOS 17~25：四层视觉模拟——材质模糊 + 镜面光泽 + 边缘折射描边 + 柔和投影
// 玻璃强度（弱/标准/强）全局缩放光泽与描边的不透明度。

struct LiquidGlassStyle: ViewModifier {
    var cornerRadius: CGFloat = 18
    var interactive = false
    /// 品牌色微染（主交互面）
    var tinted = false

    func body(content: Content) -> some View {
        #if compiler(>=6.2) && canImport(UIKit)
        if #available(iOS 26.0, *) {
            modified26(content)
        } else {
            legacy(content)
        }
        #else
        legacy(content)
        #endif
    }

    #if compiler(>=6.2) && canImport(UIKit)
    @available(iOS 26.0, *)
    @ViewBuilder
    private func modified26(_ content: some View) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if interactive {
            content.glassEffect(.regular.interactive(), in: shape)
        } else {
            content.glassEffect(.regular, in: shape)
        }
    }
    #endif

    private func legacy(_ content: some View) -> some View {
        let boost = CurrentTheme.glassBoost
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return content
            .background(
                ZStack {
                    shape.fill(.ultraThinMaterial)
                    if tinted {
                        shape.fill(Color.brand.opacity(0.05 * boost))
                    }
                    shape.fill(
                        LinearGradient(
                            stops: [
                                .init(color: .white.opacity(0.50 * boost), location: 0.00),
                                .init(color: .white.opacity(0.10 * boost), location: 0.20),
                                .init(color: .white.opacity(0.00), location: 0.50),
                                .init(color: .white.opacity(0.14 * boost), location: 1.00)
                            ],
                            startPoint: .top, endPoint: .bottom))
                }
            )
            .overlay(
                shape.strokeBorder(
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0.80 * boost), location: 0.00),
                            .init(color: .white.opacity(0.12 * boost), location: 0.45),
                            .init(color: .white.opacity(0.38 * boost), location: 1.00)
                        ],
                        startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.05 * boost), radius: 8, y: 4)
    }
}

extension View {
    /// 液态玻璃容器（iOS 26 原生 glassEffect，旧系统四层模拟）
    func liquidGlass(cornerRadius: CGFloat = 18, interactive: Bool = false, tinted: Bool = false) -> some View {
        modifier(LiquidGlassStyle(cornerRadius: cornerRadius, interactive: interactive, tinted: tinted))
    }
}

// MARK: - 全局弥散背景（极淡主题色弥散斑，为液态玻璃提供折射内容）

struct LiquidGlassBackground: View {
    @State private var animate = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let palette = CurrentTheme.palette
        ZStack {
            Color.appBackground.ignoresSafeArea()

            Circle()
                .fill(palette.brand)
                .frame(width: 320, height: 320)
                .blur(radius: 120)
                .opacity(scheme == .dark ? 0.13 : 0.05)
                .offset(x: animate ? -60 : -100, y: animate ? -170 : -130)

            Circle()
                .fill(palette.brandLight)
                .frame(width: 260, height: 260)
                .blur(radius: 110)
                .opacity(scheme == .dark ? 0.09 : 0.035)
                .offset(x: animate ? 150 : 110, y: animate ? 330 : 390)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 12).repeatForever(autoreverses: true)) {
                animate = true
            }
        }
    }
}

// MARK: - 徽章（极简淡底胶囊）

struct GlassBadge: View {
    let text: String
    var tint: Color = .brand

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .foregroundStyle(tint)
            .background(Capsule().fill(tint.opacity(0.10)))
    }
}
