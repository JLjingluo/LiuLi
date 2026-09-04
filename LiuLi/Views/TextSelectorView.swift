import SwiftUI

// MARK: - 全屏文本选择页（对标豆包「选择文本」）
// 长按消息 → 选择文本 → 进入本页，可自由拖选、复制

struct TextSelectorView: View {
    let title: String
    let text: String

    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        NavigationStack {
            ScrollView {
                // 只读 TextEditor：系统级长按拖选 + 放大镜 + 拷贝菜单
                TextEditor(text: .constant(text))
                    .font(.system(size: 15))
                    .foregroundStyle(Color.textPrimary)
                    .scrollContentBackground(.hidden)
                    .background(Color.appBackground)
                    .frame(minHeight: 400)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .textSelection(.enabled)
            }
            .background(Color.appBackground)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("完成") { dismiss() }
                        .foregroundStyle(Color.liuliAccent)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        UIPasteboard.general.string = text
                        withAnimation { copied = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                            withAnimation { copied = false }
                        }
                    } label: {
                        Label(copied ? "已复制" : "复制全部", systemImage: copied ? "checkmark" : "doc.on.doc")
                            .foregroundStyle(Color.liuliAccent)
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if copied {
                    Label("已复制到剪贴板", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.onBrand)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(Color.brandGradient))
                        .padding(.bottom, 24)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
    }
}
