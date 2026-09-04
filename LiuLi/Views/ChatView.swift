import SwiftUI
import PhotosUI

// MARK: - 聊天主界面

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
    @FocusState private var inputFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !settings.isConfigured {
                    notConfiguredBanner
                }
                messageList
                inputBar
            }
            .navigationTitle(currentTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
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
        }
    }

    private var currentTitle: String {
        store.current?.title ?? "对话"
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
            .foregroundStyle(Color(red: 1.0, green: 0.78, blue: 0.35))
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
                LazyVStack(spacing: 14) {
                    if let messages = store.current?.messages, !messages.isEmpty {
                        ForEach(messages) { message in
                            MessageBubble(
                                message: message,
                                isStreaming: vm.isStreaming && message.id == store.current?.messages.last?.id
                            )
                            .id(message.id)
                        }
                    } else {
                        emptyState
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 6)
            }
            .onChange(of: store.current?.messages.count) { _, newCount in
                // 新消息出现时滚动到底
                if let count = newCount, count > 0,
                   let last = store.current?.messages.last {
                    withAnimation(.easeOut(duration: 0.25)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
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

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "sparkles")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(
                    LinearGradient(colors: [Color.liuliTeal, Color.liuliViolet],
                                   startPoint: .top, endPoint: .bottom))
            Text("开始新对话")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
            Text(modeHintText)
                .font(.system(size: 13))
                .foregroundStyle(Color.liuliTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
        }
        .padding(.top, 60)
    }

    private var modeHintText: String {
        switch store.current?.mode {
        case .deep:
            return "深度模式：完整上下文，AI 可读写工作区文件、编写并保存 HTML 小程序"
        default:
            return "省流模式：精简上下文与历史图片，Token 消耗最低"
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

        ToolbarItem(placement: .topBarTrailing) {
            PhotosPicker(selection: $photoSelection, maxSelectionCount: 3, matching: .images) {
                Image(systemName: "photo.on.rectangle.angled")
                    .foregroundStyle(Color.liuliAccent)
            }
            .disabled(vm.isStreaming)
        }
    }

    // MARK: 输入栏

    private var inputBar: some View {
        VStack(spacing: 8) {
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
                                        .frame(width: 64, height: 64)
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                } else {
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(Color.white.opacity(0.1))
                                        .frame(width: 64, height: 64)
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
                .frame(height: 74)
            }

            HStack(alignment: .bottom, spacing: 8) {
                TextField(vm.isStreaming ? "生成中…" : "输入消息…", text: $vm.draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...5)
                    .focused($inputFocused)
                    .font(.system(size: 15))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(.ultraThinMaterial)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                    )
                    .submitLabel(.send)
                    .onSubmit { vm.send() }

                sendButton
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
        }
        .padding(.top, 8)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 0.5)
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
                Image(systemName: "stop.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(Color(red: 1.0, green: 0.42, blue: 0.42))
            }
            .buttonStyle(.plain)
        } else {
            Button(action: { vm.send() }) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(
                        vm.canSend
                            ? AnyShapeStyle(LinearGradient(colors: [Color.liuliTeal, Color.liuliIndigo],
                                                          startPoint: .topLeading, endPoint: .bottomTrailing))
                            : AnyShapeStyle(Color.white.opacity(0.25))
                    )
            }
            .buttonStyle(.plain)
            .disabled(!vm.canSend)
        }
    }

    // MARK: 图片选择处理

    private func loadPickedImages(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        photoSelection = []
        // 识图能力预检：不支持时提示（可强制继续）
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
