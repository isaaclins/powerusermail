import Foundation
import WebKit
import SwiftUI

/// Pools WKWebViews and sanitizes/stylizes HTML bodies for chats.
final class MessageRenderEngine: NSObject {
    static let shared = MessageRenderEngine()

    let pool = WebViewPool(maxSize: 3)

    private override init() {
        super.init()
    }

    // MARK: - Public API

    func isSimple(_ body: String) -> Bool {
        let lower = body.lowercased()
        let richMarkers = ["<div", "<table", "<html", "<body", "<style", "<img", "<iframe", "<head"]
        return !richMarkers.contains(where: { lower.contains($0) })
    }

    func prepareHTML(_ raw: String, allowRemoteImages: Bool, isDark: Bool, fontSize: Double) -> String {
        let cleaned = sanitize(raw, allowRemoteImages: allowRemoteImages)
        return wrapWithTheme(cleaned, isDark: isDark, fontSize: fontSize)
    }

    // MARK: - Sanitization

    private func sanitize(_ html: String, allowRemoteImages: Bool) -> String {
        var output = html

        // Remove scripts
        output = output.replacingOccurrences(
            of: #"(?is)<script.*?</script>"#,
            with: "",
            options: [.regularExpression]
        )

        // Remove iframes
        output = output.replacingOccurrences(
            of: #"(?is)<iframe.*?</iframe>"#,
            with: "",
            options: [.regularExpression]
        )

        // Remove embedded object tags
        output = output.replacingOccurrences(
            of: #"(?is)<object.*?</object>"#,
            with: "",
            options: [.regularExpression]
        )

        if !allowRemoteImages {
            // Strip remote image sources but keep placeholders
            output = output.replacingOccurrences(
                of: "<img([^>]+?)src\\s*=\\s*\"([^\"]+)\"([^>]*)>",
                with: "<img$1data-src=\"$2\"$3 alt=\"Remote image blocked\" loading=\"lazy\">",
                options: [.regularExpression, .caseInsensitive]
            )
        }

        return output
    }

    private func wrapWithTheme(_ body: String, isDark: Bool, fontSize: Double) -> String {
        let textColor = isDark ? "#e8ebf5" : "#0f1116"
        let mutedColor = isDark ? "#b6bdc8" : "#4c5365"
        let linkColor = isDark ? "#7ec3ff" : "#0a84ff"
        let codeBg = isDark ? "rgba(255,255,255,0.08)" : "rgba(0,0,0,0.04)"
        let bg = "transparent"

        let css = """
        :root { color-scheme: \(isDark ? "dark" : "light"); }
        * { box-sizing: border-box; }
        html, body {
            margin: 0; padding: 0;
            background: \(bg) !important;
            color: \(textColor);
            font-family: -apple-system, 'SF Pro Text', 'Helvetica Neue', sans-serif;
            font-size: \(fontSize)px; line-height: 1.55;
            -webkit-font-smoothing: antialiased;
        }
        p { margin: 0.35em 0; }
        a { color: \(linkColor); text-decoration: none; }
        a:hover { text-decoration: underline; }
        img { max-width: 100%; height: auto; border-radius: 8px; }
        blockquote {
            border-left: 3px solid \(linkColor);
            margin: 0.6em 0; padding-left: 10px;
            color: \(mutedColor);
        }
        pre, code {
            font-family: 'SF Mono', Menlo, monospace;
            background: \(codeBg);
            border-radius: 6px;
        }
        pre { padding: 10px; overflow-x: auto; }
        table { border-collapse: collapse; width: 100%; }
        td, th { border: 1px solid rgba(255,255,255,0.08); padding: 6px; }
        hr { border: none; border-top: 1px solid rgba(255,255,255,0.1); margin: 10px 0; }
        ul, ol { margin: 0.35em 0 0.35em 1.1em; }
        """

        return """
        <!doctype html>
        <html>
        <head>
            <meta charset=\"utf-8\">
            <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">
            <style>\(css)</style>
        </head>
        <body>\(body)</body>
        </html>
        """
    }
}

// MARK: - Pooling

final class WebViewPool {
    private let maxSize: Int
    private var pool: [WKWebView] = []
    private let lock = NSLock()

    init(maxSize: Int) {
        self.maxSize = maxSize
    }

    func checkout(allowJavaScript: Bool) -> WKWebView {
        lock.lock(); defer { lock.unlock() }
        if let view = pool.popLast() {
            view.configuration.preferences.javaScriptEnabled = allowJavaScript
            return view
        }
        let config = WKWebViewConfiguration()
        config.preferences.javaScriptEnabled = allowJavaScript
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        let view = WKWebView(frame: .zero, configuration: config)
        view.setValue(false, forKey: "drawsBackground")
        view.allowsBackForwardNavigationGestures = false
        return view
    }

    func recycle(_ view: WKWebView) {
        lock.lock(); defer { lock.unlock() }
        view.navigationDelegate = nil
        view.uiDelegate = nil
        if pool.count < maxSize {
            pool.append(view)
        }
    }
}

// MARK: - SwiftUI wrapper

struct RenderedHTMLView: NSViewRepresentable {
    let rawHTML: String
    let allowJavaScript: Bool
    let allowRemoteImages: Bool
    let fontSize: Double
    @Binding var contentHeight: CGFloat

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> WKWebView {
        let webView = MessageRenderEngine.shared.pool.checkout(allowJavaScript: allowJavaScript)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        let isDark = context.environment.colorScheme == .dark
        let prepared = MessageRenderEngine.shared.prepareHTML(
            rawHTML,
            allowRemoteImages: allowRemoteImages,
            isDark: isDark,
            fontSize: fontSize
        )
        context.coordinator.startTime = Date()
        nsView.configuration.preferences.javaScriptEnabled = allowJavaScript
        nsView.loadHTMLString(prepared, baseURL: nil)
    }

    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        MessageRenderEngine.shared.pool.recycle(nsView)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var parent: RenderedHTMLView
        var startTime: Date = Date()

        init(_ parent: RenderedHTMLView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript("document.body.scrollHeight") { [weak self] result, _ in
                var height: CGFloat?
                if let n = result as? NSNumber {
                    height = CGFloat(truncating: n)
                }
                if let h = height {
                    DispatchQueue.main.async {
                        self?.parent.contentHeight = max(h + 16, 50)
                    }
                }
                if let start = self?.startTime {
                    let delta = Date().timeIntervalSince(start)
                    if delta > 0.15 {
                        NSLog("[MessageRenderEngine] slow render: %.0f ms", delta * 1000)
                    }
                }
            }
        }
    }
}
