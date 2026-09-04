import SwiftUI

// MARK: - Markdown 渲染（基于已测块级解析器）

struct MarkdownTextView: View {
    let markdown: String

    var body: some View {
        let blocks = MarkdownParser.parse(markdown)
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
                .foregroundStyle(.white)
                .padding(.top, 2)

        case .paragraph(let text):
            InlineFormattedText(text: text, size: 15)

        case .code(let language, let content):
            CodeBlockView(language: language, content: content)

        case .quote(let text):
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(LinearGradient(colors: [Color.liuliTeal, Color.liuliIndigo],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: 3)
                InlineFormattedText(text: text, size: 13, color: Color.liuliTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

        case .listItem(let indent, let ordinal, let text):
            HStack(alignment: .top, spacing: 7) {
                Text(ordinal.map { "\($0)." } ?? "•")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.liuliAccent)
                    .frame(minWidth: 16, alignment: .trailing)
                InlineFormattedText(text: text, size: 14)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, CGFloat(indent) * 16)

        case .divider:
            Rectangle()
                .fill(Color.white.opacity(0.12))
                .frame(height: 0.6)
                .padding(.vertical, 3)

        case .table(let rows):
            MarkdownTableView(rows: rows)
        }
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: return .system(size: 20, weight: .bold)
        case 2: return .system(size: 18, weight: .bold)
        case 3: return .system(size: 16, weight: .semibold)
        default: return .system(size: 15, weight: .semibold)
        }
    }
}

// MARK: - 行内格式（`code`、**bold**、*italic*）

struct InlineFormattedText: View {
    let text: String
    var size: CGFloat = 14
    var color: Color = .white

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
            part.foregroundColor = segment.code
                ? Color.liuliAccent
                : (segment.bold ? color : color)
            if segment.code {
                part.backgroundColor = Color.white.opacity(0.08)
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
            // 行内代码
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
            // 粗体
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
            // 斜体（单星，要求左右有内容）
            if ch == "*" {
                let next = input.index(after: i)
                if next < input.endIndex, input[next] != "*" {
                    if let close = input[next...].firstIndex(of: "*") {
                        // 单星斜体：内容非空且收尾不与粗体混淆
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

// MARK: - 代码块（复制 / 保存 / HTML 预览）

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
            // 代码块头部
            HStack {
                Text(language.isEmpty ? "code" : language)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.liuliTextTertiary)
                Spacer()

                if isHTML {
                    Button {
                        showPreview = true
                    } label: {
                        Label("预览", systemImage: "play.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.liuliAccent)
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 6)
                }

                Button {
                    UIPasteboard.general.string = content
                    withAnimation { copied = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                        withAnimation { copied = false }
                    }
                } label: {
                    Label(copied ? "已复制" : "复制", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(copied ? Color.liuliTeal : Color.liuliTextSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.05))

            // 代码主体
            ScrollView(.horizontal, showsIndicators: false) {
                Text(content)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Color(red: 0.92, green: 0.95, blue: 1.0))
                    .textSelection(.enabled)
                    .padding(12)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(red: 0.02, green: 0.03, blue: 0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
        )
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
                            color: rowIndex == 0 ? Color.liuliAccent : Color.liuliTextPrimary
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 7)
                        .background(rowIndex == 0 ? Color.white.opacity(0.06) : Color.clear)
                    }
                }
                if rowIndex < rows.count - 1 {
                    Rectangle().fill(Color.white.opacity(0.07)).frame(height: 0.5)
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
