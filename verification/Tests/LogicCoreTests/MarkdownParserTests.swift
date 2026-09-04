import XCTest
@testable import LogicCore

final class MarkdownParserTests: XCTestCase {

    func testHeadingLevels() {
        let blocks = MarkdownParser.parse("## 标题二\n### 标题三\n#一级无空格不是标题")
        XCTAssertEqual(blocks[0], .heading(level: 2, text: "标题二"))
        XCTAssertEqual(blocks[1], .heading(level: 3, text: "标题三"))
        XCTAssertEqual(blocks[2], .paragraph(text: "#一级无空格不是标题"))
    }

    func testHeadingLevel6Max() {
        XCTAssertEqual(MarkdownParser.parse("###### 六级").first, .heading(level: 6, text: "六级"))
        XCTAssertEqual(MarkdownParser.parse("####### 七级").first, .paragraph(text: "####### 七级"))
    }

    func testUnorderedList() {
        let blocks = MarkdownParser.parse("- 苹果\n* 香蕉\n+ 樱桃")
        XCTAssertEqual(blocks, [
            .listItem(indent: 0, ordinal: nil, text: "苹果"),
            .listItem(indent: 0, ordinal: nil, text: "香蕉"),
            .listItem(indent: 0, ordinal: nil, text: "樱桃")
        ])
    }

    func testOrderedListAndNesting() {
        let blocks = MarkdownParser.parse("1. 第一\n2. 第二\n   - 嵌套项")
        XCTAssertEqual(blocks[0], .listItem(indent: 0, ordinal: 1, text: "第一"))
        XCTAssertEqual(blocks[1], .listItem(indent: 0, ordinal: 2, text: "第二"))
        XCTAssertEqual(blocks[2], .listItem(indent: 1, ordinal: nil, text: "嵌套项"))
    }

    func testCodeFence() {
        let src = "前面\n```swift\nlet a = 1\nlet b = 2\n```\n后面"
        let blocks = MarkdownParser.parse(src)
        XCTAssertEqual(blocks.count, 3)
        XCTAssertEqual(blocks[1], .code(language: "swift", content: "let a = 1\nlet b = 2"))
    }

    func testUnclosedCodeFenceSwallowsToEOF() {
        let blocks = MarkdownParser.parse("```html\n<div>\n未闭合")
        XCTAssertEqual(blocks, [.code(language: "html", content: "<div>\n未闭合")])
    }

    func testTildeFence() {
        let blocks = MarkdownParser.parse("~~~\nabc\n~~~")
        XCTAssertEqual(blocks, [.code(language: "", content: "abc")])
    }

    func testQuoteBlockMergesLines() {
        let blocks = MarkdownParser.parse("> 第一行\n> 第二行\n普通文本")
        XCTAssertEqual(blocks[0], .quote(text: "第一行\n第二行"))
        XCTAssertEqual(blocks[1], .paragraph(text: "普通文本"))
    }

    func testDivider() {
        XCTAssertEqual(MarkdownParser.parse("前\n\n---\n\n后").contains(.divider), true)
        XCTAssertEqual(MarkdownParser.parse("***").first, .divider)
        XCTAssertEqual(MarkdownParser.parse("前\n--\n后").contains(.divider), false) // 两个字符不算
    }

    func testTable() {
        let src = "| 名称 | 值 |\n| --- | :---: |\n| a | 1 |\n| b | 2 |"
        let blocks = MarkdownParser.parse(src)
        guard case .table(let rows) = blocks.first else {
            return XCTFail("应为表格")
        }
        XCTAssertEqual(rows.count, 3) // 分隔行被剔除
        XCTAssertEqual(rows[0], ["名称", "值"])
        XCTAssertEqual(rows[2], ["b", "2"])
    }

    func testParagraphMerging() {
        let blocks = MarkdownParser.parse("第一行\n第二行\n\n新段落")
        XCTAssertEqual(blocks, [.paragraph(text: "第一行\n第二行"), .paragraph(text: "新段落")])
    }

    func testCRLFLineEndings() {
        let blocks = MarkdownParser.parse("# 标题\r\n\r\n- 甲\r\n- 乙\r\n")
        XCTAssertEqual(blocks, [.heading(level: 1, text: "标题"), .listItem(indent: 0, ordinal: nil, text: "甲"), .listItem(indent: 0, ordinal: nil, text: "乙")])
    }

    func testEmptyInput() {
        XCTAssertEqual(MarkdownParser.parse(""), [])
        XCTAssertEqual(MarkdownParser.parse("\n\n  \n"), [])
    }
}
