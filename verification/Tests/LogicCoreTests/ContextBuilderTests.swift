import XCTest
@testable import LogicCore

final class ContextBuilderTests: XCTestCase {

    private func makeOptions() -> ContextBuildOptions {
        ContextBuildOptions(
            liteSystemPrompt: "LITE_SYS",
            deepSystemPrompt: "DEEP_SYS"
        )
    }

    private func msg(_ role: MessageRole, _ text: String = "", images: [String] = [], toolCalls: [ToolCallInfo] = [], toolCallID: String? = nil) -> ChatMessage {
        ChatMessage(role: role, text: text, images: images, toolCalls: toolCalls, toolCallID: toolCallID)
    }

    func testBasicLiteContext() {
        let msgs = [msg(.user, "你好"), msg(.assistant, "你好！")]
        let ctx = ContextBuilder.buildContext(messages: msgs, mode: .lite, options: makeOptions())
        XCTAssertEqual(ctx.count, 3)
        XCTAssertEqual(ctx[0].role, "system")
        XCTAssertEqual(ctx[1].content, .text("你好"))
        XCTAssertEqual(ctx[2].content, .text("你好！"))
    }

    func testLiteStripsHistoryImagesButKeepsLast() {
        let img1 = "data:image/jpeg;base64,AAA"
        let img2 = "data:image/jpeg;base64,BBB"
        let msgs = [
            msg(.user, "第一张", images: [img1]),
            msg(.assistant, "收到"),
            msg(.user, "第二张", images: [img2])
        ]
        let ctx = ContextBuilder.buildContext(messages: msgs, mode: .lite, options: makeOptions())

        guard case .parts(let p1)? = ctx[1].content else { return XCTFail("应为 parts") }
        XCTAssertFalse(p1.contains { $0.type == "image_url" }, "省流应剔除历史图片")

        guard case .parts(let p2)? = ctx[3].content else { return XCTFail("应为 parts") }
        XCTAssertTrue(p2.contains { $0.type == "image_url" && $0.image_url?.url == img2 }, "最后一条用户图片应保留")
    }

    func testDeepKeepsAllImages() {
        let img = "data:image/jpeg;base64,AAA"
        let msgs = [msg(.user, "图", images: [img]), msg(.assistant, "好"), msg(.user, "再来")]
        let ctx = ContextBuilder.buildContext(messages: msgs, mode: .deep, options: makeOptions())
        guard case .parts(let p)? = ctx[1].content else { return XCTFail() }
        XCTAssertEqual(p.count, 2)
    }

    func testLiteWindowTrimsHistory() {
        var msgs: [ChatMessage] = [msg(.user, "0")]
        for i in 1...20 {
            msgs.append(msg(.assistant, "a\(i)"))
            msgs.append(msg(.user, "u\(i)"))
        }
        let ctx = ContextBuilder.buildContext(messages: msgs, mode: .lite, options: makeOptions())
        XCTAssertEqual(ctx.count, 1 + 8, "系统提示 + 最近 8 条")
        XCTAssertEqual(ctx.last?.content, .text("u20"))
        XCTAssertEqual(ctx[ctx.count - 2].content, .text("a20"))
    }

    func testToolCallProtocolRoundTrip() {
        let call = ToolCallInfo(id: "call_x", name: "write_file", arguments: "{\"path\":\"a.txt\"}")
        let msgs = [
            msg(.user, "帮我写文件"),
            msg(.assistant, "", toolCalls: [call]),
            msg(.tool, "已写入 a.txt", toolCalls: [], toolCallID: "call_x"),
            msg(.assistant, "完成了")
        ]
        let ctx = ContextBuilder.buildContext(messages: msgs, mode: .deep, options: makeOptions())

        XCTAssertEqual(ctx.count, 5)
        XCTAssertEqual(ctx[2].tool_calls?.first?.id, "call_x")
        XCTAssertNil(ctx[2].content, "空文本 assistant 的 content 应为 nil")
        XCTAssertEqual(ctx[3].role, "tool")
        XCTAssertEqual(ctx[3].tool_call_id, "call_x")
        XCTAssertEqual(ctx[3].content, .text("已写入 a.txt"))
    }

    func testSanitizeRemovesDanglingToolCalls() {
        // 模拟流式中断：assistant 带 tool_calls 但没有 tool 结果
        let call = ToolCallInfo(id: "c1", name: "read_file", arguments: "{}")
        let msgs = [
            msg(.user, "看看文件"),
            msg(.assistant, "", toolCalls: [call]) // 悬空
        ]
        let cleaned = ContextBuilder.sanitize(msgs)
        XCTAssertEqual(cleaned.map { $0.role }, [MessageRole.user], "悬空 assistant 应被移除")

        let ctx = ContextBuilder.buildContext(messages: msgs, mode: .deep, options: makeOptions())
        XCTAssertEqual(ctx.count, 2, "系统 + user，悬空 assistant 不参与")
    }

    func testSanitizeKeepsCompleteToolCycle() {
        let call = ToolCallInfo(id: "c1", name: "read_file", arguments: "{}")
        let msgs = [
            msg(.user, "看"),
            msg(.assistant, "", toolCalls: [call]),
            msg(.tool, "内容 ABC", toolCallID: "c1"),
            msg(.assistant, "文件内容是 ABC")
        ]
        let cleaned = ContextBuilder.sanitize(msgs)
        XCTAssertEqual(cleaned.count, 4)
    }

    func testSanitizeDropsDanglingToolResult() {
        let msgs = [
            msg(.user, "看"),
            msg(.tool, "孤儿结果", toolCallID: "ghost")
        ]
        let cleaned = ContextBuilder.sanitize(msgs)
        XCTAssertEqual(cleaned.map { $0.role }, [MessageRole.user])
    }

    func testNoteMessagesExcluded() {
        let msgs = [msg(.user, "hi"), msg(.note, "本地提示"), msg(.assistant, "hey")]
        let ctx = ContextBuilder.buildContext(messages: msgs, mode: .lite, options: makeOptions())
        XCTAssertEqual(ctx.count, 3)
        XCTAssertFalse(ctx.contains { $0.role == "note" })
    }
}
