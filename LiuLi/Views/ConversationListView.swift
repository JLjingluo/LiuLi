import SwiftUI

// MARK: - 会话列表（抽屉）

struct ConversationListView: View {
    @EnvironmentObject private var store: ConversationStore
    @EnvironmentObject private var router: AppRouter
    @Environment(\.dismiss) private var dismiss

    @State private var newChatMode: ChatMode = .lite

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        store.create(mode: .lite)
                        dismiss()
                    } label: {
                        Label("新建省流对话", systemImage: "bolt.fill")
                            .foregroundStyle(Color.liuliTeal)
                    }
                    Button {
                        store.create(mode: .deep)
                        dismiss()
                    } label: {
                        Label("新建深度对话", systemImage: "brain.filled.head.profile")
                            .foregroundStyle(Color.liuliViolet)
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
                        .foregroundStyle(Color.liuliAccent)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func row(_ conv: Conversation) -> some View {
        Button {
            store.select(conv.id)
            dismiss()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: conv.mode == .deep ? "brain.filled.head.profile" : "bolt.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(conv.mode == .deep ? Color.liuliViolet : Color.liuliTeal)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 3) {
                    Text(conv.title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                    Text("\(conv.messages.count) 条消息 · \(conv.updatedAt.formatted(.relative(presentation: .named)))")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.liuliTextTertiary)
                }

                Spacer()

                if conv.id == store.currentID {
                    GlassBadge(text: "当前", tint: .liuliAccent)
                }
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
