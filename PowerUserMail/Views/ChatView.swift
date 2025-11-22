import SwiftUI

struct ChatView: View {
    let conversation: Conversation

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(conversation.messages) { email in
                        ChatBubble(email: email)
                            .id(email.id)
                    }
                }
                .padding()
            }
            .onChange(of: conversation) { _ in
                if let last = conversation.messages.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
        .navigationTitle(conversation.person)
    }
}

struct ChatBubble: View {
    let email: Email

    // In a real app, check if email.from == myAccount.email
    var isMe: Bool { false }

    var body: some View {
        HStack {
            if isMe { Spacer() }

            VStack(alignment: .leading, spacing: 4) {
                if !email.subject.isEmpty {
                    Text(email.subject)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // We use the preview for the chat bubble text for now,
                // or we could try to strip HTML from body.
                // Using preview is safer for a chat list.
                Text(email.preview)
                    .font(.body)
                    .foregroundStyle(isMe ? .white : .primary)

                Text(email.receivedAt, style: .time)
                    .font(.caption2)
                    .foregroundStyle(isMe ? .white.opacity(0.8) : .secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(12)
            .background(isMe ? Color.blue : Color(nsColor: .controlBackgroundColor))
            .cornerRadius(16)
            .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
            .frame(maxWidth: 400, alignment: isMe ? .trailing : .leading)
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
