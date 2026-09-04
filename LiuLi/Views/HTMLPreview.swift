import SwiftUI
import WebKit

// MARK: - WKWebView 封装（HTML 实时预览，支持同目录相对资源）

struct HTMLWebView: UIViewRepresentable {
    /// 文件 URL 模式：loadFileURL，允许读取同目录资源（css/js/图片）
    var fileURL: URL?
    /// 纯字符串模式：直接渲染 HTML 文本
    var htmlString: String?

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        if let fileURL {
            // allowingReadAccessTo 同目录 → 相对引用的 css/js 生效
            let dir = fileURL.deletingLastPathComponent()
            webView.loadFileURL(fileURL, allowingReadAccessTo: dir)
        } else if let htmlString {
            webView.loadHTMLString(baseHTML(htmlString), baseURL: nil)
        }
    }

    /// 注入深色友好的基础样式与视口
    private func baseHTML(_ html: String) -> String {
        if html.lowercased().contains("<html") {
            return html
        }
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <style>
        body { font-family: -apple-system, sans-serif; padding: 16px;
               background: #0b0d18; color: #e8eaf2; }
        </style>
        </head>
        <body>\(html)</body>
        </html>
        """
    }
}

// MARK: - HTML 预览浮层

struct HTMLPreviewSheet: View {
    let title: String
    /// 二选一：文件预览传 fileURL；代码块预览传 html
    var fileURL: URL? = nil
    var html: String? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var reloadToken = UUID()

    var body: some View {
        NavigationStack {
            Group {
                if let fileURL {
                    HTMLWebView(fileURL: fileURL, htmlString: nil)
                        .id(reloadToken)
                } else if let html {
                    HTMLWebView(fileURL: nil, htmlString: html)
                        .id(reloadToken)
                }
            }
            .background(Color.appBackground)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { dismiss() }
                        .foregroundStyle(Color.liuliAccent)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        reloadToken = UUID()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .foregroundStyle(Color.liuliAccent)
                    }
                }
            }
        }
    }
}
