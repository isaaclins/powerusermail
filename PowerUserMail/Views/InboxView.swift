import SwiftUI

struct InboxView: View {
    @StateObject private var viewModel: InboxViewModel
    @Binding var selectedConversation: Conversation?

    init(service: MailService, selectedConversation: Binding<Conversation?>) {
        _viewModel = StateObject(wrappedValue: InboxViewModel(service: service))
        _selectedConversation = selectedConversation
    }

    var body: some View {
        List(selection: $selectedConversation) {
            ForEach(viewModel.conversations) { conversation in
                let isTopic = PromotedThreadStore.shared.isPromoted(threadId: conversation.id)
                Button {
                    viewModel.select(conversation: conversation)
                    selectedConversation = conversation
                } label: {
                    VStack(alignment: .leading) {
                        HStack {
                            Image(systemName: isTopic ? "number" : "person.circle")
                                .foregroundStyle(isTopic ? .blue : .secondary)
                            Text(conversation.person)
                                .font(.headline)
                                .lineLimit(1)
                            Spacer()
                            if let last = conversation.latestMessage {
                                Text(last.receivedAt, style: .time)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if let last = conversation.latestMessage {
                            Text(last.subject)  // Show Subject as the "preview" context
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Text(last.preview)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
        }
        .task { await viewModel.loadInbox() }
        .overlay {
            if viewModel.isLoading {
                ProgressView("Loading chats…")
            } else if let error = viewModel.errorMessage {
                VStack(spacing: 8) {
                    Text(error)
                        .multilineTextAlignment(.center)
                    Button("Retry") {
                        Task { await viewModel.loadInbox() }
                    }
                }
                .padding()
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(radius: 10)
            } else if viewModel.conversations.isEmpty {
                ContentUnavailableView("No Messages", systemImage: "tray")
            }
        }
    }
}
