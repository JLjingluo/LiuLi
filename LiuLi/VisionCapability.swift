import Foundation

// MARK: - 模型多模态（识图）能力启发式判断（纯逻辑，Linux 已测）
// OpenAI 兼容 /models 不返回能力元数据，只能按命名惯例启发式判断。
// 判断错误的代价是可控的：误判为不支持 → 用户收到提示仍可继续；
// 误判为支持 → 服务端会报错，错误信息会正常展示。

enum VisionCapability {

    /// 已知**不支持**图片输入的常见模型前缀（小写匹配）
    private static let knownTextOnlyPrefixes: [String] = [
        "deepseek-chat", "deepseek-reasoner", "deepseek-coder", "deepseek-v3", "deepseek-r1",
        "gpt-3.5", "o1-mini", "o3-mini", "text-embedding", "embed", "davinci", "babbage",
        "dall-e", "whisper", "tts", "rerank", "bge-", "deepseek-math", "deepseek-prover",
        "codegeex", "codestral", "devstral"
    ]

    /// 常见支持图片输入的命名特征（小写包含匹配）
    private static let visionIndicators: [String] = [
        "gpt-4o", "gpt-4.1", "gpt-4-turbo", "gpt-4v", "chatgpt-4o", "gpt-5", "o4-mini",
        "vl", "vision", "glm-4v", "glm-4.5v", "glm-4.6v", "multimodal", "mm-",
        "gemini", "claude", "pixtral", "internvl", "minicpm-v", "llava", "moondream",
        "gemma-3", "llama-3.2-90b", "llama-3.2-11b", "qwen2-vl", "qwen2.5-vl", "qvq"
    ]

    /// 启发式判断模型是否可能支持图片输入
    static func likelySupportsVision(modelID: String) -> Bool {
        let m = modelID.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !m.isEmpty else { return false }
        if knownTextOnlyPrefixes.contains(where: { m == $0 || m.hasPrefix($0) }) {
            return false
        }
        return visionIndicators.contains(where: { m.contains($0) })
    }

    /// 提示文案
    static func unsupportedHint(modelID: String) -> String {
        "当前模型「\(modelID)」可能不支持图片识别（多模态）。请在设置中选择多模态模型，例如 gpt-4o、glm-4v、qwen-vl 系列。"
    }
}
