import SwiftUI

// MARK: - 设置页（API 接入 + 模型选择）

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings

    @State private var apiKeyInput: String = ""
    @State private var fetchingModels = false
    @State private var fetchError: String?
    @State private var showModelPicker = false
    @State private var manualModelInput: String = ""

    var body: some View {
        NavigationStack {
            List {
                providerSection
                apiKeySection
                modelSection
                usageSection
                aboutSection
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color(red: 0.043, green: 0.055, blue: 0.11))
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .sheet(isPresented: $showModelPicker) {
                ModelPickerSheet()
            }
            .onAppear {
                if apiKeyInput != settings.apiKey {
                    apiKeyInput = settings.apiKey
                }
                if manualModelInput != settings.manualModels {
                    manualModelInput = settings.manualModels
                }
            }
        }
    }

    // MARK: 服务商

    private var providerSection: some View {
        Section {
            ForEach(AppSettings.presets) { preset in
                providerRow(preset)
            }
            customProviderRow
        } header: {
            Text("服务商")
        } footer: {
            Text("选择预设服务商或自定义任意 OpenAI 兼容接口。")
        }
        .listRowBackground(Color.white.opacity(0.05))
    }

    private func providerRow(_ preset: ProviderPreset) -> some View {
        Button {
            settings.providerID = preset.id
            if settings.model.isEmpty, let m = preset.suggestedModel {
                settings.model = m
            }
            // 切换服务商后模型列表失效，重新自动拉取
            settings.availableModels = []
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(preset.name)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white)
                    Text(preset.baseURL)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color.liuliTextTertiary)
                        .lineLimit(1)
                }
                Spacer()
                if settings.providerID == preset.id {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.liuliAccent)
                }
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var customProviderRow: some View {
        Button {
            settings.providerID = "custom"
            settings.availableModels = []
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("自定义")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white)
                    Text(settings.customBaseURL.isEmpty ? "填写 Base URL" : settings.customBaseURL)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color.liuliTextTertiary)
                        .lineLimit(1)
                }
                Spacer()
                if settings.isCustom {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.liuliAccent)
                }
            }
        }
        .buttonStyle(.plain)

        if settings.isCustom {
            VStack(alignment: .leading, spacing: 8) {
                LabeledInput(title: "名称", placeholder: "我的接口", text: $settings.customName)
                LabeledInput(title: "Base URL", placeholder: "https://example.com/v1", text: $settings.customBaseURL)
                    .autocapitalization(.none)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: API Key

    private var apiKeySection: some View {
        Section {
            HStack {
                SecureField("API Key", text: $apiKeyInput)
                    .autocapitalization(.none)
                    .autocorrectionDisabled()
                    .font(.system(size: 14, design: .monospaced))
                Button("保存") {
                    settings.apiKey = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
                    // 换 Key 后重新自动拉取
                    settings.availableModels = []
                    autoFetchIfReady()
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.liuliAccent)
                .disabled(settings.apiKey == apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        } header: {
            Text("API Key（存于 Keychain）")
        } footer: {
            if let hint = settings.preset?.keyHint, !settings.isCustom {
                Text("获取：\(hint)")
            } else {
                Text("仅保存在本机钥匙串，不会上传。")
            }
        }
        .listRowBackground(Color.white.opacity(0.05))
        .onChange(of: settings.apiKey) { _, newKey in
            // 外部变化（如无）同步
            if apiKeyInput != newKey { apiKeyInput = newKey }
        }
    }

    // MARK: 模型

    private var modelSection: some View {
        Section {
            // 当前模型
            Button {
                showModelPicker = true
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(settings.model.isEmpty ? "点击选择模型" : settings.model)
                            .font(.system(size: 15, weight: .medium, design: .monospaced))
                            .foregroundStyle(settings.model.isEmpty ? Color.liuliTextTertiary : .white)
                        Text(modelSummary)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.liuliTextTertiary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.liuliTextTertiary)
                }
            }
            .buttonStyle(.plain)

            // 手动输入模型名（拉取失败时的兜底）
            HStack {
                TextField("手动输入模型名", text: $manualModelInput)
                    .autocapitalization(.none)
                    .autocorrectionDisabled()
                    .font(.system(size: 14, design: .monospaced))
                    .onSubmit { commitManualModel() }
                Button("添加") { commitManualModel() }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.liuliAccent)
            }

            if fetchingModels {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("正在识别可用模型…")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.liuliTextSecondary)
                }
            }

            if let error = fetchError {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(Color(red: 1.0, green: 0.6, blue: 0.5))
            }

            // 重新拉取
            Button {
                fetchModels()
            } label: {
                Label(fetchingModels ? "识别中…" : "重新识别模型列表", systemImage: "arrow.triangle.2.circlepath")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.liuliAccent)
            }
            .disabled(fetchingModels || !settings.hasAPIKey)

            // 视觉能力提示
            if !settings.model.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: settings.modelSupportsVisionFlag ? "eye.fill" : "eye.slash")
                        .font(.system(size: 11))
                        .foregroundStyle(settings.modelSupportsVisionFlag ? Color.liuliTeal : Color.liuliTextTertiary)
                    Text(settings.modelSupportsVisionFlag ? "该模型支持图片识别（多模态）" : "该模型可能不支持图片识别，识图请选择多模态模型")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.liuliTextTertiary)
                }
            }
        } header: {
            Text("模型")
        } footer: {
            Text("识别到的模型可直接点选；列表为空时可手动输入模型名。")
        }
        .listRowBackground(Color.white.opacity(0.05))
        .onAppear {
            autoFetchIfReady()
        }
    }

    private var modelSummary: String {
        if settings.availableModels.isEmpty {
            return settings.modelCandidates.isEmpty ? "尚未识别到模型列表" : "候选 \(settings.modelCandidates.count) 个模型"
        }
        return "已识别 \(settings.availableModels.count) 个模型"
    }

    private func commitManualModel() {
        let name = manualModelInput.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        settings.model = name
        manualModelInput = ""
    }

    // MARK: 用量偏好

    private var usageSection: some View {
        Section {
            Toggle("流式返回 Token 用量", isOn: $settings.includeUsage)
                .font(.system(size: 14))
                .foregroundStyle(.white)
        } header: {
            Text("用量")
        } footer: {
            Text("个别服务商不支持 stream_options，若报错可关闭。")
        }
        .listRowBackground(Color.white.opacity(0.05))
    }

    private var aboutSection: some View {
        Section {
            LabeledRow(label: "版本", value: "1.0.0")
            LabeledRow(label: "工作区", value: "文件 App → 我的 iPhone → 琉璃助手")
        } header: {
            Text("关于")
        }
        .listRowBackground(Color.white.opacity(0.05))
    }

    // MARK: 模型拉取

    private func autoFetchIfReady() {
        // 已有 Key、已配 Base URL、尚未拉取过 → 自动识别
        if settings.hasAPIKey, settings.baseURL != nil, settings.availableModels.isEmpty, !fetchingModels {
            fetchModels()
        }
    }

    private func fetchModels() {
        guard let base = settings.baseURL else {
            fetchError = "Base URL 无效，请检查服务商配置。"
            return
        }
        guard settings.hasAPIKey else {
            fetchError = "请先填写 API Key。"
            return
        }
        fetchingModels = true
        fetchError = nil
        let key = settings.apiKey
        Task {
            do {
                let client = APIClient(endpoint: APIClient.Endpoint(base: base, apiKey: key),
                                       includeUsage: true)
                let models = try await client.fetchModels()
                settings.availableModels = models
                // 若当前未选模型，自动选第一个
                if settings.model.trimmingCharacters(in: .whitespaces).isEmpty, let first = models.first {
                    settings.model = first
                }
                // 若当前模型不在列表中，提示但保留
                fetchingModels = false
            } catch {
                fetchError = "识别失败：\(error.localizedDescription)"
                fetchingModels = false
            }
        }
    }
}

// MARK: - 小组件

private extension SettingsView {
    var modelSupportsVisionFlag: Bool {
        VisionCapability.likelySupportsVision(modelID: settings.model)
    }
}

struct LabeledInput: View {
    let title: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(Color.liuliTextSecondary)
                .frame(width: 64, alignment: .leading)
            TextField(placeholder, text: $text)
                .autocapitalization(.none)
                .autocorrectionDisabled()
                .font(.system(size: 14, design: .monospaced))
                .foregroundStyle(.white)
        }
    }
}

struct LabeledRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 14))
                .foregroundStyle(Color.liuliTextSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 13))
                .foregroundStyle(Color.liuliTextTertiary)
        }
    }
}

// MARK: - 模型选择浮层

struct ModelPickerSheet: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private var filtered: [String] {
        let candidates = settings.modelCandidates
        guard !search.isEmpty else { return candidates }
        return candidates.filter { $0.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationStack {
            List {
                if filtered.isEmpty {
                    Text("暂无候选模型。请返回设置点击「重新识别模型列表」，或手动输入模型名。")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.liuliTextSecondary)
                } else {
                    Section("识别到 \(filtered.count) 个模型") {
                        ForEach(filtered, id: \.self) { model in
                            Button {
                                settings.model = model
                                dismiss()
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(model)
                                            .font(.system(size: 13, design: .monospaced))
                                            .foregroundStyle(.white)
                                        if VisionCapability.likelySupportsVision(modelID: model) {
                                            Text("支持图片识别")
                                                .font(.system(size: 10, weight: .medium))
                                                .foregroundStyle(Color.liuliTeal)
                                        }
                                    }
                                    Spacer()
                                    if settings.model == model {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(Color.liuliAccent)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .listRowBackground(Color.white.opacity(0.05))
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .searchable(text: $search, prompt: "搜索模型")
            .background(Color(red: 0.043, green: 0.055, blue: 0.11))
            .navigationTitle("选择模型")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                        .foregroundStyle(Color.liuliAccent)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
