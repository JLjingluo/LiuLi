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
                optimizerSection
                aboutSection
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.appBackground)
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
        .listRowBackground(Color.surfaceCard)
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
                        .foregroundStyle(Color.textPrimary)
                    Text(preset.baseURL)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color.textTertiary)
                        .lineLimit(1)
                }
                Spacer()
                if settings.providerID == preset.id {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.brand)
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
                        .foregroundStyle(Color.textPrimary)
                    Text(settings.customBaseURL.isEmpty ? "填写 Base URL" : settings.customBaseURL)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color.textTertiary)
                        .lineLimit(1)
                }
                Spacer()
                if settings.isCustom {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.brand)
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
                .foregroundStyle(Color.brand)
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
        .listRowBackground(Color.surfaceCard)
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
                            .foregroundStyle(settings.model.isEmpty ? Color.textTertiary : .white)
                        Text(modelSummary)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.textTertiary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.textTertiary)
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
                    .foregroundStyle(Color.brand)
            }

            if fetchingModels {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("正在识别可用模型…")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.textSecondary)
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
                    .foregroundStyle(Color.brand)
            }
            .disabled(fetchingModels || !settings.hasAPIKey)

            // 视觉能力提示
            if !settings.model.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: settings.modelSupportsVisionFlag ? "eye.fill" : "eye.slash")
                        .font(.system(size: 11))
                        .foregroundStyle(settings.modelSupportsVisionFlag ? Color.brand : Color.textTertiary)
                    Text(settings.modelSupportsVisionFlag ? "该模型支持图片识别（多模态）" : "该模型可能不支持图片识别，识图请选择多模态模型")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.textTertiary)
                }
            }
        } header: {
            Text("模型")
        } footer: {
            Text("识别到的模型可直接点选；列表为空时可手动输入模型名。")
        }
        .listRowBackground(Color.surfaceCard)
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

    // MARK: 用量偏好与费用估算

    private var usageSection: some View {
        Section {
            Toggle("显示本次花费", isOn: $settings.includeUsage)
                .font(.system(size: 14))
                .foregroundStyle(Color.textPrimary)
            HStack {
                Text("输入单价")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                TextField("2", value: $settings.inputPricePerM, format: .number.precision(.fractionLength(0...4)))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundStyle(Color.textSecondary)
                    .frame(width: 90)
                Text("元/百万")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.textTertiary)
            }
            HStack {
                Text("输出单价")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                TextField("8", value: $settings.outputPricePerM, format: .number.precision(.fractionLength(0...4)))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundStyle(Color.textSecondary)
                    .frame(width: 90)
                Text("元/百万")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.textTertiary)
            }
            Button {
                settings.resetPricingToSuggested()
            } label: {
                Label("恢复当前模型建议单价", systemImage: "arrow.counterclockwise")
                    .font(.system(size: 13.5))
            }
        } header: {
            Text("费用估算")
        } footer: {
            Text("每条回复下方按 Token 用量估算花费（¥）。切换模型时自动套用常见模型单价，可手动修改。个别服务商不支持 stream_options，若报错可关闭「显示本次花费」。")
        }
        .listRowBackground(Color.surfaceCard)
    }

    // MARK: 提示词优化

    private var optimizerSection: some View {
        Section {
            Toggle("启用提示词优化", isOn: $settings.promptOptimizerEnabled)
                .font(.system(size: 14))
                .foregroundStyle(Color.textPrimary)
        } header: {
            Text("提示词优化")
        } footer: {
            Text("开启后，输入框右下角出现魔法棒按钮，一键把草稿改写成更清晰、具体的提示词，可随时撤销。")
        }
        .listRowBackground(Color.surfaceCard)
    }

    private var aboutSection: some View {
        Section {
            LabeledRow(label: "版本", value: "1.0.0")
            LabeledRow(label: "工作区", value: "文件 App → 我的 iPhone → Nexus")
        } header: {
            Text("关于")
        }
        .listRowBackground(Color.surfaceCard)
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
                .foregroundStyle(Color.textSecondary)
                .frame(width: 64, alignment: .leading)
            TextField(placeholder, text: $text)
                .autocapitalization(.none)
                .autocorrectionDisabled()
                .font(.system(size: 14, design: .monospaced))
                .foregroundStyle(Color.textPrimary)
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
                .foregroundStyle(Color.textSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 13))
                .foregroundStyle(Color.textTertiary)
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
                        .foregroundStyle(Color.textSecondary)
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
                                            .foregroundStyle(Color.textPrimary)
                                        if VisionCapability.likelySupportsVision(modelID: model) {
                                            Text("支持图片识别")
                                                .font(.system(size: 10, weight: .medium))
                                                .foregroundStyle(Color.brand)
                                        }
                                    }
                                    Spacer()
                                    if settings.model == model {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(Color.brand)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .listRowBackground(Color.surfaceCard)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .searchable(text: $search, prompt: "搜索模型")
            .background(Color.appBackground)
            .navigationTitle("选择模型")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                        .foregroundStyle(Color.brand)
                }
            }
        }
    }
}
