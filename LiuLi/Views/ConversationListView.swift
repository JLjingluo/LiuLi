import SwiftUI

// MARK: - 会话列表（抽屉，DeepSeek 式极简）

struct ConversationListView: View {
    @EnvironmentObject private var store: ConversationStore
    @EnvironmentObject private var router: AppRouter
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        store.create(mode: .lite)
                        dismiss()
                    } label: {
                        Label("新对话 · 快速模式", systemImage: "plus")
                            .foregroundStyle(Color.brand)
                    }
                    Button {
                        store.create(mode: .deep)
                        dismiss()
                    } label: {
                        Label("新对话 · 深度模式", systemImage: "plus")
                            .foregroundStyle(Color.brand)
                    }
                }
                .listRowBackground(Color.surfaceCard)

                Section("历史会话") {
                    ForEach(store.conversations) { conv in
                        row(conv)
                    }
                    .onDelete(perform: delete)
                }
                .listRowBackground(Color.surfaceCard)
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.appBackground)
            .navigationTitle("对话")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                        .foregroundStyle(Color.brand)
                }
            }
        }
    }

    /// 纯文字行（DeepSeek 式：无图标，标题 + 消息数/时间）
    private func row(_ conv: Conversation) -> some View {
        Button {
            store.select(conv.id)
            dismiss()
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    if conv.id == store.currentID {
                        Circle()
                            .fill(Color.brand)
                            .frame(width: 5, height: 5)
                    }
                    Text(conv.title)
                        .font(.system(size: 14.5))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                }
                Text("\(conv.messages.count) 条消息 · \(conv.updatedAt.formatted(.relative(presentation: .named)))")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .buttonStyle(.plain)
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            store.delete(store.conversations[index].id)
        }
    }
}
