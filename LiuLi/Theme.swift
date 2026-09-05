import SwiftUI
import UIKit

// MARK: - 应用信息（改名只改这里 + Info.plist 的 CFBundleDisplayName）

enum AppInfo {
    static let displayName = "Nexus"
    static let tagline = "AI 编程与对话助手"
}

// MARK: - 多主题系统 v2（液态玻璃 · 8 套配色）
//
// 设计原则（对标 DeepSeek 舒适感 + iOS 26 液态玻璃语言）：
// 1. 全 App 单一强调色：主题色（8 套，即时切换）
// 2. 背景：近白微灰 + 主题色弥散（为玻璃提供折射内容）
// 3. 消息：用户玻璃气泡（品牌色微染）/ AI 无气泡直接排版
// 4. 悬浮层（顶栏/输入栏/回底箭头/卡片）：液态玻璃四层模拟
// 5. 玻璃强度三档（弱/标准/强），全局即时生效

/// 一套主题配色（强调色 + 背景弥散斑）
struct ThemePalette: Identifiable, Equatable {
    let id: String
    let name: String
    /// 唯一强调色（按钮 / 图标 / 高亮）
    let brand: Color
    /// 品牌色的浅色端（渐变用）
    let brandLight: Color
    /// 背景弥散斑 1（大）
    let blobA: Color
    /// 背景弥散斑 2（小）
    let blobB: Color

    static func == (lhs: ThemePalette, rhs: ThemePalette) -> Bool { lhs.id == rhs.id }
}

extension ThemePalette {

    /// 全部内置主题（设置页色板顺序）
    static let all: [ThemePalette] = [
        ThemePalette(id: "nexus", name: "晴空蓝",
                     brand: Color(red: 0.302, green: 0.420, blue: 0.996),
                     brandLight: Color(red: 0.490, green: 0.706, blue: 1.000),
                     blobA: Color(red: 0.302, green: 0.420, blue: 0.996),
                     blobB: Color(red: 0.490, green: 0.706, blue: 1.000)),
        ThemePalette(id: "indigo", name: "靛夜紫",
                     brand: Color(red: 0.431, green: 0.353, blue: 0.902),
                     brandLight: Color(red: 0.596, green: 0.545, blue: 0.980),
                     blobA: Color(red: 0.431, green: 0.353, blue: 0.902),
                     blobB: Color(red: 0.596, green: 0.545, blue: 0.980)),
        ThemePalette(id: "mint", name: "青竹碧",
                     brand: Color(red: 0.055, green: 0.639, blue: 0.467),
                     brandLight: Color(red: 0.208, green: 0.796, blue: 0.690),
                     blobA: Color(red: 0.055, green: 0.639, blue: 0.467),
                     blobB: Color(red: 0.208, green: 0.796, blue: 0.690)),
        ThemePalette(id: "coral", name: "落日橙",
                     brand: Color(red: 0.976, green: 0.420, blue: 0.290),
                     brandLight: Color(red: 1.000, green: 0.651, blue: 0.420),
                     blobA: Color(red: 0.976, green: 0.420, blue: 0.290),
                     blobB: Color(red: 1.000, green: 0.651, blue: 0.420)),
        ThemePalette(id: "sakura", name: "樱花粉",
                     brand: Color(red: 0.906, green: 0.357, blue: 0.573),
                     brandLight: Color(red: 1.000, green: 0.620, blue: 0.733),
                     blobA: Color(red: 0.906, green: 0.357, blue: 0.573),
                     blobB: Color(red: 1.000, green: 0.620, blue: 0.733)),
        ThemePalette(id: "gold", name: "琥珀金",
                     brand: Color(red: 0.847, green: 0.596, blue: 0.176),
                     brandLight: Color(red: 0.976, green: 0.812, blue: 0.522),
                     blobA: Color(red: 0.847, green: 0.596, blue: 0.176),
                     blobB: Color(red: 0.976, green: 0.812, blue: 0.522)),
        ThemePalette(id: "graphite", name: "静谧墨",
                     brand: Color(red: 0.235, green: 0.251, blue: 0.286),
                     brandLight: Color(red: 0.510, green: 0.537, blue: 0.580),
                     blobA: Color(red: 0.235, green: 0.251, blue: 0.286),
                     blobB: Color(red: 0.510, green: 0.537, blue: 0.580)),
        ThemePalette(id: "ocean", name: "深海青",
                     brand: Color(red: 0.000, green: 0.476, blue: 0.616),
                     brandLight: Color(red: 0.220, green: 0.710, blue: 0.870),
                     blobA: Color(red: 0.000, green: 0.476, blue: 0.616),
                     blobB: Color(red: 0.220, green: 0.710, blue: 0.870))
    ]

    /// 按 id 取主题（未知 id 回退默认）
    static func palette(for id: String) -> ThemePalette {
        all.first { $0.id == id } ?? all[0]
    }
}

/// 当前主题的全局持有者（线程安全；AppSettings 变更时写入，Color 扩展读取）
enum CurrentTheme {
    private static let lock = NSLock()
    private static var _palette: ThemePalette = .palette(for: "nexus")
    /// 玻璃强度（0=弱 / 1=标准 / 2=强），影响玻璃高光与描边的不透明度倍率
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

    // MARK: 主题色（唯一强调色，随主题即时切换）

    /// 当前主题强调色（品牌色）
    static var brand: Color { CurrentTheme.palette.brand }

    /// 品牌渐变（品牌色 → 浅端，按钮/头像质感）
    static var brandGradient: LinearGradient {
        LinearGradient(colors: [CurrentTheme.palette.brand, CurrentTheme.palette.brandLight],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// 主题色淡底（选中态 / 提示底色）
    static var brandSoft: Color {
        uiAdaptive(light: CurrentTheme.palette.brand.opacity(0.11),
                   dark: CurrentTheme.palette.brand.opacity(0.24))
    }

    // MARK: 语义色（浅色为默认，深色完整适配）

    private static func dyn(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark ? dark : light
        })
    }

    /// 页面背景（浅：#F7F8FA 近白微灰 / 深：近黑蓝）
    static let appBackground = dyn(
        light: UIColor(red: 0.969, green: 0.973, blue: 0.980, alpha: 1),
        dark: UIColor(red: 0.047, green: 0.055, blue: 0.075, alpha: 1))

    /// 玻璃卡片底
    static let surfaceCard = dyn(
        light: UIColor(red: 1, green: 1, blue: 1, alpha: 0.80),
        dark: UIColor(red: 1, green: 1, blue: 1, alpha: 0.07))

    /// 玻璃描边（随玻璃强度缩放）
    static var glassStroke: Color {
        let b = CurrentTheme.glassBoost
        return uiAdaptive(light: Color.black.opacity(0.07 * b),
                          dark: Color.white.opacity(0.14 * b))
    }

    /// 主文本（浅：近黑 / 深：近白）
    static let textPrimary = dyn(
        light: UIColor(red: 0.11, green: 0.12, blue: 0.15, alpha: 1),
        dark: UIColor(red: 0.94, green: 0.95, blue: 0.97, alpha: 1))

    /// 次级文本
    static let textSecondary = dyn(
        light: UIColor(red: 0.37, green: 0.40, blue: 0.45, alpha: 1),
        dark: UIColor(red: 0.70, green: 0.73, blue: 0.79, alpha: 1))

    /// 弱化文本 / 占位
    static let textTertiary = dyn(
        light: UIColor(red: 0.58, green: 0.61, blue: 0.66, alpha: 1),
        dark: UIColor(red: 0.47, green: 0.50, blue: 0.56, alpha: 1))

    /// 分隔线
    static let separator = dyn(
        light: UIColor(red: 0, green: 0, blue: 0, alpha: 0.06),
        dark: UIColor(red: 1, green: 1, blue: 1, alpha: 0.08))

    /// 用户气泡（玻璃风：品牌色微染玻璃；纯色风：浅灰蓝）
    static var userBubbleFill: Color {
        uiAdaptive(light: CurrentTheme.palette.brand.opacity(0.10),
                   dark: CurrentTheme.palette.brand.opacity(0.18))
    }

    /// 用户气泡纯色风（浅灰蓝，DeepSeek 式）
    static let userBubbleSolid = dyn(
        light: UIColor(red: 0.930, green: 0.942, blue: 0.965, alpha: 1),
        dark: UIColor(red: 0.13, green: 0.14, blue: 0.18, alpha: 1))

    /// 用户气泡内文字
    static let onUserBubble = dyn(
        light: UIColor(red: 0.11, green: 0.12, blue: 0.15, alpha: 1),
        dark: UIColor(red: 0.94, green: 0.95, blue: 0.97, alpha: 1))

    /// 工具调用底色（主题色淡底）
    static var toolChipBG: Color {
        uiAdaptive(light: CurrentTheme.palette.brand.opacity(0.07),
                   dark: CurrentTheme.palette.brand.opacity(0.14))
    }

    /// 错误色
    static let errorText = dyn(
        light: UIColor(red: 0.78, green: 0.22, blue: 0.18, alpha: 1),
        dark: UIColor(red: 1.0, green: 0.52, blue: 0.46, alpha: 1))

    /// 主题色上的文字（始终白色）
    static let onBrand = Color.white

    // MARK: 旧色名兼容（映射到当前主题色，全 App 单一强调色）

    static var liuliAccent: Color { Color.brand }
    static var liuliTeal: Color { Color.brand }
    static var liuliIndigo: Color { Color.brand }
    static var liuliViolet: Color { Color.brand }
    static var liuliTextPrimary: Color { Color.textPrimary }
    static var liuliTextSecondary: Color { Color.textSecondary }
    static var liuliTextTertiary: Color { Color.textTertiary }

    /// 任意 Color 的深浅适配包装
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
    /// 轻点反馈（按钮按下 / 切换）
    static func tap() {
        guard AppSettings.shared.hapticsEnabled else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    /// 成功反馈（发送 / 保存完成）
    static func success() {
        guard AppSettings.shared.hapticsEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
    /// 警告反馈（出错 / 中断）
    static func warning() {
        guard AppSettings.shared.hapticsEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
}

// MARK: - 按压反馈按钮样式（按下缩放 + 变淡）

struct PressableButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.90

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.75), value: configuration.isPressed)
    }
}

// MARK: - 液态玻璃系统 v2
//
// iOS 26+：原生 glassEffect（实时折射、高光、形变融合；interactive 提供点击液态反馈）
// iOS 17~25：四层视觉模拟（借鉴 FabBar / LiquidGlassReference 社区方案）——
//   ① 材质模糊（玻璃透光）        ultraThinMaterial
//   ② 镜面光泽渐变                顶部高光 → 透明 → 底部反光
//   ③ 边缘折射描边                左上亮 → 右下暗（色散感）
//   ④ 柔和投影                    悬浮感
// 玻璃强度（弱/标准/强）全局缩放 ②③ 层的不透明度。

struct LiquidGlassStyle: ViewModifier {
    var cornerRadius: CGFloat = 18
    var padding: CGFloat = 0
    /// iOS 26 原生玻璃 interactive（点击有液态融合反馈）
    var interactive = false
    /// 品牌色微染（输入胶囊等主交互面）
    var tinted = false

    func body(content: Content) -> some View {
        let shaped = content.padding(padding)

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
    @available(iOS 26.0, *)
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

    /// iOS 17~25 降级：四层液态玻璃模拟
    private func legacy(_ content: some View) -> some View {
        let boost = CurrentTheme.glassBoost
        return content
            .background(
                ZStack {
                    // ① 材质模糊（透光磨砂）
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)
                    // ①b 品牌微染（可选，主交互面用）
                    if tinted {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(Color.brand.opacity(0.05 * boost))
                    }
                    // ② 镜面光泽（顶部高光 → 透明 → 底部反光）
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(
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
            // ③ 边缘折射描边（左上亮 → 右下暗 → 反光）
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            stops: [
                                .init(color: .white.opacity(0.80 * boost), location: 0.00),
                                .init(color: .white.opacity(0.12 * boost), location: 0.45),
                                .init(color: .white.opacity(0.38 * boost), location: 1.00)
                            ],
                            startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 1)
            )
            // ④ 柔和投影（玻璃悬浮感）
            .shadow(color: Color.black.opacity(0.05 * boost), radius: 8, y: 4)
    }
}

extension View {
    /// 液态玻璃容器（iOS 26 原生 glassEffect，旧系统四层模拟）
    func liquidGlass(cornerRadius: CGFloat = 18, padding: CGFloat = 0,
                     interactive: Bool = false, tinted: Bool = false) -> some View {
        modifier(LiquidGlassStyle(cornerRadius: cornerRadius, padding: padding,
                                  interactive: interactive, tinted: tinted))
    }

    @available(*, deprecated, renamed: "liquidGlass(cornerRadius:padding:)")
    func glassCard(cornerRadius: CGFloat = 20, padding: CGFloat = 14) -> some View {
        liquidGlass(cornerRadius: cornerRadius, padding: padding)
    }
}

// MARK: - 全局弥散背景（主题色弥散斑，为液态玻璃提供折射内容）

struct LiquidGlassBackground: View {
    @State private var animate = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let palette = CurrentTheme.palette
        ZStack {
            Color.appBackground.ignoresSafeArea()

            // 主题色弥散斑 1：浅色下近隐形，玻璃滑过时透出流动色
            Circle()
                .fill(palette.blobA)
                .frame(width: 320, height: 320)
                .blur(radius: 110)
                .opacity(scheme == .dark ? 0.15 : 0.06)
                .offset(x: animate ? -60 : -100, y: animate ? -170 : -130)

            // 主题色弥散斑 2：右下角呼应
            Circle()
                .fill(palette.blobB)
                .frame(width: 260, height: 260)
                .blur(radius: 100)
                .opacity(scheme == .dark ? 0.10 : 0.04)
                .offset(x: animate ? 150 : 110, y: animate ? 330 : 390)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 10).repeatForever(autoreverses: true)) {
                animate = true
            }
        }
    }
}

// MARK: - 徽章（极简：淡底色文字胶囊）

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

// MARK: - 品牌胶囊按钮

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
                        .font(.system(size: 13, weight: .medium))
                }
                Text(title)
                    .font(.system(size: 14, weight: .medium))
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 9)
            .foregroundStyle(prominent ? Color.onBrand : Color.textPrimary)
            .background(
                Capsule().fill(prominent ? AnyShapeStyle(Color.brandGradient) : AnyShapeStyle(Color.surfaceCard))
            )
            .overlay(Capsule().strokeBorder(Color.glassStroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
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
