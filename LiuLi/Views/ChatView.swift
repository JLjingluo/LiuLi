import SwiftUI
import PhotosUI

// MARK: - 聊天主界面 v3（液态玻璃版）
// 顶部：侧栏入口 + 低调标题 + 模式胶囊
// 中部：消息流（用户玻璃气泡 / AI 无气泡排版）
// 底部：三件独立玻璃胶囊（[+] 圆 · 长文本胶囊 · 发送圆），内容从间隙间折射而过
//
// 稳定性设计：
// - 输入框直绑 vm.draft（单一数据源，彻底消除双状态同步 bug）
// - 贴底检测双 PreferenceKey + 64/32pt 滞回（用户滑动不被劫持）
// - 思考链展开状态由本视图持有（LazyVStack 回收不丢失）

struct ChatView: View {
    @EnvironmentObject private var store: ConversationStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var router: AppRouter
    @StateObject private var vm = ChatViewModel(store: .shared, settings: .shared)

    @State private var showConversationList = false
    @State private var photoSelection: [PhotosPickerItem] = []
    @State private var stashedItems: [PhotosPickerItem] = []
    @State private var showVisionAlert = false
    @State private var forceVisionBypass = false
    @State private var optimizeError: String?
    @State private var lastScrollAt = Date.distantPast

    // 滚动状态机
    /// 内容底缘 Y（滚动坐标系内的绝对位置）
    @State private var contentBottomY: CGFloat = 0
    /// 滚动区自身可视高度（键盘弹出 / 输入栏增高时同步收缩）
    @State private var visibleScrollHeight: CGFloat = 0
    /// 用户是否贴在底部（仅贴底时才自动跟随，翻阅历史不被打断）
    @State private var pinnedToBottom = true

    // 思考链展开状态（用户显式操作记录，覆盖默认值）
    @State private var userExpandedReasoning: Set<UUID> = []
    @State private var userCollapsedReasoning: Set<UUID> = []

    @FocusState private var inputFocused: Bool
    @Environment(\.scenePhase) private var scenePhase

    /// 建议提问（按模式给出）
    private var suggestions: [String] {
        store.current?.mode == .deep
        ? ["写一个个人主页", "读一下工作区文件", "写一个计算器"]
        : ["今天适合做什么", "帮我润色一句话", "列个周末计划"]
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                VStack(spacing: 0) {
                    if !settings.isConfigured {
                        notConfiguredBanner
                    }
                    if store.current?.messages.isEmpty != false {
                        // 空状态独立于滚动区：图标在可视区域正中央
                        emptyState
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        messageList(proxy: proxy)
                    }
                }
                // 底部：玻璃回底箭头（贴底时隐藏）+ 三件玻璃胶囊输入组
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    VStack(spacing: 10) {
                        if showScrollToBottomArrow {
                            scrollToBottomArrow(proxy: proxy)
                                .transition(.scale(scale: 0.5, anchor: .center).combined(with: .opacity))
                        }
                        inputBar
                            .padding(.horizontal, 12)
                            .padding(.top, 8)
                            .padding(.bottom, 4)
                    }
                    .animation(.spring(response: 0.35, dampingFraction: 0.7),
                               value: showScrollToBottomArrow)
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
                        vm.draft = prompt
                        router.pendingPrompt = nil
                        inputFocused = true
                    }
                }
                // Siri 快捷指令：提问（自动填入输入框并聚焦）
                .onReceive(NotificationCenter.default.publisher(for: .nexusSiriPrompt)) { note in
                    if let prompt = note.object as? String, !prompt.isEmpty {
                        vm.draft = prompt
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
    }

    // MARK: 未配置提示（玻璃横幅）

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
            .liquidGlass(cornerRadius: 14)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.top, 6)
    }

    // MARK: 消息列表（滚动核心）

    /// 内容底缘位置（滚动坐标系）
    private struct ChatContentBottomKey: PreferenceKey {
        static var defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
    }

    /// 滚动区自身可视高度
    private struct ChatVisibleHeightKey: PreferenceKey {
        static var defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
    }

    private func messageList(proxy: ScrollViewProxy) -> some View {
        ScrollView {
            LazyVStack(spacing: 18) {
                ForEach(store.current?.messages ?? []) { message in
                    MessageBubble(
                        message: message,
                        isStreaming: vm.stream.activeID == message.id,
                        isLatestAssistant: isLatestAssistant(message),
                        reasoningExpanded: reasoningBinding(message),
                        showTimestamp: settings.showTimestamps,
                        stream: vm.stream,
                        onRegenerate: {
                            // 重写：回到贴底并跟随新一轮生成位置
                            pinnedToBottom = true
                            vm.regenerate()
                        }
                    )
                    .id(message.id)
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 8)

            // 底部哨兵：内容底缘 Y（滚动坐标系内的绝对位置）
            GeometryReader { geo in
                Color.clear
                    .preference(
                        key: ChatContentBottomKey.self,
                        value: geo.frame(in: .named("chatScroll")).minY
                    )
            }
            .frame(height: 1)
        }
        .coordinateSpace(name: "chatScroll")
        .background(
            // 滚动区自身高度：键盘弹出 / 输入栏增高时同步收缩，贴底判断不受屏高误差影响
            GeometryReader { geo in
                Color.clear.preference(key: ChatVisibleHeightKey.self, value: geo.size.height)
            }
        )
        .onPreferenceChange(ChatContentBottomKey.self) { newValue in
            contentBottomY = newValue
            syncPinnedState()
        }
        .onPreferenceChange(ChatVisibleHeightKey.self) { newValue in
            visibleScrollHeight = newValue
            syncPinnedState()
        }
        // 新消息插入：贴底时以弹簧动画跟随（含用户刚发送 / 重写的场景）
        .onChange(of: store.current?.messages.count) { _, newCount in
            guard pinnedToBottom, let count = newCount, count > 0,
                  let last = store.current?.messages.last else { return }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
        // 流式跟随：由 VM 的节流 scrollTick 信号驱动（~8 次/秒），此处再限 ~4 次/秒；
        // 用户上滑脱离贴底后立即停止跟随（由 syncPinnedState 持续维护）
        .onChange(of: vm.scrollTick) { _, _ in
            guard vm.isStreaming, settings.autoFollowEnabled, pinnedToBottom,
                  let last = store.current?.messages.last else { return }
            guard Date().timeIntervalSince(lastScrollAt) > 0.25 else { return }
            lastScrollAt = Date()
            proxy.scrollTo(last.id, anchor: .bottom)
        }
        // 切换会话：重置贴底状态并直接跳底（无动画，避免跨会话滚动轨迹）
        .onChange(of: store.currentID) { _, _ in
            contentBottomY = 0
            pinnedToBottom = true
            if let last = store.current?.messages.last {
                DispatchQueue.main.async {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
        .defaultScrollAnchor(.bottom)
        .scrollDismissesKeyboard(.immediately)
    }

    /// 贴底检测（滞回防抖）：距底 > 64pt 视为脱离；贴回 < 32pt 视为恢复
    private func syncPinnedState() {
        let distance = contentBottomY - visibleScrollHeight
        if distance > 64 {
            if pinnedToBottom { pinnedToBottom = false }
        } else if distance < 32 {
            if !pinnedToBottom { pinnedToBottom = true }
        }
    }

    /// 是否展示「回到底部」玻璃箭头（阈值更高，与贴底判定形成滞回区，避免闪烁）
    private var showScrollToBottomArrow: Bool {
        guard store.current?.messages.isEmpty == false else { return false }
        return contentBottomY - visibleScrollHeight > 120
    }

    /// 回底箭头：独立玻璃圆 + 下箭头，一键弹回底部（弹簧物理回弹）
    private func scrollToBottomArrow(proxy: ScrollViewProxy) -> some View {
        HStack {
            Spacer()
            Button {
                Haptics.tap()
                scrollToBottom(proxy)
            } label: {
                Image(systemName: "arrow.down")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.textSecondary)
                    .frame(width: 38, height: 38)
                    .liquidGlass(cornerRadius: 19, interactive: true)
            }
            .buttonStyle(PressableButtonStyle(scale: 0.86))
            .padding(.trailing, 6)
        }
    }

    /// 弹回底部：带阻尼的弹簧（先快后缓的自然回弹，非生硬 easeOut）
    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        guard let last = store.current?.messages.last else { return }
        pinnedToBottom = true
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
            proxy.scrollTo(last.id, anchor: .bottom)
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

    // MARK: 思考链展开绑定（状态存于本视图，LazyVStack 回收不丢失）

    private func reasoningBinding(_ message: ChatMessage) -> Binding<Bool> {
        Binding(
            get: {
                if userExpandedReasoning.contains(message.id) { return true }
                if userCollapsedReasoning.contains(message.id) { return false }
                return settings.defaultExpandReasoning
            },
            set: { expanded in
                if expanded {
                    userExpandedReasoning.insert(message.id)
                    userCollapsedReasoning.remove(message.id)
                } else {
                    userCollapsedReasoning.insert(message.id)
                    userExpandedReasoning.remove(message.id)
                }
            }
        )
    }

    // MARK: 空状态

    private var emptyState: some View {
        VStack(spacing: 0) {
            // logo：品牌渐变圆角方 + 白 N
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.brandGradient)
                Text("N")
                    .font(.system(size: 25, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.white)
            }
            .frame(width: 52, height: 52)
            .shadow(color: Color.brand.opacity(0.35), radius: 14, y: 6)

            Text("你好，我是 \(AppInfo.displayName)")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.textPrimary)
                .padding(.top, 16)

            Text(modeHintText)
                .font(.system(size: 13))
                .foregroundStyle(Color.textTertiary)
                .padding(.top, 6)

            // 建议胶囊（玻璃质感，点击填入输入框）
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(suggestions, id: \.self) { s in
                        Button {
                            Haptics.tap()
                            vm.draft = s
                            inputFocused = true
                        } label: {
                            Text(s)
                                .font(.system(size: 12.5))
                                .foregroundStyle(Color.textSecondary)
                                .padding(.horizontal, 13)
                                .padding(.vertical, 7)
                                .liquidGlass(cornerRadius: 16)
                        }
                        .buttonStyle(PressableButtonStyle(scale: 0.94))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 28)
            }
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

    // MARK: 工具栏（principal 低调标题 + 模式胶囊）

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                Haptics.tap()
                showConversationList = true
            } label: {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(Color.textSecondary)
            }
        }

        // principal 标题：现代极简（低调灰、可截断，绝不挤压两侧按钮）
        ToolbarItem(placement: .principal) {
            Text(store.current?.title ?? "对话")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 160)
                .fixedSize(horizontal: false, vertical: true)
        }

        ToolbarItem(placement: .topBarTrailing) {
            // 模式胶囊：短名 + fixedSize，长标题下也不会被压缩
            Button {
                guard var conv = store.current else { return }
                Haptics.tap()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    conv.mode = conv.mode == .lite ? .deep : .lite
                    store.update(conv)
                }
            } label: {
                HStack(spacing: 5) {
                    Circle()
                        .fill(Color.brand)
                        .frame(width: 4.5, height: 4.5)
                    Text((store.current?.mode ?? .lite).shortName)
                        .font(.system(size: 12.5, weight: .medium))
                        .contentTransition(.opacity)
                }
                .foregroundStyle(Color.brand)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.brandSoft))
                .overlay(Capsule().strokeBorder(Color.brand.opacity(0.14), lineWidth: 1))
                .fixedSize()
            }
            .buttonStyle(PressableButtonStyle(scale: 0.94))
            .animation(.easeInOut(duration: 0.18), value: store.current?.mode)
        }
    }

    // MARK: 输入栏（三件独立玻璃胶囊：[+] 圆 · 长文本胶囊 · 发送圆）

    private var inputBar: some View {
        VStack(spacing: 7) {
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
                                    Haptics.tap()
                                    vm.pendingImages.removeAll { $0.id == img.id }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 15))
                                        .foregroundStyle(Color.textTertiary)
                                        .shadow(color: .white, radius: 2)
                                }
                                .buttonStyle(PressableButtonStyle(scale: 0.82))
                                .offset(x: 5, y: -5)
                            }
                        }
                    }
                    .padding(.horizontal, 4)
                }
                .frame(height: 68)
            }

            // 三件套：左 [+] 玻璃圆 · 中 玻璃长胶囊 · 右 发送/停止圆
            HStack(alignment: .bottom, spacing: 8) {
                PhotosPicker(selection: $photoSelection, maxSelectionCount: 3, matching: .images) {
                    Image(systemName: "plus")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Color.textSecondary)
                        .frame(width: 36, height: 36)
                        .liquidGlass(cornerRadius: 18, interactive: true)
                }
                .buttonStyle(PressableButtonStyle(scale: 0.88))
                .disabled(vm.isStreaming)

                ZStack(alignment: .bottomTrailing) {
                    // 输入胶囊直绑 vm.draft（单一数据源，无同步 bug）
                    TextField(vm.isStreaming ? "生成中…" : "有问题，尽管问", text: $vm.draft, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(1...5)
                        .focused($inputFocused)
                        .font(.system(size: settings.chatFontSize + 0.5))
                        .foregroundStyle(Color.textPrimary)
                        .padding(.leading, 15)
                        .padding(.trailing, showOptimizeButton ? 42 : 15)
                        .padding(.vertical, 11)
                        .submitLabel(.send)
                        .onSubmit {
                            if settings.enterToSend { performSend() }
                        }

                    if showOptimizeButton {
                        optimizeButton
                    }
                }
                .liquidGlass(cornerRadius: 19, interactive: true, tinted: true)

                sendButton
            }

            Text("内容由 AI 生成，请注意甄别")
                .font(.system(size: 10))
                .foregroundStyle(Color.textTertiary.opacity(0.7))
                .padding(.bottom, 1)
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

    // MARK: 提示词优化（输入胶囊右下角魔法棒）

    private var showOptimizeButton: Bool {
        settings.promptOptimizerEnabled && !vm.isStreaming &&
        !vm.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @ViewBuilder
    private var optimizeButton: some View {
        Button {
            Haptics.tap()
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
        .buttonStyle(PressableButtonStyle(scale: 0.85))
        .disabled(vm.isOptimizing)
        .padding(.trailing, 6)
        .padding(.bottom, 5)
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
                        Haptics.tap()
                        vm.undoOptimize()
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
                .buttonStyle(PressableButtonStyle(scale: 0.85))
            }
        }
        .font(.system(size: 12))
        .foregroundStyle(Color.textSecondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .liquidGlass(cornerRadius: 16)
        .padding(.horizontal, 4)
    }

    private func performOptimize() {
        guard !vm.isOptimizing else { return }
        guard !vm.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        optimizeError = nil
        Task {
            if let error = await vm.optimizeDraft() {
                optimizeError = error
            }
        }
    }

    // MARK: 发送 / 停止（同一位置平滑过渡）

    @ViewBuilder
    private var sendButton: some View {
        Button {
            Haptics.tap()
            if vm.isStreaming {
                vm.stop()
            } else {
                performSend()
            }
        } label: {
            ZStack {
                if vm.isStreaming {
                    // 停止态：玻璃圆 + 深色小方块
                    Circle()
                        .fill(Color.surfaceCard)
                        .frame(width: 36, height: 36)
                        .overlay(Circle().strokeBorder(Color.glassStroke, lineWidth: 1))
                    RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                        .fill(Color.textPrimary)
                        .frame(width: 12, height: 12)
                        .transition(.scale(scale: 0.5).combined(with: .opacity))
                } else {
                    // 发送态：品牌渐变圆 + 上箭头（顶部高光做玻璃质感）
                    ZStack {
                        Circle().fill(Color.brandGradient)
                        Circle()
                            .fill(
                                LinearGradient(
                                    stops: [
                                        .init(color: .white.opacity(0.35), location: 0),
                                        .init(color: .white.opacity(0.0), location: 0.45)
                                    ],
                                    startPoint: .top, endPoint: .bottom))
                    }
                    .frame(width: 36, height: 36)
                    Image(systemName: "arrow.up")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .transition(.scale(scale: 0.5).combined(with: .opacity))
                }
            }
        }
        .buttonStyle(PressableButtonStyle(scale: 0.86))
        .disabled(!vm.isStreaming && !canSendInput)
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: vm.isStreaming)
        .animation(.easeInOut(duration: 0.15), value: canSendInput)
    }

    private var canSendInput: Bool {
        !vm.isStreaming && settings.isConfigured &&
        (!vm.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !vm.pendingImages.isEmpty)
    }

    /// 发送：直绑 draft 后无需任何状态同步，发送即贴底跟随
    private func performSend() {
        guard !vm.isStreaming else { return }
        guard settings.isConfigured else { return }
        guard canSendInput else { return }

        Haptics.success()
        pinnedToBottom = true
        vm.send()
        inputFocused = false
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
