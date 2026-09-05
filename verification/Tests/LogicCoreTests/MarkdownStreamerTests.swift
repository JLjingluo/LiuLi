import XCTest
@testable import LogicCore

// MARK: - 流式切分（稳定前缀 + 增量尾部）
// 对应 App 内 MarkdownTextView 的流式防抖逻辑：完整块缓存解析、半闭合结构走纯文本。

final class MarkdownStreamerTests: XCTestCase {

    func testNoBlankLine_AllTail() {
        let (stable, tail) = MarkdownStreamer.splitStablePrefix("正在输出的单行")
        XCTAssertEqual(stable, "")
        XCTAssertEqual(tail, "正在输出的单行")
    }

    func testBlankLine_SplitsAtLastBoundary() {
        let src = "第一段。\n\n第二段。\n\n第三段正在写"
        let (stable, tail) = MarkdownStreamer.splitStablePrefix(src)
        XCTAssertEqual(stable, "第一段。\n\n第二段。")
        XCTAssertEqual(tail, "第三段正在写")
    }

    func testTrailingBlankLine_EmptyTail() {
        let (stable, tail) = MarkdownStreamer.splitStablePrefix("完整段。\n\n")
        XCTAssertEqual(stable, "完整段。")
        XCTAssertEqual(tail, "")
    }

    func testUnclosedFenceAtStart_AllTail() {
        // 开头就是一个未闭合代码块：全文按增量处理（绝不解析半个代码块）
        let src = "```swift\nlet a = 1\n\nlet b = 2"
        let (stable, tail) = MarkdownStreamer.splitStablePrefix(src)
        XCTAssertEqual(stable, "")
        XCTAssertEqual(tail, src)
    }

    func testFenceClosedBeforeBoundary_StableKept() {
        let src = "说明：\n\n```swift\nlet a = 1\n```\n\n后续正在写"
        let (stable, tail) = MarkdownStreamer.splitStablePrefix(src)
        XCTAssertEqual(stable, "说明：\n\n```swift\nlet a = 1\n```")
        XCTAssertEqual(tail, "后续正在写")
    }

    func testUnclosedFenceAfterStableText_StablePrefixPreserved() {
        // 代码块之前的完整段落仍是稳定前缀，只有代码块部分走增量
        let src = "先说结论。\n\n```python\nprint(1)\n\nprint(2)"
        let (stable, tail) = MarkdownStreamer.splitStablePrefix(src)
        XCTAssertEqual(stable, "先说结论。")
        XCTAssertEqual(tail, "```python\nprint(1)\n\nprint(2)")
    }

    func testHasUnclosedFence() {
        XCTAssertFalse(MarkdownStreamer.hasUnclosedFence("无代码"))
        XCTAssertFalse(MarkdownStreamer.hasUnclosedFence("```\nx\n```"))
        XCTAssertTrue(MarkdownStreamer.hasUnclosedFence("```swift\nlet a = 1"))
        XCTAssertTrue(MarkdownStreamer.hasUnclosedFence("~~~\nabc"))
        XCTAssertFalse(MarkdownStreamer.hasUnclosedFence("~~~\nabc\n~~~"))
    }
}
