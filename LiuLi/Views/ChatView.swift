import SwiftUI
import PhotosUI

// MARK: - 聊天主界面（对标豆包布局）
// 顶部：标题居中 + 侧栏/模式切换
// 中部：消息流（用户右气泡 / AI 左排版）
// 底部：液态玻璃输入栏（+ 附件 / 文本框 / 圆形发送键）

struct ChatView: View {
    @EnvironmentObject private var store: ConversationStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var router: AppRouter
    @StateObject private var vm = ChatViewModel(store: .shared, settings: .shared)

    // 输入框本地状态：发送后立即清空（豆包行为）
    @State private var inputText = ""
    @State private var showConversationList = false
    @State private var photoSelection: [PhotosPickerItem] = []
    @State private var stashedItems: [PhotosPickerItem] = []
    @State private var showVisionAlert = false
    @State private var forceVisionBypass = false
    @FocusState private var inputFocused: Bool

    /// 建议提问（豆包式空状态卡片，按当前模式给出）
    private var suggestions: [SuggestionItem] {
        store.current?.mode == .deep
        ? [
            SuggestionItem(icon: "globe", title: "写一个个人主页", subtitle: "生成 index.html 并预览"),
            SuggestionItem(icon: "doc.text", title: "读一下工作区文件", subtitle: "让 AI 列出并解读文件"),
            SuggestionItem(icon: "hammer", title: "写一个计算器", subtitle: "HTML+CSS+JS 小程序"),
        ]
        : [
            SuggestionItem(icon: "lightbulb", title: "今天适合做什么？", subtitle: "随手一问，省流回答"),
            SuggestionItem(icon: "translate", title: "帮我润色一句话", subtitle: "快速改写文本"),
            SuggestionItem(icon: "list.bullet", title: "列个周末计划", subtitle: "简洁要点式输出"),
        ]
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !settings.isConfigured {
                    notConfiguredBanner
                }
                messageList
                inputBar
            }
            .navigationTitle(store.current?.title ?? "对话")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .sheet(isPresented: $showConversationList) {
                ConversationListView()
            }
            .onChange(of: router.pendingPrompt) { _, newValue in
                if let prompt = newValue {
                    inputText = prompt
                    router.pendingPrompt = nil
                    inputFocused = true
                }
            }
        }
    }

    // MARK: 未配置提示

    private var notConfiguredBanner: some View {
        Button {
            router.selectedTab = .settings
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                Text("尚未完成 API 配置，点此前往设置")
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(Color.errorText)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(.ultraThinMaterial)
        }
        .buttonStyle(.plain)
    }

    // MARK: 消息列表

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 18) {
                    if let messages = store.current?.messages, !messages.isEmpty {
                        ForEach(messages) { message in
                            MessageBubble(
                                message: message,
                                isStreaming: vm.isStreaming && message.id == store.current?.messages.last?.id,
                                isLatestAssistant: isLatestAssistant(message),
                                onRegenerate: { vm.regenerate() }
                            )
                            .id(message.id)
                        }
                    } else {
                        emptyState
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 8)
            }
            .onChange(of: store.current?.messages.count) { _, newCount in
                if let count = newCount, count > 0,
                   let last = store.current?.messages.last {
                    withAnimation(.easeOut(duration: 0.25)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            .onChange(of: store.current?.messages.last?.text) { _, newValue in
                // 流式输出期间跟随滚动
                if vm.isStreaming, let last = store.current?.messages.last, newValue != nil {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
            .onChange(of: store.currentID) { _, _ in
                if let last = store.current?.messages.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
            .defaultScrollAnchor(.bottom)
        }
    }

    /// 最后一条 assistant 消息（含工具轮次后）才有"重新生成"
    private func isLatestAssistant(_ message: ChatMessage) -> Bool {
        guard let msgs = store.current?.messages else { return false }
        guard message.role == .assistant else { return false }
        // 找最后一条非 tool 消息；若是这条 assistant 则为最新
        for m in msgs.reversed() {
            if m.role == .tool { continue }
            return m.id == message.id && m.role == .assistant
        }
        return false
    }

    // MARK: 空状态（豆包式建议卡片）

    private var emptyState: some View {
        VStack(spacing: 18) {
            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color.brandGradient)
                        .frame(width: 64, height: 64)
                        .shadow(color: Color.liuliIndigo.opacity(0.35), radius: 18, y: 8)
                    Image(systemName: "sparkles")
                        .font(.system(size: 26, weight: .medium))
                        .foregroundStyle(Color.onBrand)
                }
                Text(AppInfo.displayName)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Color.textPrimary)
                Text(modeHintText)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.textTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 34)
            }
            .padding(.top, 48)

            VStack(spacing: 10) {
                ForEach(suggestions) { s in
                    Button {
                        inputText = s.title
                        inputFocused = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: s.icon)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(Color.liuliAccent)
                                .frame(width: 30, height: 30)
                                .background(Circle().fill(Color.liuliAccent.opacity(0.12)))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(s.title)
                                    .font(.system(size: 14.5, weight: .medium))
                                    .foregroundStyle(Color.textPrimary)
                                Text(s.subtitle)
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(Color.textTertiary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.textTertiary.opacity(0.6))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color.surfaceCard)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(Color.glassStroke, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 6)
        }
        .padding(.bottom, 16)
    }

    private var modeHintText: String {
        switch store.current?.mode {
        case .deep:
            return "深度模式 · 完整上下文，AI 可读写文件并编写小程序"
        default:
            return "省流模式 · 极简上下文，日常闲聊 Token 消耗最低"
        }
    }

    // MARK: 工具栏

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                showConversationList = true
            } label: {
                Image(systemName: "sidebar.left")
                    .foregroundStyle(Color.liuliAccent)
            }
        }

        ToolbarItem(placement: .topBarTrailing) {
            // 模式切换（省流/深度）
            Button {
                if var conv = store.current, !vm.isStreaming {
                    conv.mode = conv.mode == .lite ? .deep : .lite
                    store.update(conv)
                }
            } label: {
                GlassBadge(
                    text: store.current?.mode == .deep ? "深度" : "省流",
                    tint: store.current?.mode == .deep ? Color.liuliViolet : Color.liuliTeal
                )
            }
        }
    }

    // MARK: 输入栏（豆包式：+ 附件 | 文本框 | 发送键）

    private var inputBar: some View {
        VStack(spacing: 6) {
            // 待发送图片预览
            if !vm.pendingImages.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(vm.pendingImages) { img in
                            ZStack(alignment: .topTrailing) {
                                if let ui = img.thumbnail {
                                    Image(uiImage: ui)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 60, height: 60)
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                } else {
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.surfaceCard)
                                        .frame(width: 60, height: 60)
                                }
                                Button {
                                    vm.pendingImages.removeAll { $0.id == img.id }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 16))
                                        .foregroundStyle(.white)
                                        .shadow(radius: 3)
                                }
                                .offset(x: 5, y: -5)
                            }
                        }
                    }
                    .padding(.horizontal, 4)
                }
                .frame(height: 70)
            }

            HStack(alignment: .bottom, spacing: 10) {
                // 「+」附件菜单（豆包式）
                Menu {
                    PhotosPicker(selection: $photoSelection, maxSelectionCount: 3, matching: .images) {
                        Label("相册选图（识图）", systemImage: "photo.on.rectangle.angled")
                    }
                    .disabled(vm.isStreaming)
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(Color.liuliAccent)
                        .symbolRenderingMode(.hierarchical)
                }
                .disabled(vm.isStreaming)

                // 输入框
                TextField(vm.isStreaming ? "生成中…" : "有问题，尽管问", text: $inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...5)
                    .focused($inputFocused)
                    .font(.system(size: 15.5))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(.ultraThinMaterial)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(Color.glassStroke, lineWidth: 1)
                    )
                    .submitLabel(.send)
                    .onSubmit { performSend() }

                // 发送 / 停止
                sendButton
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
            .padding(.top, 2)

            Text("内容由 AI 生成，请注意甄别")
                .font(.system(size: 10))
                .foregroundStyle(Color.textTertiary.opacity(0.7))
                .padding(.bottom, 2)
        }
        .padding(.top, 6)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.separator).frame(height: 0.5)
        }
        .onChange(of: photoSelection) { _, items in
            loadPickedImages(items)
        }
        .alert("模型可能不支持识图", isPresented: $showVisionAlert) {
            Button("取消", role: .cancel) {
                stashedItems = []
            }
            Button("仍然添加") {
                forceVisionBypass = true
                let items = stashedItems
                stashedItems = []
                addImages(items)
            }
        } message: {
            Text(vm.visionWarning ?? "")
        }
    }

    @ViewBuilder
    private var sendButton: some View {
        if vm.isStreaming {
            Button {
                vm.stop()
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.errorText)
                        .frame(width: 34, height: 34)
                    Image(systemName: "stop.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.white)
                }
            }
            .buttonStyle(.plain)
        } else {
            Button(action: performSend) {
                ZStack {
                    Circle()
                        .fill(canSendInput ? AnyShapeStyle(Color.brandGradient) : AnyShapeStyle(Color.textTertiary.opacity(0.25)))
                        .frame(width: 34, height: 34)
                    Image(systemName: "arrow.up")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.white)
                }
            }
            .buttonStyle(.plain)
            .disabled(!canSendInput)
            .animation(.easeInOut(duration: 0.15), value: canSendInput)
        }
    }

    private var canSendInput: Bool {
        !vm.isStreaming && settings.isConfigured &&
        (!inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !vm.pendingImages.isEmpty)
    }

    /// 发送：同步本地输入到 VM → 发送 → 立即清空输入框（豆包行为）
    private func performSend() {
        guard !vm.isStreaming else { return }
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !vm.pendingImages.isEmpty else { return }
        guard settings.isConfigured else { return }

        vm.draft = inputText
        vm.send()
        // 立即清空（用户消息已同步上屏）
        inputText = ""
    }

    // MARK: 图片选择处理

    private func loadPickedImages(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        photoSelection = []
        if !vm.modelSupportsVision && !forceVisionBypass {
            stashedItems = items
            vm.visionWarning = VisionCapability.unsupportedHint(modelID: settings.model)
            showVisionAlert = true
            return
        }
        forceVisionBypass = false
        addImages(items)
    }

    private func addImages(_ items: [PhotosPickerItem]) {
        Task {
            for item in items.prefix(3) {
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let dataURL = ImageCompressor.compressToDataURL(data) else { continue }
                vm.pendingImages.append(PendingImage(dataURL: dataURL))
            }
        }
    }
}

// MARK: - 建议项模型

struct SuggestionItem: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let subtitle: String
}
