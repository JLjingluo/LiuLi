import Foundation
import Security

// MARK: - 服务商预设

struct ProviderPreset: Identifiable, Equatable {
    let id: String
    let name: String
    let baseURL: String
    let suggestedModel: String?
    /// 预填 Key 的获取提示（不自动打开链接，仅展示文字）
    let keyHint: String
}

// MARK: - 设置存储（API Key 存 Keychain，其余存 UserDefaults）

@MainActor
final class AppSettings: ObservableObject {

    static let shared = AppSettings()

    // MARK: 预设

    static let presets: [ProviderPreset] = [
        ProviderPreset(id: "deepseek", name: "DeepSeek", baseURL: "https://api.deepseek.com/v1",
                       suggestedModel: "deepseek-chat", keyHint: "platform.deepseek.com → API Keys"),
        ProviderPreset(id: "openai", name: "OpenAI", baseURL: "https://api.openai.com/v1",
                       suggestedModel: "gpt-4o-mini", keyHint: "platform.openai.com → API Keys"),
        ProviderPreset(id: "moonshot", name: "Kimi (月之暗面)", baseURL: "https://api.moonshot.cn/v1",
                       suggestedModel: "moonshot-v1-8k", keyHint: "platform.moonshot.cn → API Key"),
        ProviderPreset(id: "zhipu", name: "智谱 GLM", baseURL: "https://open.bigmodel.cn/api/paas/v4",
                       suggestedModel: "glm-4-flash", keyHint: "open.bigmodel.cn → API Keys"),
        ProviderPreset(id: "siliconflow", name: "硅基流动", baseURL: "https://api.siliconflow.cn/v1",
                       suggestedModel: nil, keyHint: "cloud.siliconflow.cn → API Keys"),
        ProviderPreset(id: "ollama", name: "Ollama 本地", baseURL: "http://127.0.0.1:11434/v1",
                       suggestedModel: nil, keyHint: "本地无需 Key，填任意字符即可")
    ]

    // MARK: 持久化键

    private enum Keys {
        static let providerID = "settings.providerID"
        static let customName = "settings.customName"
        static let customBaseURL = "settings.customBaseURL"
        static let model = "settings.model"
        static let manualModels = "settings.manualModels"
        static let includeUsage = "settings.includeUsage"
        static let inputPricePerM = "settings.inputPricePerM"
        static let outputPricePerM = "settings.outputPricePerM"
        static let pricingCustomized = "settings.pricingCustomized"
        static let promptOptimizerEnabled = "settings.promptOptimizerEnabled"
        static let systemPromptLite = "settings.systemPromptLite"
        static let systemPromptDeep = "settings.systemPromptDeep"
        // v1.7 外观自定义
        static let themeID = "settings.themeID"
        static let chatFontSize = "settings.chatFontSize"
        static let showAIavatar = "settings.showAIavatar"
        static let hapticsEnabled = "settings.hapticsEnabled"
        static let markdownEnabled = "settings.markdownEnabled"
        static let defaultExpandReasoning = "settings.defaultExpandReasoning"
    }

    // MARK: 默认注入提示词（设置页可编辑，可一键恢复）

    /// 快速模式默认（保持精简，控制 Token 消耗）
    static let defaultLiteSystemPrompt = """
    你是「璇玑」，一个简洁高效的中文 AI 助手。
    - 用简体中文回答，直击要点，短问题给短答案
    - 默认不使用 Markdown 标题与加粗，直接给结论
    - 信息不足时先反问一句再作答，不做长篇铺垫
    """

    /// 深度模式默认（Agent 规范：文件工具 + 编码约定）
    static let defaultDeepSystemPrompt = """
    你是「璇玑」，一个专业的 AI 编程与文件助手，运行在 iPhone 上。

    ## 工具
    工作区（App 沙盒 Documents）内的文件通过工具访问：list_files 列目录、read_file 读文件、write_file 写文件（自动创建父目录）、delete_file 删除。涉及文件操作时优先用工具完成，而不是只给建议；修改文件前先 read_file 了解现状，避免覆盖未知内容。

    ## 编码规范
    - 代码放入代码块并标注语言
    - HTML/CSS/JS 保证手机 Safari 直接打开可用：自包含、无外部依赖、包含 viewport
    - 小程序类需求输出单个完整文件，不要拆成多个文件增加用户负担

    ## 回答风格
    - 使用 Markdown 排版，先给结论或成果，再给必要说明
    - 给完整可运行代码，不用伪代码或「此处省略」占位
    """

    /// 模型价格（元 / 百万 tokens）
    struct ModelPricing: Equatable {
        var input: Double
        var output: Double
    }

    /// 常见模型默认单价（元/百万 tokens），未知模型回退 DeepSeek 档
    static func suggestedPricing(forModel modelID: String) -> ModelPricing {
        let m = modelID.lowercased()
        if m.contains("deepseek-reasoner") { return ModelPricing(input: 4, output: 16) }
        if m.contains("deepseek") { return ModelPricing(input: 2, output: 8) }
        if m.contains("gpt-4o-mini") { return ModelPricing(input: 1.1, output: 4.3) }
        if m.contains("gpt-4o") { return ModelPricing(input: 16.5, output: 66) }
        if m.contains("o4-mini") || m.contains("o3-mini") { return ModelPricing(input: 8, output: 32) }
        if m.contains("glm-4-flash") || m.contains("glm-4.5-flash") { return ModelPricing(input: 0, output: 0) }
        if m.contains("glm-4") { return ModelPricing(input: 14, output: 14) }
        if m.contains("moonshot-v1-8k") { return ModelPricing(input: 12, output: 12) }
        if m.contains("qwen-turbo") { return ModelPricing(input: 0.3, output: 0.6) }
        if m.contains("qwen-plus") { return ModelPricing(input: 0.8, output: 2) }
        return ModelPricing(input: 2, output: 8)
    }

    private let keychainService = "com.liulidev.assistant"
    private let keychainAccount = "api-key"

    private let d: UserDefaults

    // MARK: 发布属性

    @Published var providerID: String {
        didSet { d.set(providerID, forKey: Keys.providerID) }
    }
    /// 自定义服务商名称（providerID == "custom" 时使用）
    @Published var customName: String {
        didSet { d.set(customName, forKey: Keys.customName) }
    }
    @Published var customBaseURL: String {
        didSet { d.set(customBaseURL, forKey: Keys.customBaseURL) }
    }
    /// 当前选择模型（手动输入或从列表选择）
    @Published var model: String {
        didSet {
            d.set(model, forKey: Keys.model)
            applySuggestedPricingIfNotCustomized()
        }
    }
    /// 拉取到的模型列表
    @Published var availableModels: [String] = []
    /// 手动补充的模型名（拉取失败/未提供列表时）
    @Published var manualModels: String {
        didSet { d.set(manualModels, forKey: Keys.manualModels) }
    }
    /// 流式请求是否携带 stream_options.include_usage
    @Published var includeUsage: Bool {
        didSet { d.set(includeUsage, forKey: Keys.includeUsage) }
    }
    /// 输入单价（元 / 百万 tokens）
    @Published var inputPricePerM: Double {
        didSet {
            d.set(inputPricePerM, forKey: Keys.inputPricePerM)
            if !isApplyingSuggested { d.set(true, forKey: Keys.pricingCustomized) }
        }
    }
    /// 输出单价（元 / 百万 tokens）
    @Published var outputPricePerM: Double {
        didSet {
            d.set(outputPricePerM, forKey: Keys.outputPricePerM)
            if !isApplyingSuggested { d.set(true, forKey: Keys.pricingCustomized) }
        }
    }
    /// 提示词优化（输入框右下角魔法棒）
    @Published var promptOptimizerEnabled: Bool {
        didSet { d.set(promptOptimizerEnabled, forKey: Keys.promptOptimizerEnabled) }
    }
    /// 快速模式注入提示词（System Prompt）
    @Published var systemPromptLite: String {
        didSet { d.set(systemPromptLite, forKey: Keys.systemPromptLite) }
    }
    /// 深度模式注入提示词（System Prompt）
    @Published var systemPromptDeep: String {
        didSet { d.set(systemPromptDeep, forKey: Keys.systemPromptDeep) }
    }
    // MARK: v1.7 外观自定义
    /// 主题 id（晴空蓝 / 靛夜紫 / 青竹碧 / 落日橙 / 樱花粉 / 琥珀金）
    @Published var themeID: String {
        didSet {
            d.set(themeID, forKey: Keys.themeID)
            applyTheme()
        }
    }
    /// 消息正文字号（13 小 / 15 标准 / 17 大 / 19 特大）
    @Published var chatFontSize: Double {
        didSet { d.set(chatFontSize, forKey: Keys.chatFontSize) }
    }
    /// 显示 AI 头像与名称行
    @Published var showAIavatar: Bool {
        didSet { d.set(showAIavatar, forKey: Keys.showAIavatar) }
    }
    /// 按钮触感反馈
    @Published var hapticsEnabled: Bool {
        didSet { d.set(hapticsEnabled, forKey: Keys.hapticsEnabled) }
    }
    /// 渲染 Markdown（关闭则纯文本展示）
    @Published var markdownEnabled: Bool {
        didSet { d.set(markdownEnabled, forKey: Keys.markdownEnabled) }
    }
    /// 思考链默认展开
    @Published var defaultExpandReasoning: Bool {
        didSet { d.set(defaultExpandReasoning, forKey: Keys.defaultExpandReasoning) }
    }
    /// 用户是否手动改过单价（决定切模型时是否自动跟随建议价）
    private var pricingCustomized: Bool
    /// 正在自动写入建议价（避免误标为「用户手动改价」）
    private var isApplyingSuggested = false

    // MARK: 派生

    var isCustom: Bool { providerID == "custom" }

    /// 当前主题配色（主题切换即时生效）
    var theme: ThemePalette { ThemePalette.palette(for: themeID) }

    var preset: ProviderPreset? {
        Self.presets.first { $0.id == providerID }
    }

    var providerDisplayName: String {
        if isCustom {
            let n = customName.trimmingCharacters(in: .whitespaces)
            return n.isEmpty ? "自定义" : n
        }
        return preset?.name ?? "自定义"
    }

    /// 规整后的 Base URL（去空格、保尾斜杠）
    var normalizedBaseURLString: String {
        var s = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }

    private var baseURLString: String {
        if isCustom { return customBaseURL }
        return preset?.baseURL ?? ""
    }

    var baseURL: URL? {
        let s = normalizedBaseURLString
        guard !s.isEmpty else { return nil }
        return URL(string: s)
    }

    var apiKey: String {
        get { Keychain.load(service: keychainService, account: keychainAccount) ?? "" }
        set { Keychain.save(newValue, service: keychainService, account: keychainAccount) }
    }

    /// 配置是否完备（可发起请求）
    var isConfigured: Bool {
        baseURL != nil && !apiKey.trimmingCharacters(in: .whitespaces).isEmpty && !model.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// 当前模型是否疑似支持视觉（多模态），供设置页提示用
    var modelSupportsVisionFlag: Bool {
        VisionCapability.likelySupportsVision(modelID: model)
    }

    /// 候选模型列表 = 拉取结果 + 手动补充（去重）
    var modelCandidates: [String] {
        var seen = Set<String>()
        var out: [String] = []
        for m in availableModels + manualModelList {
            let t = m.trimmingCharacters(in: .whitespaces)
            if !t.isEmpty && !seen.contains(t) {
                seen.insert(t)
                out.append(t)
            }
        }
        return out
    }

    private var manualModelList: [String] {
        manualModels
            .components(separatedBy: CharacterSet(charactersIn: ",\n"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    var hasAPIKey: Bool {
        !apiKey.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: 初始化

    init(defaults: UserDefaults = .standard) {
        self.d = defaults
        self.providerID = defaults.string(forKey: Keys.providerID) ?? "deepseek"
        self.customName = defaults.string(forKey: Keys.customName) ?? ""
        self.customBaseURL = defaults.string(forKey: Keys.customBaseURL) ?? ""
        let modelID = defaults.string(forKey: Keys.model) ?? ""
        self.model = modelID
        self.manualModels = defaults.string(forKey: Keys.manualModels) ?? ""
        self.includeUsage = defaults.object(forKey: Keys.includeUsage) as? Bool ?? true
        self.pricingCustomized = defaults.bool(forKey: Keys.pricingCustomized)
        if let inP = defaults.object(forKey: Keys.inputPricePerM) as? Double,
           let outP = defaults.object(forKey: Keys.outputPricePerM) as? Double {
            self.inputPricePerM = inP
            self.outputPricePerM = outP
        } else {
            let p = Self.suggestedPricing(forModel: modelID)
            self.inputPricePerM = p.input
            self.outputPricePerM = p.output
        }
        self.promptOptimizerEnabled = defaults.object(forKey: Keys.promptOptimizerEnabled) as? Bool ?? true
        self.systemPromptLite = defaults.string(forKey: Keys.systemPromptLite) ?? Self.defaultLiteSystemPrompt
        self.systemPromptDeep = defaults.string(forKey: Keys.systemPromptDeep) ?? Self.defaultDeepSystemPrompt
        // v1.7 外观自定义
        self.themeID = defaults.string(forKey: Keys.themeID) ?? "nexus"
        let storedSize = defaults.object(forKey: Keys.chatFontSize) as? Double ?? 15
        self.chatFontSize = (13...19).contains(storedSize) ? storedSize : 15
        self.showAIavatar = defaults.object(forKey: Keys.showAIavatar) as? Bool ?? true
        self.hapticsEnabled = defaults.object(forKey: Keys.hapticsEnabled) as? Bool ?? true
        self.markdownEnabled = defaults.object(forKey: Keys.markdownEnabled) as? Bool ?? true
        self.defaultExpandReasoning = defaults.object(forKey: Keys.defaultExpandReasoning) as? Bool ?? false
        applyTheme()
    }

    /// 把当前主题写入全局 Color 扩展（Color.brand 等随之变化）
    private func applyTheme() {
        CurrentTheme.palette = theme
    }

    /// 恢复某个模式的默认注入提示词
    func resetSystemPrompt(lite: Bool) {
        if lite {
            systemPromptLite = Self.defaultLiteSystemPrompt
        } else {
            systemPromptDeep = Self.defaultDeepSystemPrompt
        }
    }

    /// 切模型时自动跟随建议单价（用户手动改过则不动）
    private func applySuggestedPricingIfNotCustomized() {
        guard !pricingCustomized else { return }
        isApplyingSuggested = true
        let p = Self.suggestedPricing(forModel: model)
        inputPricePerM = p.input
        outputPricePerM = p.output
        isApplyingSuggested = false
    }

    /// 恢复当前模型的建议单价（设置页按钮），并恢复自动跟随
    func resetPricingToSuggested() {
        isApplyingSuggested = true
        let p = Self.suggestedPricing(forModel: model)
        inputPricePerM = p.input
        outputPricePerM = p.output
        isApplyingSuggested = false
        pricingCustomized = false
        d.set(false, forKey: Keys.pricingCustomized)
    }
}

// MARK: - Keychain 封装（纯 Security 框架）

enum Keychain {

    static func save(_ value: String, service: String, account: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        // 先删后写，幂等
        SecItemDelete(query as CFDictionary)
        guard !value.isEmpty else { return }
        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(attributes as CFDictionary, nil)
    }

    static func load(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
