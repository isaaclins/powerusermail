import SwiftUI
import WebKit

struct WebView: NSViewRepresentable {
    let htmlContent: String
    var darkMode: Bool = false

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        let styledHTML = wrapWithStyling(htmlContent)
        nsView.loadHTMLString(styledHTML, baseURL: nil)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            if navigationAction.navigationType == .linkActivated,
                let url = navigationAction.request.url,
                shouldOpenExternally(url: url)
            {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }

            decisionHandler(.allow)
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            // Handles target="_blank" links.
            if let url = navigationAction.request.url, shouldOpenExternally(url: url) {
                NSWorkspace.shared.open(url)
            }
            return nil
        }

        private func shouldOpenExternally(url: URL) -> Bool {
            guard let scheme = url.scheme?.lowercased() else { return false }
            switch scheme {
            case "http", "https", "mailto", "tel":
                return true
            default:
                return false
            }
        }
    }

    private func wrapWithStyling(_ content: String) -> String {
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua

        let bgColor = isDark ? "#1e1e1e" : "#ffffff"
        let textColor = isDark ? "#e4e4e4" : "#1a1a1a"
        let linkColor = isDark ? "#6cb6ff" : "#0066cc"
        let codeBlockBg = isDark ? "#2d2d2d" : "#f5f5f5"
        let codeBorder = isDark ? "#404040" : "#e0e0e0"
        let blockquoteBorder = isDark ? "#4a9eff" : "#0066cc"
        let blockquoteBg = isDark ? "rgba(74, 158, 255, 0.1)" : "rgba(0, 102, 204, 0.05)"

        return """
            <!DOCTYPE html>
            <html>
            <head>
                <meta charset="UTF-8">
                <meta name="viewport" content="width=device-width, initial-scale=1.0">
                <style>
                    * {
                        box-sizing: border-box;
                    }
                    
                    body {
                        font-family: -apple-system, BlinkMacSystemFont, 'SF Pro Text', 'Helvetica Neue', sans-serif;
                        font-size: 14px;
                        line-height: 1.6;
                        color: \(textColor);
                        background-color: \(bgColor);
                        margin: 0;
                        padding: 16px;
                        word-wrap: break-word;
                        overflow-wrap: break-word;
                    }
                    
                    h1, h2, h3, h4, h5, h6 {
                        margin-top: 1.5em;
                        margin-bottom: 0.5em;
                        font-weight: 600;
                        line-height: 1.3;
                    }
                    
                    h1 { font-size: 1.75em; }
                    h2 { font-size: 1.5em; }
                    h3 { font-size: 1.25em; }
                    h4 { font-size: 1.1em; }
                    
                    p {
                        margin: 0.75em 0;
                    }
                    
                    a {
                        color: \(linkColor);
                        text-decoration: none;
                    }
                    
                    a:hover {
                        text-decoration: underline;
                    }
                    
                    img {
                        max-width: 100%;
                        height: auto;
                        border-radius: 8px;
                    }
                    
                    pre {
                        background-color: \(codeBlockBg);
                        border: 1px solid \(codeBorder);
                        border-radius: 8px;
                        padding: 12px 16px;
                        overflow-x: auto;
                        font-family: 'SF Mono', Menlo, Monaco, 'Courier New', monospace;
                        font-size: 13px;
                        line-height: 1.5;
                    }
                    
                    code {
                        font-family: 'SF Mono', Menlo, Monaco, 'Courier New', monospace;
                        font-size: 0.9em;
                        background-color: \(codeBlockBg);
                        padding: 2px 6px;
                        border-radius: 4px;
                    }
                    
                    pre code {
                        background: none;
                        padding: 0;
                    }
                    
                    blockquote {
                        margin: 1em 0;
                        padding: 12px 16px;
                        border-left: 4px solid \(blockquoteBorder);
                        background-color: \(blockquoteBg);
                        border-radius: 0 8px 8px 0;
                    }
                    
                    blockquote p {
                        margin: 0;
                    }
                    
                    ul, ol {
                        padding-left: 1.5em;
                        margin: 0.75em 0;
                    }
                    
                    li {
                        margin: 0.25em 0;
                    }
                    
                    table {
                        border-collapse: collapse;
                        width: 100%;
                        margin: 1em 0;
                    }
                    
                    th, td {
                        border: 1px solid \(codeBorder);
                        padding: 8px 12px;
                        text-align: left;
                    }
                    
                    th {
                        background-color: \(codeBlockBg);
                        font-weight: 600;
                    }
                    
                    hr {
                        border: none;
                        border-top: 1px solid \(codeBorder);
                        margin: 1.5em 0;
                    }
                    
                    /* Gmail-specific cleanup */
                    .gmail_quote {
                        color: \(isDark ? "#888" : "#666");
                        border-left: 2px solid \(codeBorder);
                        padding-left: 12px;
                        margin-top: 1em;
                    }
                    
                    /* Outlook-specific cleanup */
                    .MsoNormal {
                        margin: 0;
                    }
                </style>
            </head>
            <body>
                \(content)
            </body>
            </html>
            """
    }
}

// MARK: - Markdown to HTML Converter
struct MarkdownRenderer {
    static func toHTML(_ markdown: String) -> String {
        var html = markdown

        // Escape HTML entities first (but preserve existing HTML tags)
        // This is a simplified approach - for complex content, consider using a proper Markdown library

        // Headers
        html = html.replacingOccurrences(
            of: "(?m)^### (.+)$", with: "<h3>$1</h3>", options: .regularExpression)
        html = html.replacingOccurrences(
            of: "(?m)^## (.+)$", with: "<h2>$1</h2>", options: .regularExpression)
        html = html.replacingOccurrences(
            of: "(?m)^# (.+)$", with: "<h1>$1</h1>", options: .regularExpression)

        // Bold and Italic
        html = html.replacingOccurrences(
            of: "\\*\\*\\*(.+?)\\*\\*\\*", with: "<strong><em>$1</em></strong>",
            options: .regularExpression)
        html = html.replacingOccurrences(
            of: "\\*\\*(.+?)\\*\\*", with: "<strong>$1</strong>", options: .regularExpression)
        html = html.replacingOccurrences(
            of: "\\*(.+?)\\*", with: "<em>$1</em>", options: .regularExpression)
        html = html.replacingOccurrences(
            of: "__(.+?)__", with: "<strong>$1</strong>", options: .regularExpression)
        html = html.replacingOccurrences(
            of: "_(.+?)_", with: "<em>$1</em>", options: .regularExpression)

        // Inline code
        html = html.replacingOccurrences(
            of: "`([^`]+)`", with: "<code>$1</code>", options: .regularExpression)

        // Links
        html = html.replacingOccurrences(
            of: "\\[([^\\]]+)\\]\\(([^)]+)\\)", with: "<a href=\"$2\">$1</a>",
            options: .regularExpression)

        // Line breaks
        html = html.replacingOccurrences(of: "\n\n", with: "</p><p>")
        html = html.replacingOccurrences(of: "\n", with: "<br>")

        // Wrap in paragraph if not already HTML
        if !html.contains("<p>") && !html.contains("<div>") && !html.contains("<h") {
            html = "<p>\(html)</p>"
        }

        return html
    }

    static func isLikelyHTML(_ content: String) -> Bool {
        let htmlTags = [
            "<html", "<body", "<div", "<p>", "<br", "<table", "<span", "<img", "<a href",
        ]
        return htmlTags.contains { content.lowercased().contains($0) }
    }
}
