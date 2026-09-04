import SwiftUI
import PhotosUI

// MARK: - 聊天主界面（对标 DeepSeek：极简浅色）
// 顶部：侧栏入口 + 标题 + 模式胶囊
// 中部：消息流（用户右浅灰蓝气泡 / AI 左无气泡排版）
// 底部：液态玻璃输入栏（+ 附件 / 玻璃文本框 / 品牌蓝发送键）

struct ChatView: View {
    @EnvironmentObject private var store: ConversationStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var router: AppRouter
    @StateObject private var vm = ChatViewModel(store: .shared, settings: .shared)

    // 输入框本地状态：发送后立即清空
    @State private var inputText = ""
    @State private var showConversationList = false
    @State private var photoSelection: [PhotosPickerItem] = []
    @State private var stashedItems: [PhotosPickerItem] = []
    @State private var showVisionAlert = false
    @State private var forceVisionBypass = false
    @State private var optimizeError: String?
    @State private var lastScrollAt = Date.distantPast
    @FocusState private var inputFocused: Bool
    @Environment(\.scenePhase) private var scenePhase

    /// 建议提问（DeepSeek 式简单文字胶囊，按模式给出）
    private var suggestions: [String] {
        store.current?.mode == .deep
        ? ["写一个个人主页", "读一下工作区文件", "写一个计算器"]
        : ["今天适合做什么", "帮我润色一句话", "列个周末计划"]
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !settings.isConfigured {
                    notConfiguredBanner
                }
                messageList
            }
            // 悬浮液态玻璃输入胶囊：贴住 Tab 栏形成一体（消息从玻璃下方滚过折射）
            .safeAreaInset(edge: .bottom, spacing: 0) {
                inputBar
                    .padding(.horizontal, 12)
                    .padding(.top, 6)
                    .padding(.bottom, 0)
                    .liquidGlass(cornerRadius: 24)
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
            // Siri 快捷指令：提问（自动填入输入框并聚焦）
            .onReceive(NotificationCenter.default.publisher(for: .nexusSiriPrompt)) { note in
                if let prompt = note.object as? String, !prompt.isEmpty {
                    inputText = prompt
                    inputFocused = true
                }
            }
            // Siri 快捷指令：新建对话
            .onReceive(NotificationCenter.default.publisher(for: .nexusSiriNewChat)) { _ in
                _ = store.create(mode: store.current?.mode ?? .lite)
            }
            // 回到前台：检查后台挂起导致的僵死流并自动收尾
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { vm.recoverIfNeeded() }
            }
        }
    }

    // MARK: 未配置提示

    private var notConfiguredBanner: some View {
        Button {
            router.selectedTab = .settings
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
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
                LazyVStack(spacing: 20) {
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
            // 流式跟随：由 VM 的节流 revision 信号驱动（~8 次/秒），此处再限 ~4 次/秒
            .onChange(of: vm.revision) { _, _ in
                guard vm.isStreaming, let last = store.current?.messages.last else { return }
                guard Date().timeIntervalSince(lastScrollAt) > 0.25 else { return }
                lastScrollAt = Date()
                proxy.scrollTo(last.id, anchor: .bottom)
            }
            .onChange(of: store.currentID) { _, _ in
                if let last = store.current?.messages.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.immediately)
        }
    }

    /// 最后一条 assistant 消息（含工具轮次后）才有"重新生成"
    private func isLatestAssistant(_ message: ChatMessage) -> Bool {
        guard let msgs = store.current?.messages else { return false }
        guard message.role == .assistant else { return false }
        for m in msgs.reversed() {
            if m.role == .tool { continue }
            return m.id == message.id && m.role == .assistant
        }
        return false
    }

    // MARK: 空状态（DeepSeek 式：logo + 一句问候 + 简单建议胶囊）

    private var emptyState: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 54)

            // logo：品牌蓝圆角方 + 白 N
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.brand)
                Text("N")
                    .font(.system(size: 25, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.white)
            }
            .frame(width: 52, height: 52)

            Text("你好，我是 \(AppInfo.displayName)")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.textPrimary)
                .padding(.top, 16)

            Text(modeHintText)
                .font(.system(size: 13))
                .foregroundStyle(Color.textTertiary)
                .padding(.top, 6)

            // 建议胶囊（浅灰底描边，点击填入输入框）
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(suggestions, id: \.self) { s in
                        Button {
                            inputText = s
                            inputFocused = true
                        } label: {
                            Text(s)
                                .font(.system(size: 12.5))
                                .foregroundStyle(Color.textSecondary)
                                .padding(.horizontal, 13)
                                .padding(.vertical, 7)
                                .background(Capsule().fill(Color.surfaceCard))
                                .overlay(Capsule().strokeBorder(Color.glassStroke, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 28)
            }

            Spacer(minLength: 0)
        }
    }

    private var modeHintText: String {
        switch store.current?.mode {
        case .deep:
            return "深度模式 · 完整上下文，AI 可读写文件并编写小程序"
        default:
            return "快速模式 · 极简上下文，日常闲聊花费最低"
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
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(Color.textSecondary)
            }
        }

        ToolbarItem(placement: .topBarTrailing) {
            // 模式切换（快速/深度，随时可点；下一次发送即生效）
            Button {
                guard var conv = store.current else { return }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(.easeInOut(duration: 0.18)) {
                    conv.mode = conv.mode == .lite ? .deep : .lite
                    store.update(conv)
                }
            } label: {
                HStack(spacing: 5) {
                    Circle()
                        .fill(Color.brand)
                        .frame(width: 5, height: 5)
                    Text((store.current?.mode ?? .lite).displayName)
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(Color.brand)
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.brand.opacity(0.10)))
            }
        }
    }

    // MARK: 输入栏（液态玻璃：+ 附件 | 玻璃文本框 | 品牌蓝发送键）

    private var inputBar: some View {
        VStack(spacing: 6) {
            // 提示词优化状态条（优化中 / 已优化可撤销 / 失败提示）
            if settings.promptOptimizerEnabled,
               vm.isOptimizing || vm.undoableOptimizedText != nil || optimizeError != nil {
                optimizeStatusBar
            }

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
                                        .frame(width: 58, height: 58)
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                } else {
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.surfaceCard)
                                        .frame(width: 58, height: 58)
                                }
                                Button {
                                    vm.pendingImages.removeAll { $0.id == img.id }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 15))
                                        .foregroundStyle(Color.textTertiary)
                                        .shadow(color: .white, radius: 2)
                                }
                                .offset(x: 5, y: -5)
                            }
                        }
                    }
                    .padding(.horizontal, 4)
                }
                .frame(height: 68)
            }

            HStack(alignment: .bottom, spacing: 8) {
                // 「+」附件（直接弹出相册选图；勿嵌在 Menu 里——Menu 会导致选择器弹不出、点击无响应）
                PhotosPicker(selection: $photoSelection, maxSelectionCount: 3, matching: .images) {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Color.textSecondary)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color.surfaceCard))
                        .overlay(Circle().strokeBorder(Color.glassStroke, lineWidth: 1))
                }
                .disabled(vm.isStreaming)

                // 输入框（玻璃胶囊内的实底白框 + 右下魔法棒）
                ZStack(alignment: .bottomTrailing) {
                    TextField(vm.isStreaming ? "生成中…" : "有问题，尽管问", text: $inputText, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(1...5)
                        .focused($inputFocused)
                        .font(.system(size: 15.5))
                        .foregroundStyle(Color.textPrimary)
                        .padding(.leading, 14)
                        .padding(.trailing, showOptimizeButton ? 40 : 14)
                        .padding(.vertical, 12)
                        .submitLabel(.send)
                        .onSubmit { performSend() }

                    if showOptimizeButton {
                        optimizeButton
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color.surfaceCard)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color.glassStroke, lineWidth: 1)
                )

                // 发送 / 停止
                sendButton
            }
            .padding(.horizontal, 10)
            .padding(.top, 2)

            Text("内容由 AI 生成，请注意甄别")
                .font(.system(size: 10))
                .foregroundStyle(Color.textTertiary.opacity(0.7))
                .padding(.bottom, 2)
                .padding(.top, 6)
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

    // MARK: 提示词优化（输入框右下角魔法棒）

    private var showOptimizeButton: Bool {
        settings.promptOptimizerEnabled && !vm.isStreaming &&
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @ViewBuilder
    private var optimizeButton: some View {
        Button {
            performOptimize()
        } label: {
            Group {
                if vm.isOptimizing {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.brand)
                }
            }
            .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .disabled(vm.isOptimizing)
        .padding(.trailing, 6)
        .padding(.bottom, 6)
    }

    private var optimizeStatusBar: some View {
        HStack(spacing: 8) {
            if vm.isOptimizing {
                ProgressView()
                    .controlSize(.small)
                Text("正在优化提示词…")
            } else if let err = optimizeError {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.errorText)
                Text(err)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
            } else {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.brand)
                Text("已优化提示词")
            }
            Spacer(minLength: 4)
            if !vm.isOptimizing {
                if vm.undoableOptimizedText != nil {
                    Button("撤销") {
                        vm.undoOptimize()
                        inputText = vm.draft
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.brand)
                }
                Button {
                    optimizeError = nil
                    vm.undoableOptimizedText = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.textTertiary)
                }
            }
        }
        .font(.system(size: 12))
        .foregroundStyle(Color.textSecondary)
        .padding(.horizontal, 14)
    }

    private func performOptimize() {
        guard !vm.isOptimizing else { return }
        let text = inputText
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        optimizeError = nil
        Task {
            vm.draft = text
            if let error = await vm.optimizeDraft() {
                // 未配置 / 网络失败等原因，直接在状态条展示中文提示
                optimizeError = error
            } else {
                inputText = vm.draft
            }
        }
    }

    @ViewBuilder
    private var sendButton: some View {
        if vm.isStreaming {
            // 停止（DeepSeek 式：白圆黑方块）
            Button {
                vm.stop()
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 36, height: 36)
                        .overlay(Circle().strokeBorder(Color.glassStroke, lineWidth: 1))
                    Image(systemName: "stop.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.textPrimary)
                }
            }
            .buttonStyle(.plain)
        } else {
            // 发送（品牌蓝实心圆）
            Button(action: performSend) {
                ZStack {
                    Circle()
                        .fill(canSendInput ? Color.brand : Color.textTertiary.opacity(0.22))
                        .frame(width: 36, height: 36)
                    Image(systemName: "arrow.up")
                        .font(.system(size: 15, weight: .semibold))
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

    /// 发送：同步本地输入到 VM → 发送 → 立即清空输入框
    private func performSend() {
        guard !vm.isStreaming else { return }
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !vm.pendingImages.isEmpty else { return }
        guard settings.isConfigured else { return }

        vm.draft = inputText
        vm.send()
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
