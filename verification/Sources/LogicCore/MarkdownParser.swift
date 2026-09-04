import Foundation

// MARK: - Markdown 块级解析（纯逻辑，Linux 已测）

enum MarkdownBlock: Equatable {
    case heading(level: Int, text: String)
    case paragraph(text: String)
    case code(language: String, content: String)
    case quote(text: String)
    case listItem(indent: Int, ordinal: Int?, text: String)
    case divider
    case table(rows: [[String]])
}

enum MarkdownParser {

    static func parse(_ source: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        // 注意：Swift 中 "\r\n" 是单个字形簇（Character），
        // components(separatedBy: "\n") 匹配不到，必须按字形分割。
        let rawLines = source
            .split(omittingEmptySubsequences: false, whereSeparator: { $0 == "\n" || $0 == "\r" || $0 == "\r\n" })
            .map(String.init)
        var i = 0
        var paragraphBuffer: [String] = []

        func flushParagraph() {
            guard !paragraphBuffer.isEmpty else { return }
            let text = paragraphBuffer.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                blocks.append(.paragraph(text: text))
            }
            paragraphBuffer = []
        }

        func cleanLine(_ raw: String) -> String {
            raw.hasSuffix("\r") ? String(raw.dropLast()) : raw
        }

        while i < rawLines.count {
            let line = cleanLine(rawLines[i])
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // 空行：结束当前段落
            if trimmed.isEmpty {
                flushParagraph()
                i += 1
                continue
            }

            // 代码围栏
            if let fence = fenceInfo(trimmed) {
                flushParagraph()
                i += 1
                var codeLines: [String] = []
                while i < rawLines.count {
                    let inner = cleanLine(rawLines[i])
                    let innerTrimmed = inner.trimmingCharacters(in: .whitespaces)
                    if let closeFence = fenceInfo(innerTrimmed),
                       closeFence.marker == fence.marker,
                       closeFence.language.isEmpty {
                        i += 1
                        break
                    }
                    codeLines.append(inner)
                    i += 1
                }
                // 未闭合时吞到 EOF，同样视为代码块
                blocks.append(.code(language: fence.language, content: codeLines.joined(separator: "\n")))
                continue
            }

            // 标题
            if let heading = headingInfo(line) {
                flushParagraph()
                blocks.append(heading)
                i += 1
                continue
            }

            // 分割线
            if isHorizontalRule(trimmed) {
                flushParagraph()
                blocks.append(.divider)
                i += 1
                continue
            }

            // 引用块（连续行合并）
            if trimmed.hasPrefix(">") {
                flushParagraph()
                var quoteLines: [String] = []
                while i < rawLines.count {
                    let l = cleanLine(rawLines[i])
                    let t = l.trimmingCharacters(in: .whitespaces)
                    guard t.hasPrefix(">") else { break }
                    var content = String(t.dropFirst())
                    if content.hasPrefix(" ") { content.removeFirst() }
                    quoteLines.append(content)
                    i += 1
                }
                blocks.append(.quote(text: quoteLines.joined(separator: "\n")))
                continue
            }

            // 列表项（逐行）
            if let item = listItemInfo(line) {
                flushParagraph()
                blocks.append(item)
                i += 1
                continue
            }

            // 表格（连续行合并）
            if trimmed.hasPrefix("|") {
                flushParagraph()
                var rows: [[String]] = []
                while i < rawLines.count {
                    let l = cleanLine(rawLines[i])
                    let t = l.trimmingCharacters(in: .whitespaces)
                    guard t.hasPrefix("|") else { break }
                    let cells = tableCells(t)
                    if !isTableSeparatorRow(cells) {
                        rows.append(cells)
                    }
                    i += 1
                }
                if rows.isEmpty {
                    blocks.append(.paragraph(text: trimmed))
                } else {
                    blocks.append(.table(rows: rows))
                }
                continue
            }

            // 普通段落：连续普通行合并
            paragraphBuffer.append(line)
            i += 1
        }

        flushParagraph()
        return blocks
    }

    // MARK: 私有解析函数

    private struct FenceInfo {
        let marker: Character
        let language: String
    }

    private static func fenceInfo(_ trimmed: String) -> FenceInfo? {
        guard let first = trimmed.first, first == "`" || first == "~" else { return nil }
        var run = 0
        for ch in trimmed {
            if ch == first { run += 1 } else { break }
        }
        guard run >= 3 else { return nil }
        let language = String(trimmed.dropFirst(run)).trimmingCharacters(in: .whitespaces)
        return FenceInfo(marker: first, language: language)
    }

    private static func headingInfo(_ line: String) -> MarkdownBlock? {
        guard let first = line.first, first == "#" else { return nil }
        var level = 0
        for ch in line {
            if ch == "#" {
                level += 1
                if level > 6 { return nil }
            } else {
                break
            }
        }
        let rest = String(line.dropFirst(level))
        guard rest.hasPrefix(" ") || rest.isEmpty else { return nil }
        return .heading(level: level, text: rest.trimmingCharacters(in: .whitespaces))
    }

    private static func isHorizontalRule(_ trimmed: String) -> Bool {
        let chars = Array(trimmed)
        guard chars.count >= 3 else { return false }
        let c = chars[0]
        guard c == "-" || c == "*" || c == "_" else { return false }
        return chars.allSatisfy { $0 == c }
    }

    private static func listItemInfo(_ line: String) -> MarkdownBlock? {
        var spaces = 0
        for ch in line {
            if ch == " " { spaces += 1 } else { break }
        }
        let indent = min(spaces / 2, 3)
        let rest = String(line.dropFirst(spaces))
        guard !rest.isEmpty else { return nil }

        // 无序列表：- * + 后跟空格
        if let bullet = rest.first, bullet == "-" || bullet == "*" || bullet == "+" {
            let after = rest.dropFirst()
            if after.first == " " {
                let text = String(after).trimmingCharacters(in: .whitespaces)
                return .listItem(indent: indent, ordinal: nil, text: text)
            }
            return nil
        }

        // 有序列表：数字 + . 或 ) 后跟空格
        let digits = rest.prefix { $0.isNumber }
        if !digits.isEmpty, digits.count <= 9 {
            let afterDigits = rest.dropFirst(digits.count)
            if let mark = afterDigits.first, mark == "." || mark == ")" {
                let after = afterDigits.dropFirst()
                if after.first == " " {
                    let text = String(after).trimmingCharacters(in: .whitespaces)
                    let ordinal = Int(digits)
                    return .listItem(indent: indent, ordinal: ordinal, text: text)
                }
            }
        }
        return nil
    }

    private static func tableCells(_ line: String) -> [String] {
        var s = line
        if s.hasSuffix("|") { s.removeLast() }
        if s.hasPrefix("|") { s.removeFirst() }
        return s.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func isTableSeparatorRow(_ cells: [String]) -> Bool {
        guard !cells.isEmpty else { return false }
        return cells.allSatisfy { cell in
            var c = cell
            if c.hasPrefix(":") { c.removeFirst() }
            if c.hasSuffix(":") { c.removeLast() }
            return !c.isEmpty && c.allSatisfy { $0 == "-" }
        }
    }
}
