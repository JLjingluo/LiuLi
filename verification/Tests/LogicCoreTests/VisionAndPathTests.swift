import XCTest
@testable import LogicCore

final class VisionCapabilityTests: XCTestCase {

    func testKnownVisionModels() {
        for m in ["gpt-4o", "gpt-4o-mini", "gpt-4o-2024-11-20", "gpt-4.1", "gpt-4-turbo",
                  "claude-3-5-sonnet", "gemini-2.0-flash", "glm-4v-plus", "glm-4.5v",
                  "qwen-vl-max", "qwen2.5-vl-72b-instruct", "llava-1.5-7b", "minicpm-v-2.6"] {
            XCTAssertTrue(VisionCapability.likelySupportsVision(modelID: m), "应识别为支持视觉：\(m)")
        }
    }

    func testKnownTextOnlyModels() {
        for m in ["deepseek-chat", "deepseek-reasoner", "deepseek-v3", "gpt-3.5-turbo",
                  "o1-mini", "text-embedding-3-small", "deepseek-coder-v2"] {
            XCTAssertFalse(VisionCapability.likelySupportsVision(modelID: m), "应识别为纯文本：\(m)")
        }
    }

    func testUnknownModelIsConservativelyTextOnly() {
        XCTAssertFalse(VisionCapability.likelySupportsVision(modelID: "my-custom-model"))
        XCTAssertFalse(VisionCapability.likelySupportsVision(modelID: ""))
    }

    func testHintMentionsModelName() {
        let hint = VisionCapability.unsupportedHint(modelID: "deepseek-chat")
        XCTAssertTrue(hint.contains("deepseek-chat"))
        XCTAssertTrue(hint.contains("多模态"))
    }
}

final class PathSecurityRegressionTests: XCTestCase {

    func testCaseInsensitiveBlacklistBypass() {
        // iOS 文件系统不区分大小写：conversations 应同样被拦截
        XCTAssertNil(PathResolver.resolve(root: URL(fileURLWithPath: "/tmp/r"), relative: "Conversations/a.json", blockedTopLevel: ["Conversations"]))
        XCTAssertNil(PathResolver.resolve(root: URL(fileURLWithPath: "/tmp/r"), relative: "conversations/a.json", blockedTopLevel: ["Conversations"]))
        XCTAssertNil(PathResolver.resolve(root: URL(fileURLWithPath: "/tmp/r"), relative: "CONVERSATIONS/a.json", blockedTopLevel: ["Conversations"]))
    }

    func testNullByteRejected() {
        XCTAssertNil(PathResolver.resolve(root: URL(fileURLWithPath: "/tmp/r"), relative: "a\0b", blockedTopLevel: []))
    }

    func testTildeRejected() {
        XCTAssertNil(PathResolver.resolve(root: URL(fileURLWithPath: "/tmp/r"), relative: "~/Library/x", blockedTopLevel: []))
        XCTAssertNil(PathResolver.resolve(root: URL(fileURLWithPath: "/tmp/r"), relative: "~", blockedTopLevel: []))
    }
}

final class CostAndModeTests: XCTestCase {

    func testModeDisplayNames() {
        XCTAssertEqual(ChatMode.lite.displayName, "快速模式")
        XCTAssertEqual(ChatMode.deep.displayName, "深度模式")
    }

    func testCostYuanCalculation() {
        // 1M 输入 tokens × ¥2/M + 0.5M 输出 tokens × ¥8/M = ¥6
        let usage = UsageInfo(promptTokens: 1_000_000, completionTokens: 500_000)
        XCTAssertEqual(usage.costYuan(inputPerM: 2, outputPerM: 8), 6, accuracy: 0.000001)
        // 空用量
        let empty = UsageInfo(promptTokens: 0, completionTokens: 0)
        XCTAssertEqual(empty.costYuan(inputPerM: 2, outputPerM: 8), 0)
    }

    func testCostTextFormatting() {
        XCTAssertEqual(UsageInfo.costText(0), "¥0")
        XCTAssertEqual(UsageInfo.costText(1.05), "¥1.05")
        XCTAssertEqual(UsageInfo.costText(1.5), "¥1.5")
        XCTAssertEqual(UsageInfo.costText(0.012345), "¥0.0123")   // ≥0.01 → 4 位精度
        XCTAssertEqual(UsageInfo.costText(0.001234), "¥0.001234") // <0.01 → 6 位精度
        XCTAssertEqual(UsageInfo.costText(0.01), "¥0.01")
        // 尾零去除：0.500000 → 0.5
        XCTAssertEqual(UsageInfo.costText(0.5), "¥0.5")
    }
}
