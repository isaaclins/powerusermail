import SwiftUI
import WebKit

struct ChatView: View {
    let conversation: Conversation
    let service: MailService
    let myEmail: String

    @State private var replyText = ""
    @State private var isSending = false
    @FocusState private var isReplyFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(conversation.messages) { email in
                            ChatBubble(email: email, myEmail: myEmail)
                                .id(email.id)
                        }
                    }
                    .padding()
                }
                .onChange(of: conversation) { _ in
                    scrollToBottom(proxy: proxy)
                }
                .onAppear {
                    scrollToBottom(proxy: proxy)
                }
            }

            Divider()

            // Inline Reply Area
            HStack(alignment: .bottom, spacing: 12) {
                TextField("Type a message...", text: $replyText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .padding(10)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
                    .lineLimit(1...5)
                    .focused($isReplyFocused)
                    .onSubmit {
                        // Optional: Send on Enter if desired, but for multiline usually Cmd+Enter or Button
                    }

                Button(action: sendReply) {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(replyText.isEmpty ? Color.gray : Color.accentColor)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(replyText.isEmpty || isSending)
            }
            .padding()
            .background(.ultraThinMaterial)
        }
        .navigationTitle(conversation.person)
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        if let last = conversation.messages.last {
            withAnimation {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }

    private func sendReply() {
        guard !replyText.isEmpty else { return }
        isSending = true

        Task {
            do {
                // Determine recipient
                // If it's a person-based chat, conversation.person is the email (mostly)
                // But safer to look at participants excluding me
                let participants = conversation.messages.flatMap { [$0.from] + $0.to + $0.cc }
                let uniqueParticipants = Set(participants)
                let recipients = uniqueParticipants.filter {
                    !$0.localizedCaseInsensitiveContains(myEmail)
                        && !$0.localizedCaseInsensitiveContains("topic:")  // Filter out our topic hack
                }

                // Fallback if no other recipients found (e.g. talking to self), use the conversation ID if it looks like an email
                let finalTo = recipients.isEmpty ? [conversation.person] : Array(recipients)

                // Subject
                let lastSubject = conversation.messages.last?.subject ?? ""
                let subject =
                    lastSubject.lowercased().hasPrefix("re:") ? lastSubject : "Re: \(lastSubject)"

                let draft = DraftMessage(
                    to: finalTo,
                    subject: subject,
                    body: replyText
                )

                try await service.send(message: draft)

                // Clear text
                replyText = ""

                // Trigger reload (optional, depends on how your app updates)
                NotificationCenter.default.post(name: Notification.Name("ReloadInbox"), object: nil)

            } catch {
                print("Failed to send reply: \(error)")
            }
            isSending = false
        }
    }
}

struct ChatBubble: View {
    let email: Email
    let myEmail: String
    
    @State private var contentHeight: CGFloat = 100

    var isMe: Bool {
        email.from.localizedCaseInsensitiveContains(myEmail)
    }

    var cleanedBody: String {
        let body = email.body.isEmpty ? email.preview : email.body

        // Common quote markers
        let markers = [
            "-----Original Message-----",
            "On ",  // English "On [Date], [Name] wrote:"
            "Am ",  // German "Am [Date] schrieb [Name]:"
            "From: ",
            "________________________________",  // Outlook separator
            ">",  // Markdown/Plain text quote
        ]

        let lines = body.components(separatedBy: CharacterSet.newlines)
        var resultLines: [String] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: CharacterSet.whitespaces)

            // Check for "On ... wrote:" pattern
            if trimmed.hasPrefix("On ") && trimmed.hasSuffix("wrote:") {
                break
            }
            // Check for "Am ... schrieb ...:" pattern
            if trimmed.hasPrefix("Am ") && trimmed.hasSuffix(":") && trimmed.contains("schrieb") {
                break
            }

            // Check for other markers
            if markers.contains(where: { trimmed.hasPrefix($0) }) {
                if trimmed.hasPrefix(">") {
                    continue
                }
                break
            }

            resultLines.append(line)
        }

        return resultLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// Strip HTML and extract plain text for display
    var displayText: String {
        var text = cleanedBody
        
        // Remove entire <style>...</style> blocks (including content)
        text = text.replacingOccurrences(
            of: "<style[^>]*>[\\s\\S]*?</style>",
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        
        // Remove entire <script>...</script> blocks
        text = text.replacingOccurrences(
            of: "<script[^>]*>[\\s\\S]*?</script>",
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        
        // Remove entire <head>...</head> section
        text = text.replacingOccurrences(
            of: "<head[^>]*>[\\s\\S]*?</head>",
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        
        // Remove HTML comments
        text = text.replacingOccurrences(
            of: "<!--[\\s\\S]*?-->",
            with: "",
            options: .regularExpression
        )
        
        // Replace <br> and <br/> with newlines
        text = text.replacingOccurrences(
            of: "<br\\s*/?>",
            with: "\n",
            options: [.regularExpression, .caseInsensitive]
        )
        
        // Replace </p>, </div>, </tr> with newlines for paragraph breaks
        text = text.replacingOccurrences(
            of: "</(?:p|div|tr|li|h[1-6])>",
            with: "\n",
            options: [.regularExpression, .caseInsensitive]
        )
        
        // Remove remaining HTML tags
        text = text.replacingOccurrences(
            of: "<[^>]+>",
            with: "",
            options: .regularExpression
        )
        
        // Decode common HTML entities
        text = text.replacingOccurrences(of: "&nbsp;", with: " ")
        text = text.replacingOccurrences(of: "&amp;", with: "&")
        text = text.replacingOccurrences(of: "&lt;", with: "<")
        text = text.replacingOccurrences(of: "&gt;", with: ">")
        text = text.replacingOccurrences(of: "&quot;", with: "\"")
        text = text.replacingOccurrences(of: "&#39;", with: "'")
        text = text.replacingOccurrences(of: "&apos;", with: "'")
        text = text.replacingOccurrences(of: "&#160;", with: " ")
        text = text.replacingOccurrences(of: "&ndash;", with: "–")
        text = text.replacingOccurrences(of: "&mdash;", with: "—")
        text = text.replacingOccurrences(of: "&bull;", with: "•")
        text = text.replacingOccurrences(of: "&copy;", with: "©")
        text = text.replacingOccurrences(of: "&reg;", with: "®")
        
        // Decode numeric HTML entities (&#123; format)
        let numericEntityPattern = "&#(\\d+);"
        if let regex = try? NSRegularExpression(pattern: numericEntityPattern) {
            let range = NSRange(text.startIndex..., in: text)
            let matches = regex.matches(in: text, range: range)
            
            for match in matches.reversed() {
                if let codeRange = Range(match.range(at: 1), in: text),
                   let code = Int(text[codeRange]),
                   let scalar = Unicode.Scalar(code) {
                    let char = String(Character(scalar))
                    if let fullRange = Range(match.range, in: text) {
                        text.replaceSubrange(fullRange, with: char)
                    }
                }
            }
        }
        
        // Clean up multiple newlines
        text = text.replacingOccurrences(
            of: "\\n{3,}",
            with: "\n\n",
            options: .regularExpression
        )
        
        // Clean up multiple spaces
        text = text.replacingOccurrences(
            of: "[ \\t]+",
            with: " ",
            options: .regularExpression
        )
        
        // Clean up spaces around newlines
        text = text.replacingOccurrences(
            of: " *\\n *",
            with: "\n",
            options: .regularExpression
        )
        
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// Check if content is HTML
    var isHTMLContent: Bool {
        let body = cleanedBody.lowercased()
        return body.contains("<html") || body.contains("<body") || body.contains("<div") || 
               body.contains("<table") || body.contains("<p>") || body.contains("<br")
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isMe { Spacer(minLength: 50) }

            VStack(alignment: .leading, spacing: 4) {
                if !isMe && !email.subject.isEmpty {
                    Text(email.from)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if isHTMLContent {
                    // Use WebView for HTML content with scroll passthrough
                    ScrollTransparentWebView(
                        htmlContent: cleanedBody,
                        isMe: isMe,
                        contentHeight: $contentHeight
                    )
                    .frame(height: contentHeight)
                } else {
                    // Use plain Text for simple content
                    Text(displayText)
                        .font(.body)
                        .foregroundStyle(isMe ? .white : .primary)
                        .lineLimit(nil)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text(email.receivedAt, style: .time)
                    .font(.caption2)
                    .foregroundStyle(isMe ? .white.opacity(0.8) : .secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(12)
            .background(isMe ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
            .cornerRadius(16)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
            .frame(maxWidth: isHTMLContent ? 550 : 500, alignment: isMe ? .trailing : .leading)
            .contextMenu {
                if PromotedThreadStore.shared.isPromoted(threadId: email.threadId) {
                    Button {
                        PromotedThreadStore.shared.demote(threadId: email.threadId)
                    } label: {
                        Label("Merge back to Person", systemImage: "arrow.down.backward.square")
                    }
                } else {
                    Button {
                        PromotedThreadStore.shared.promote(threadId: email.threadId)
                    } label: {
                        Label("Promote to Thread", systemImage: "arrow.up.forward.square")
                    }
                }
            }

            if !isMe { Spacer(minLength: 50) }
        }
        .frame(maxWidth: .infinity, alignment: isMe ? .trailing : .leading)
    }
}

// MARK: - Scroll-Transparent WebView
// This WebView passes scroll events to the parent ScrollView

class ScrollPassthroughWebView: WKWebView {
    override func scrollWheel(with event: NSEvent) {
        // Pass scroll events to next responder (parent ScrollView)
        self.nextResponder?.scrollWheel(with: event)
    }
}

struct ScrollTransparentWebView: NSViewRepresentable {
    let htmlContent: String
    let isMe: Bool
    @Binding var contentHeight: CGFloat
    
    func makeNSView(context: Context) -> ScrollPassthroughWebView {
        let config = WKWebViewConfiguration()
        let webView = ScrollPassthroughWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        
        // Disable all scrolling on the WebView itself
        webView.enclosingScrollView?.hasVerticalScroller = false
        webView.enclosingScrollView?.hasHorizontalScroller = false
        
        return webView
    }
    
    func updateNSView(_ nsView: ScrollPassthroughWebView, context: Context) {
        let styledHTML = wrapWithStyling(htmlContent)
        nsView.loadHTMLString(styledHTML, baseURL: nil)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: ScrollTransparentWebView
        
        init(_ parent: ScrollTransparentWebView) {
            self.parent = parent
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Calculate content height after load
            webView.evaluateJavaScript("document.body.scrollHeight") { [weak self] result, _ in
                if let height = result as? CGFloat {
                    DispatchQueue.main.async {
                        self?.parent.contentHeight = min(max(height, 50), 600) // Cap at 600px
                    }
                }
            }
        }
    }
    
    private func wrapWithStyling(_ content: String) -> String {
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        
        let textColor: String
        let linkColor: String
        let bgColor: String
        
        if isMe {
            textColor = "#ffffff"
            linkColor = "#b3d9ff"
            bgColor = "transparent"
        } else {
            textColor = isDark ? "#e4e4e4" : "#1a1a1a"
            linkColor = isDark ? "#6cb6ff" : "#0066cc"
            bgColor = "transparent"
        }
        
        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <style>
                * { box-sizing: border-box; }
                html, body {
                    margin: 0;
                    padding: 0;
                    overflow: hidden !important;
                    background: \(bgColor) !important;
                }
                body {
                    font-family: -apple-system, BlinkMacSystemFont, 'SF Pro Text', sans-serif;
                    font-size: 13px;
                    line-height: 1.5;
                    color: \(textColor) !important;
                    word-wrap: break-word;
                    overflow-wrap: break-word;
                }
                /* Override any background colors in email */
                body *, div, table, td, th, p, span {
                    background-color: transparent !important;
                    color: \(textColor) !important;
                }
                a { color: \(linkColor) !important; text-decoration: none; }
                a:hover { text-decoration: underline; }
                img { max-width: 100%; height: auto; border-radius: 6px; }
                table { border-collapse: collapse; max-width: 100%; }
                pre, code {
                    font-family: 'SF Mono', Menlo, monospace;
                    font-size: 12px;
                    background: rgba(128,128,128,0.2) !important;
                    border-radius: 4px;
                    padding: 2px 4px;
                }
                pre { padding: 8px; overflow-x: auto; }
                blockquote {
                    border-left: 3px solid \(linkColor);
                    margin: 0.5em 0;
                    padding-left: 10px;
                    opacity: 0.8;
                }
                h1, h2, h3, h4, h5, h6 {
                    margin: 0.5em 0 0.3em;
                    line-height: 1.3;
                }
                p { margin: 0.4em 0; }
                ul, ol { padding-left: 1.2em; margin: 0.4em 0; }
                hr { border: none; border-top: 1px solid rgba(128,128,128,0.3); margin: 0.5em 0; }
            </style>
        </head>
        <body>\(content)</body>
        </html>
        """
    }
}

