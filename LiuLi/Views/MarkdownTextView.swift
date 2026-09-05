import SwiftUI

// MARK: - Markdown 渲染（基于已测块级解析器；字号随「设置 → 消息字号」联动）

struct MarkdownTextView: View {
    let markdown: String
    /// 正文字号（标题/列表/引用在此基础上缩放）
    var size: CGFloat = 15

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
                .foregroundStyle(Color.textPrimary)
                .padding(.top, 2)

        case .paragraph(let text):
            InlineFormattedText(text: text, size: size, color: .textPrimary)

        case .code(let language, let content):
            CodeBlockView(language: language, content: content)

        case .quote(let text):
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(LinearGradient(colors: [Color.brand, Color.brand],
                                         startPoint: .top, endPoint: .bottom))
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

// MARK: - 行内格式（`code`、**bold**、*italic*）

struct InlineFormattedText: View {
    let text: String
    var size: CGFloat = 14
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
            part.foregroundColor = segment.code
                ? Color.brand
                : (segment.bold ? color : color)
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
            // 代码块头部（浅色 WorkBuddy 风：语言名 + 预览/复制小按钮）
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

            // 代码主体（浅底深字，横向滚动）
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
