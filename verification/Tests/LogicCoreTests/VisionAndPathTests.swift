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
