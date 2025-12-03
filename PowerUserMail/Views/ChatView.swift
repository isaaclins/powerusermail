import SwiftUI
import WebKit

struct ChatView: View {
    let conversation: Conversation
    let service: MailService
    let myEmail: String

    @State private var replyText = ""
    @State private var isSending = false
    @State private var localMessages: [Email] = []
    @FocusState private var isReplyFocused: Bool
    
    private var allMessages: [Email] {
        let existingIds = Set(conversation.messages.map { $0.id })
        let newLocals = localMessages.filter { !existingIds.contains($0.id) }
        return conversation.messages + newLocals
    }
    
    /// Extract display name from conversation person
    private var displayName: String {
        let person = conversation.person
        
        if person.hasPrefix("Topic:") {
            return String(person.dropFirst(6)).trimmingCharacters(in: .whitespaces)
        }
        
        if let nameEnd = person.firstIndex(of: "<") {
            let name = String(person[..<nameEnd]).trimmingCharacters(in: .whitespaces)
            if !name.isEmpty {
                return name
            }
        }
        
        if let atIndex = person.firstIndex(of: "@") {
            let localPart = String(person[..<atIndex])
            let formatted = localPart
                .replacingOccurrences(of: ".", with: " ")
                .replacingOccurrences(of: "_", with: " ")
                .split(separator: " ")
                .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
                .joined(separator: " ")
            return formatted
        }
        
        return person
    }
    
    /// Extract email from conversation person
    private var personEmail: String {
        let person = conversation.person
        
        // Handle "Name <email@example.com>" format
        if let start = person.firstIndex(of: "<"),
           let end = person.firstIndex(of: ">") {
            return String(person[person.index(after: start)..<end])
        }
        
        // If it's already an email
        if person.contains("@") {
            return person
        }
        
        return ""
    }

    var body: some View {
        VStack(spacing: 0) {
            // Chat Header (like demo)
            chatHeader
            
            Divider()
            
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(allMessages) { email in
                            ChatBubble(email: email, myEmail: myEmail)
                                .id(email.id)
                        }
                    }
                    .padding()
                }
                .onChange(of: conversation) { _ in
                    localMessages.removeAll { msg in
                        conversation.messages.contains { $0.id == msg.id }
                    }
                    scrollToBottom(proxy: proxy)
                }
                .onChange(of: localMessages.count) { _ in
                    scrollToBottom(proxy: proxy)
                }
                .onAppear {
                    scrollToBottom(proxy: proxy)
                }
            }

            Divider()

            // Reply Area (demo style)
            HStack(alignment: .center, spacing: 12) {
                MessageInputField(
                    text: $replyText,
                    placeholder: "Type a message...",
                    onSend: sendReply
                )
                .frame(minHeight: 40, maxHeight: 120)

                Button(action: sendReply) {
                    Image(systemName: "arrowtriangle.right.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(replyText.isEmpty ? Color.gray.opacity(0.5) : Color.accentColor)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(replyText.isEmpty || isSending)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .navigationTitle("")
        .toolbar(.hidden, for: .automatic)
    }
    
    // MARK: - Chat Header (like demo)
    private var chatHeader: some View {
        HStack(spacing: 12) {
            SenderProfilePicture(email: conversation.person, size: 44)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                
                if !personEmail.isEmpty {
                    Text(personEmail)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
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
        
        // Capture the message content before clearing
        let messageBody = replyText

        Task {
            do {
                // Determine recipient
                let participants = conversation.messages.flatMap { [$0.from] + $0.to + $0.cc }
                let uniqueParticipants = Set(participants)
                let recipients = uniqueParticipants.filter {
                    !$0.localizedCaseInsensitiveContains(myEmail)
                        && !$0.localizedCaseInsensitiveContains("topic:")
                }

                let finalTo = recipients.isEmpty ? [conversation.person] : Array(recipients)

                // Subject
                let lastSubject = conversation.messages.last?.subject ?? ""
                let subject =
                    lastSubject.lowercased().hasPrefix("re:") ? lastSubject : "Re: \(lastSubject)"

                let draft = DraftMessage(
                    to: finalTo,
                    subject: subject,
                    body: messageBody
                )
                
                // Create optimistic local message immediately
                let preview = String(messageBody.prefix(100))
                let optimisticMessage = Email(
                    id: "local-\(UUID().uuidString)",
                    threadId: conversation.id,
                    subject: subject,
                    from: myEmail,
                    to: finalTo,
                    cc: [],
                    preview: preview,
                    body: messageBody,
                    receivedAt: Date(),
                    isRead: true
                )
                
                // Add to local messages immediately (optimistic update)
                await MainActor.run {
                    localMessages.append(optimisticMessage)
                    replyText = ""
                }

                try await service.send(message: draft)

                // Trigger reload in background to sync with server
                NotificationCenter.default.post(name: Notification.Name("ReloadInbox"), object: nil)

            } catch {
                print("Failed to send reply: \(error)")
                // Remove the optimistic message on failure
                await MainActor.run {
                    localMessages.removeAll { $0.body == messageBody }
                    replyText = messageBody // Restore the text so user can retry
                }
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
            // For HTML content, use minimal spacing to allow more width
            if isMe { Spacer(minLength: isHTMLContent ? 20 : 50) }

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
            .padding(isHTMLContent ? 8 : 12)
            .background(isMe ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
            .cornerRadius(16)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
            .frame(maxWidth: isHTMLContent ? .infinity : 500, alignment: isMe ? .trailing : .leading)
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

            if !isMe { Spacer(minLength: isHTMLContent ? 20 : 50) }
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
            // Calculate content height after load - no cap, let it expand fully
            webView.evaluateJavaScript("document.body.scrollHeight") { [weak self] result, _ in
                if let height = result as? CGFloat {
                    DispatchQueue.main.async {
                        // Add some padding and ensure minimum height
                        self?.parent.contentHeight = max(height + 20, 50)
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

// MARK: - Message Input Field with Enter to Send, Shift+Enter for New Line
struct MessageInputField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var onSend: () -> Void
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let textView = MessageTextView()
        
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.font = .systemFont(ofSize: 14)
        textView.textColor = .labelColor
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.autoresizingMask = [.width]
        textView.allowsUndo = true
        
        // Store reference for keyboard handling
        textView.onSend = onSend
        
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        
        // Styling
        scrollView.wantsLayer = true
        scrollView.layer?.cornerRadius = 18
        scrollView.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        scrollView.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.3).cgColor
        scrollView.layer?.borderWidth = 1
        
        // Set initial text
        textView.string = text
        
        return scrollView
    }
    
    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? MessageTextView else { return }
        
        if textView.string != text {
            textView.string = text
        }
        textView.onSend = onSend
        
        // Update placeholder visibility
        textView.needsDisplay = true
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MessageInputField
        
        init(_ parent: MessageInputField) {
            self.parent = parent
        }
        
        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }
    }
}

// Custom NSTextView that handles Enter/Shift+Enter
class MessageTextView: NSTextView {
    var onSend: (() -> Void)?
    var placeholderString: String = "Type a message..."
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        // Draw placeholder if empty - at the exact same position as text would appear
        if string.isEmpty, let textContainer = textContainer, let layoutManager = layoutManager {
            let attrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: NSColor.placeholderTextColor,
                .font: font ?? .systemFont(ofSize: 14)
            ]
            
            // Get the exact position where text would be drawn
            let glyphRange = layoutManager.glyphRange(for: textContainer)
            var textRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            textRect.origin.x += textContainerOrigin.x
            textRect.origin.y += textContainerOrigin.y
            
            let placeholder = NSAttributedString(string: placeholderString, attributes: attrs)
            placeholder.draw(at: textRect.origin)
        }
    }
    
    override func keyDown(with event: NSEvent) {
        // Enter key
        if event.keyCode == 36 {
            // Shift+Enter = new line
            if event.modifierFlags.contains(.shift) {
                super.keyDown(with: event)
            } else {
                // Enter without shift = send
                if !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    onSend?()
                }
            }
        } else {
            super.keyDown(with: event)
        }
    }
}

