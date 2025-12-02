import SwiftUI

struct InboxView: View {
    @StateObject private var viewModel: InboxViewModel
    @Binding var selectedConversation: Conversation?

    init(service: MailService, myEmail: String, selectedConversation: Binding<Conversation?>) {
        _viewModel = StateObject(wrappedValue: InboxViewModel(service: service, myEmail: myEmail))
        _selectedConversation = selectedConversation
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(viewModel.conversations) { conversation in
                    ConversationRow(
                        conversation: conversation,
                        isSelected: selectedConversation?.id == conversation.id,
                        displayName: displayName(for: conversation.person)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            viewModel.select(conversation: conversation)
                            selectedConversation = conversation
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .task { await viewModel.loadInbox() }
        .safeAreaInset(edge: .bottom) {
            // Show loading progress at bottom while loading
            if viewModel.isLoading && !viewModel.conversations.isEmpty {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text(viewModel.loadingProgress)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .shadow(color: .black.opacity(0.1), radius: 4)
                .padding(.bottom, 8)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.easeInOut(duration: 0.2), value: viewModel.isLoading)
            }
        }
        .overlay {
            if viewModel.isLoading && viewModel.conversations.isEmpty {
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text(viewModel.loadingProgress.isEmpty ? "Loading chats…" : viewModel.loadingProgress)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } else if let error = viewModel.errorMessage, viewModel.conversations.isEmpty {
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
            } else if viewModel.conversations.isEmpty && !viewModel.isLoading {
                ContentUnavailableView("No Messages", systemImage: "tray")
            }
        }
    }
    
    /// Extract a cleaner display name from email addresses
    private func displayName(for person: String) -> String {
        // Handle "Topic: Subject" format
        if person.hasPrefix("Topic:") {
            return person
        }
        
        // Handle "Name <email@example.com>" format
        if let nameEnd = person.firstIndex(of: "<") {
            let name = String(person[..<nameEnd]).trimmingCharacters(in: .whitespaces)
            if !name.isEmpty {
                return name
            }
        }
        
        // Handle plain email - extract name before @
        if let atIndex = person.firstIndex(of: "@") {
            let localPart = String(person[..<atIndex])
            // Convert "john.doe" or "john_doe" to "John Doe"
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
}

// MARK: - Conversation Row
struct ConversationRow: View {
    let conversation: Conversation
    let isSelected: Bool
    let displayName: String
    
    @State private var isHovered = false
    
    private var isTopic: Bool {
        PromotedThreadStore.shared.isPromoted(threadId: conversation.id)
    }
    
    private var hasUnread: Bool {
        conversation.hasUnread
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Unread indicator dot
            Circle()
                .fill(hasUnread ? Color.accentColor : Color.clear)
                .frame(width: 8, height: 8)
            
            // Profile picture or topic icon
            if isTopic {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.blue.opacity(0.8), .blue],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Image(systemName: "number")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 36, height: 36)
            } else {
                SenderProfilePicture(email: conversation.person, size: 36)
            }
            
            // Content
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(displayName)
                        .font(.system(size: 14, weight: hasUnread ? .semibold : .regular))
                        .foregroundStyle(hasUnread ? Color.primary : Color.primary.opacity(0.9))
                        .lineLimit(1)
                    
                    Spacer()
                    
                    if let last = conversation.latestMessage {
                        Text(last.receivedAt.relativeTimeString())
                            .font(.system(size: 12, weight: hasUnread ? .medium : .regular))
                            .foregroundStyle(hasUnread ? Color.accentColor : Color.secondary)
                    }
                }
                
                if let last = conversation.latestMessage {
                    Text(last.subject)
                        .font(.system(size: 13, weight: hasUnread ? .medium : .regular))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(backgroundColor)
        )
        .padding(.horizontal, 8)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovered = hovering
            }
        }
    }
    
    private var backgroundColor: Color {
        if isSelected {
            return Color.accentColor.opacity(0.2)
        } else if isHovered {
            return Color.primary.opacity(0.05)
        } else {
            return Color.clear
        }
    }
}
