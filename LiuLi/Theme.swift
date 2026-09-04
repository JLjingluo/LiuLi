import SwiftUI
import UIKit

// MARK: - 应用信息（改名只改这里 + Info.plist 的 CFBundleDisplayName）

enum AppInfo {
    static let displayName = "Nexus"
    static let tagline = "AI 编程与对话助手"
}

// MARK: - 主题（对标 DeepSeek：浅色极简 · 单一品牌蓝 · 液态玻璃）
//
// 设计语言：
// 1. 全 App 只有一个强调色：品牌蓝 #4D6BFE（无渐变、无紫色、无青色）
// 2. 背景：近白微灰 + 极淡品牌色弥散（供液态玻璃折射出层次）
// 3. 消息：用户浅灰蓝气泡（深色文字，DeepSeek 式）/ AI 无气泡直接排版
// 4. 悬浮层（顶栏 / 输入栏 / Tab 栏 / 发送键）：液态玻璃
// 5. 图标：细线系统符号，小号、灰色为主，品牌蓝点缀

extension Color {

    // MARK: 品牌色（唯一强调色）

    /// DeepSeek 式品牌蓝 #4D6BFE
    static let brand = Color(red: 0.302, green: 0.420, blue: 0.996)

    /// 品牌蓝淡底（选中态 / 提示底色）
    static var brandSoft: Color {
        uiAdaptive(light: Color(red: 0.930, green: 0.947, blue: 0.998),
                   dark: Color(red: 0.180, green: 0.220, blue: 0.360))
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

    /// 玻璃描边
    static var glassStroke: Color {
        uiAdaptive(light: Color.black.opacity(0.07), dark: Color.white.opacity(0.14))
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

    /// 用户气泡（浅灰蓝，DeepSeek 式深字气泡，非彩色）
    static let userBubble = dyn(
        light: UIColor(red: 0.930, green: 0.942, blue: 0.965, alpha: 1),
        dark: UIColor(red: 0.13, green: 0.14, blue: 0.18, alpha: 1))

    /// 用户气泡内文字（深色）
    static let onUserBubble = dyn(
        light: UIColor(red: 0.11, green: 0.12, blue: 0.15, alpha: 1),
        dark: UIColor(red: 0.94, green: 0.95, blue: 0.97, alpha: 1))

    /// 工具调用底色（品牌蓝淡底）
    static let toolChipBG = dyn(
        light: UIColor(red: 0.302, green: 0.420, blue: 0.996, alpha: 0.07),
        dark: UIColor(red: 0.302, green: 0.420, blue: 0.996, alpha: 0.14))

    /// 错误色
    static let errorText = dyn(
        light: UIColor(red: 0.78, green: 0.22, blue: 0.18, alpha: 1),
        dark: UIColor(red: 1.0, green: 0.52, blue: 0.46, alpha: 1))

    /// 代码块底色
    static let codeBG = dyn(
        light: UIColor(red: 0.956, green: 0.961, blue: 0.966, alpha: 1),
        dark: UIColor(red: 0.09, green: 0.10, blue: 0.13, alpha: 1))

    /// 品牌色上的文字（始终白色）
    static let onBrand = Color.white

    // MARK: 旧色名兼容（全部映射为品牌蓝，全 App 单一强调色）

    static let liuliAccent = Color.brand
    static let liuliTeal = Color.brand
    static let liuliIndigo = Color.brand
    static let liuliViolet = Color.brand
    static let liuliTextPrimary = Color.textPrimary
    static let liuliTextSecondary = Color.textSecondary
    static let liuliTextTertiary = Color.textTertiary

    /// 旧渐变（保留 API，实际为纯品牌蓝）
    static var brandGradient: LinearGradient {
        LinearGradient(colors: [Color.brand, Color.brand],
                       startPoint: .top, endPoint: .bottom)
    }

    /// 任意 Color 的深浅适配包装
    static func uiAdaptive(light: Color, dark: Color) -> Color {
        let uiLight = UIColor(light)
        let uiDark = UIColor(dark)
        return Color(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark ? uiDark : uiLight
        })
    }
}

// MARK: - 液态玻璃（Liquid Glass）
//
// iOS 26+：原生 glassEffect（真·液态玻璃：实时折射、高光、形变融合）
// iOS 17~25：四层视觉模拟——
//   ① 材质模糊（玻璃透光）② 镜面光泽渐变（顶部高光→透明→底部反光）
//   ③ 边缘折射描边（左上亮→右下暗）④ 柔和投影（悬浮感）

struct LiquidGlassStyle: ViewModifier {
    var cornerRadius: CGFloat = 18
    var padding: CGFloat = 0
    /// iOS 26 原生玻璃 interactive（点击有液态融合反馈）
    var interactive = false

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
        content
            .background(
                ZStack {
                    // ① 材质模糊（透光磨砂）
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)
                    // ② 镜面光泽（顶部高光 → 透明 → 底部反光，玻璃折射感）
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                stops: [
                                    .init(color: .white.opacity(0.50), location: 0.00),
                                    .init(color: .white.opacity(0.10), location: 0.20),
                                    .init(color: .white.opacity(0.00), location: 0.50),
                                    .init(color: .white.opacity(0.14), location: 1.00)
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
                                .init(color: .white.opacity(0.80), location: 0.00),
                                .init(color: .white.opacity(0.12), location: 0.45),
                                .init(color: .white.opacity(0.38), location: 1.00)
                            ],
                            startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 1)
            )
            // ④ 柔和投影（玻璃悬浮感）
            .shadow(color: Color.black.opacity(0.05), radius: 8, y: 4)
    }
}

extension View {
    /// 液态玻璃容器（iOS 26 原生 glassEffect，旧系统四层模拟）
    func liquidGlass(cornerRadius: CGFloat = 18, padding: CGFloat = 0, interactive: Bool = false) -> some View {
        modifier(LiquidGlassStyle(cornerRadius: cornerRadius, padding: padding, interactive: interactive))
    }

    @available(*, deprecated, renamed: "liquidGlass(cornerRadius:padding:)")
    func glassCard(cornerRadius: CGFloat = 20, padding: CGFloat = 14) -> some View {
        liquidGlass(cornerRadius: cornerRadius, padding: padding)
    }
}

// MARK: - 全局弥散背景（极淡品牌色斑，为液态玻璃提供折射内容）

struct LiquidGlassBackground: View {
    @State private var animate = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            // 极淡品牌蓝弥散：浅色下近隐形，玻璃滑过时透出流动色
            Circle()
                .fill(Color.brand)
                .frame(width: 320, height: 320)
                .blur(radius: 110)
                .opacity(scheme == .dark ? 0.15 : 0.06)
                .offset(x: animate ? -60 : -100, y: animate ? -170 : -130)

            Circle()
                .fill(Color.brand)
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

// MARK: - 品牌胶囊按钮（保留 API，实际为纯品牌蓝实心 / 玻璃空心）

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
                Capsule().fill(prominent ? AnyShapeStyle(Color.brand) : AnyShapeStyle(Color.surfaceCard))
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
