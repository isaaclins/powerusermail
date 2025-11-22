import SwiftUI

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

            // Check if this line starts a quote block
            // This is a heuristic and might be too aggressive or miss some cases
            // Ideally we'd use a regex for "On ... wrote:" but simple prefix checks help a lot

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
                // If it's just ">", it's a quote line. If it's a separator, it's the end.
                if trimmed.hasPrefix(">") {
                    continue  // Skip this line, but maybe not stop completely?
                    // Usually in chat view we want to hide all quoted text.
                    // If we break here, we hide everything after the first quote.
                    break
                }
                break
            }

            resultLines.append(line)
        }

        return resultLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isMe { Spacer() }

            VStack(alignment: .leading, spacing: 4) {
                if !isMe && !email.subject.isEmpty {
                    Text(email.from)  // Show sender name/email for others
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Text(cleanedBody)  // Use cleaned body
                    .font(.body)
                    .foregroundStyle(isMe ? .white : .primary)
                    .lineLimit(nil)

                Text(email.receivedAt, style: .time)
                    .font(.caption2)
                    .foregroundStyle(isMe ? .white.opacity(0.8) : .secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(12)
            .background(isMe ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
            .cornerRadius(16)
            // Add a little tail effect or just rounded corners
            .clipShape(
                RoundedRectangle(cornerRadius: 16)
            )
            .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
            .frame(maxWidth: 450, alignment: isMe ? .trailing : .leading)
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

            if !isMe { Spacer() }
        }
    }
}
