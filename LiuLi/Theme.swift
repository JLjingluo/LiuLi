import SwiftUI

// MARK: - 液态玻璃主题（Liquid Glass）
// 深色弥散背景 + ultraThinMaterial 卡片 + 渐变描边，iOS 17 原生实现，无第三方依赖。

extension Color {
    /// 主强调色：青→靛渐变的代表色
    static let liuliAccent = Color(red: 0.35, green: 0.78, blue: 0.86)
    /// 渐变起止色
    static let liuliTeal = Color(red: 0.20, green: 0.72, blue: 0.78)
    static let liuliIndigo = Color(red: 0.38, green: 0.34, blue: 0.90)
    static let liuliViolet = Color(red: 0.62, green: 0.36, blue: 0.94)
    /// 文本
    static let liuliTextPrimary = Color.white
    static let liuliTextSecondary = Color.white.opacity(0.62)
    static let liuliTextTertiary = Color.white.opacity(0.38)
}

// MARK: 玻璃卡片修饰器

struct GlassCardStyle: ViewModifier {
    var cornerRadius: CGFloat = 20
    var padding: CGFloat = 14

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                // 玻璃底
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .environment(\.colorScheme, .dark)
            )
            .overlay(
                // 高光描边：左上亮、右下暗，模拟玻璃边缘折射
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.38),
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
            .shadow(color: Color.black.opacity(0.28), radius: 14, y: 6)
    }
}

extension View {
    /// 液态玻璃卡片
    func glassCard(cornerRadius: CGFloat = 20, padding: CGFloat = 14) -> some View {
        modifier(GlassCardStyle(cornerRadius: cornerRadius, padding: padding))
    }
}

// MARK: 全局弥散背景

struct LiquidGlassBackground: View {
    @State private var animate = false

    var body: some View {
        ZStack {
            Color(red: 0.043, green: 0.055, blue: 0.11)
                .ignoresSafeArea()

            // 弥散色斑 1：青
            Circle()
                .fill(Color.liuliTeal)
                .frame(width: 340, height: 340)
                .blur(radius: 90)
                .opacity(0.34)
                .offset(x: animate ? -70 : -110, y: animate ? -140 : -90)
            // 弥散色斑 2：紫
            Circle()
                .fill(Color.liuliViolet)
                .frame(width: 380, height: 380)
                .blur(radius: 100)
                .opacity(0.30)
                .offset(x: animate ? 150 : 110, y: animate ? 260 : 320)
            // 弥散色斑 3：靛
            Circle()
                .fill(Color.liuliIndigo)
                .frame(width: 300, height: 300)
                .blur(radius: 90)
                .opacity(0.26)
                .offset(x: animate ? 40 : -30, y: animate ? 420 : 470)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 9).repeatForever(autoreverses: true)) {
                animate = true
            }
        }
    }
}

// MARK: 胶囊按钮

struct GlassCapsuleButton: View {
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
            .foregroundStyle(prominent ? Color.white : Color.liuliTextPrimary)
            .background(
                Capsule()
                    .fill(
                        prominent
                            ? AnyShapeStyle(LinearGradient(
                                colors: [Color.liuliTeal, Color.liuliIndigo],
                                startPoint: .topLeading, endPoint: .bottomTrailing))
                            : AnyShapeStyle(.ultraThinMaterial)
                    )
            )
            .overlay(
                Capsule().strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: 徽章

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
