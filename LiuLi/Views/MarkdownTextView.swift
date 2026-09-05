import SwiftUI

// MARK: - Markdown 渲染 v3（块级缓存 + 稳定增量 + 流式光标）
//
// DeepSeek 式流畅的关键：流式中途不重排。
// - 静态消息：解析一次并缓存（@State 引用型缓存，body 重算零成本）
// - 流式消息：文本切成「稳定前缀（完整块，缓存解析）」+「增量尾部（纯文本 + 闪烁光标）」，
//   半闭合的代码块/标题/列表在尾部按纯文本直出，绝不反复横跳。
// - 光标：品牌色 ▍，0.53s 呼吸闪烁（TimelineView 驱动，布局宽度恒定不跳动）

struct MarkdownTextView: View {
    let markdown: String
    /// 正文字号（标题/列表/引用在此基础上缩放）
    var size: CGFloat = 16
    /// 是否正在流式生成（true 时尾部增量以纯文本直出，防抖）
    var isStreaming: Bool = false

    var body: some View {
        if isStreaming {
            StreamingMarkdownBody(markdown: markdown, size: size)
        } else {
            StaticMarkdownBody(markdown: markdown, size: size)
        }
    }
}

// MARK: - 解析缓存（引用型 @State：body 重算不触发视图更新，合法且零成本）

private final class MarkdownParseCache {
    private var source = ""
    private var blocks: [MarkdownBlock] = []

    func blocks(for markdown: String) -> [MarkdownBlock] {
        if source == markdown { return blocks }
        source = markdown
        blocks = MarkdownParser.parse(markdown)
        return blocks
    }
}

// MARK: - 静态渲染（完整 Markdown，解析一次缓存）

private struct StaticMarkdownBody: View {
    let markdown: String
    let size: CGFloat
    @State private var cache = MarkdownParseCache()

    var body: some View {
        MarkdownBlocksView(blocks: cache.blocks(for: markdown), size: size)
    }
}

// MARK: - 流式渲染（稳定前缀缓存解析 + 尾部纯文本 + 光标）

private struct StreamingMarkdownBody: View {
    let markdown: String
    let size: CGFloat
    @State private var cache = MarkdownParseCache()

    var body: some View {
        let (stable, tail) = MarkdownTextView.splitStablePrefix(markdown)
        VStack(alignment: .leading, spacing: 10) {
            if !stable.isEmpty {
                MarkdownBlocksView(blocks: cache.blocks(for: stable), size: size)
            }
            if !tail.isEmpty {
                StreamingTailView(tail: tail, size: size)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 流式尾部：纯文本直出（无解析、零重排）+ 品牌色闪烁光标
private struct StreamingTailView: View {
    let tail: String
    let size: CGFloat

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.53)) { context in
            let cursorOn = Int(context.date.timeIntervalSince1970 / 0.53) % 2 == 0
            Text(attributed(cursorOn: cursorOn))
                .font(.system(size: size))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func attributed(cursorOn: Bool) -> AttributedString {
        var text = AttributedString(tail)
        text.foregroundColor = .textPrimary
        var cursor = AttributedString("▍")
        cursor.foregroundColor = cursorOn ? Color.brand : Color.brand.opacity(0.12)
        cursor.font = .system(size: size)
        return text + cursor
    }
}

// MARK: - 块列表渲染（静态/流式共用）

private struct MarkdownBlocksView: View {
    let blocks: [MarkdownBlock]
    let size: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(text)
                .font(headingFont(level))
                .foregroundStyle(Color.textPrimary)
                .padding(.top, 2)

        case .paragraph(let text):
            InlineFormattedText(text: text, size: size, color: .textPrimary)

        case .code(let language, let content):
            CodeBlockView(language: language, content: content)

        case .quote(let text):
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.brand)
                    .frame(width: 3)
                InlineFormattedText(text: text, size: size - 2, color: .textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

        case .listItem(let indent, let ordinal, let text):
            HStack(alignment: .top, spacing: 7) {
                Text(ordinal.map { "\($0)." } ?? "•")
                    .font(.system(size: size - 1, weight: .semibold))
                    .foregroundStyle(Color.brand)
                    .frame(minWidth: 16, alignment: .trailing)
                InlineFormattedText(text: text, size: size - 1, color: .textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, CGFloat(indent) * 16)

        case .divider:
            Rectangle()
                .fill(Color.separator)
                .frame(height: 0.6)
                .padding(.vertical, 3)

        case .table(let rows):
            MarkdownTableView(rows: rows)
        }
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: return .system(size: size + 5, weight: .bold)
        case 2: return .system(size: size + 3, weight: .bold)
        case 3: return .system(size: size + 1, weight: .semibold)
        default: return .system(size: size, weight: .semibold)
        }
    }
}

// MARK: - 流式文本切分（纯逻辑实现见 MarkdownParser.swift 的 MarkdownStreamer，Linux 已测）

extension MarkdownTextView {

    /// 把流式文本切成「稳定前缀（完整块）」+「增量尾部」。
    static func splitStablePrefix(_ source: String) -> (stable: String, tail: String) {
        MarkdownStreamer.splitStablePrefix(source)
    }
}

// MARK: - 行内格式（`code`、**bold**、*italic*）

struct InlineFormattedText: View {
    let text: String
    var size: CGFloat = 15
    var color: Color = .textPrimary

    var body: some View {
        Text(attributed)
    }

    private var attributed: AttributedString {
        var result = AttributedString()
        let segments = Self.parseSegments(text)
        for segment in segments {
            var part = AttributedString(segment.text)
            part.font = .system(size: size, weight: segment.bold ? .semibold : .regular,
                               design: segment.code ? .monospaced : .default)
            part.foregroundColor = segment.code ? Color.brand : color
            if segment.code {
                part.backgroundColor = Color.textPrimary.opacity(0.07)
            }
            if segment.italic && !segment.bold {
                part.font = .system(size: size).italic()
            }
            result += part
        }
        if result.characters.isEmpty {
            result = AttributedString(text)
            result.font = .system(size: size)
            result.foregroundColor = color
        }
        return result
    }

    struct Segment {
        var text: String
        var bold = false
        var italic = false
        var code = false
    }

    /// 轻量行内解析：`code` 优先，其次 **bold**，再次 *italic*
    static func parseSegments(_ input: String) -> [Segment] {
        var segments: [Segment] = []
        var current = ""
        var i = input.startIndex

        func flush() {
            guard !current.isEmpty else { return }
            segments.append(Segment(text: current))
            current = ""
        }

        while i < input.endIndex {
            let ch = input[i]
            if ch == "`" {
                if let close = input.index(i, offsetBy: 1, limitedBy: input.endIndex),
                   let end = input[close...].firstIndex(of: "`") {
                    flush()
                    let content = String(input[close..<end])
                    segments.append(Segment(text: content, code: true))
                    i = input.index(after: end)
                    continue
                }
            }
            if ch == "*", input[i...].hasPrefix("**") {
                let afterFirst = input.index(after: input.index(after: i))
                if let close = input.range(of: "**", range: afterFirst..<input.endIndex) {
                    flush()
                    let content = String(input[afterFirst..<close.lowerBound])
                    segments.append(Segment(text: content, bold: true))
                    i = close.upperBound
                    continue
                }
            }
            if ch == "*" {
                let next = input.index(after: i)
                if next < input.endIndex, input[next] != "*" {
                    if let close = input[next...].firstIndex(of: "*") {
                        let content = String(input[next..<close])
                        if !content.isEmpty && !content.hasPrefix("*") {
                            flush()
                            segments.append(Segment(text: content, italic: true))
                            i = input.index(after: close)
                            continue
                        }
                    }
                }
            }
            current.append(ch)
            i = input.index(after: i)
        }
        flush()
        return segments
    }
}

// MARK: - 代码块（复制 / HTML 预览）

struct CodeBlockView: View {
    let language: String
    let content: String

    @State private var copied = false
    @State private var showPreview = false

    private var isHTML: Bool {
        let lang = language.lowercased()
        if lang == "html" || lang == "htm" { return true }
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("<!DOCTYPE html") || trimmed.hasPrefix("<html")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                HStack(spacing: 5) {
                    Circle()
                        .fill(Color.brand)
                        .frame(width: 4.5, height: 4.5)
                    Text(language.isEmpty ? "code" : language)
                        .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.textSecondary)
                }
                Spacer()

                if isHTML {
                    Button {
                        Haptics.tap()
                        showPreview = true
                    } label: {
                        Label("预览", systemImage: "play.fill")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(Color.brand)
                    }
                    .buttonStyle(PressableButtonStyle(scale: 0.9))
                }

                Button {
                    UIPasteboard.general.string = content
                    Haptics.success()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { copied = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                        withAnimation { copied = false }
                    }
                } label: {
                    Label(copied ? "已复制" : "复制", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(copied ? Color.brand : Color.textTertiary)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(PressableButtonStyle(scale: 0.9))
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(Color.textPrimary.opacity(0.045))

            ScrollView(.horizontal, showsIndicators: false) {
                Text(content)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Color.textPrimary)
                    .textSelection(.enabled)
                    .padding(11)
            }
        }
        .liquidGlass(cornerRadius: 13, tinted: true)
        .sheet(isPresented: $showPreview) {
            HTMLPreviewSheet(title: "代码预览", html: content)
        }
    }
}

// MARK: - 表格

struct MarkdownTableView: View {
    let rows: [[String]]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                HStack(spacing: 0) {
                    ForEach(Array(row.enumerated()), id: \.offset) { colIndex, cell in
                        InlineFormattedText(
                            text: cell,
                            size: 12,
                            color: rowIndex == 0 ? Color.brand : Color.textPrimary
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 7)
                        .background(rowIndex == 0 ? Color.textPrimary.opacity(0.05) : Color.clear)
                    }
                }
                if rowIndex < rows.count - 1 {
                    Rectangle().fill(Color.separator).frame(height: 0.5)
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.separator, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
