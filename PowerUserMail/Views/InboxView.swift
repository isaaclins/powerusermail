import SwiftUI

// MARK: - Inbox Filter
enum InboxFilter: String, CaseIterable {
    case unread = "Unread"
    case all = "All"
    case archived = "Archived"
    case pinned = "Pinned"
    
    var shortcutNumber: Int {
        switch self {
        case .unread: return 1
        case .all: return 2
        case .archived: return 3
        case .pinned: return 4
        }
    }
    
    var icon: String {
        switch self {
        case .all: return "tray"
        case .unread: return "envelope.badge"
        case .archived: return "archivebox"
        case .pinned: return "pin"
        }
    }
}

struct InboxView: View {
    @ObservedObject var viewModel: InboxViewModel
    @Binding var selectedConversation: Conversation?
    @State private var activeFilter: InboxFilter = .all
    
    let service: MailService
    let myEmail: String
    var onReauthenticate: (() -> Void)?  // Callback to trigger re-authentication

    init(viewModel: InboxViewModel, service: MailService, myEmail: String, selectedConversation: Binding<Conversation?>, onReauthenticate: (() -> Void)? = nil) {
        self.viewModel = viewModel
        self.service = service
        self.myEmail = myEmail
        _selectedConversation = selectedConversation
        self.onReauthenticate = onReauthenticate
        // Don't configure here - do it in onAppear to ensure proper lifecycle
    }
    
    private var filteredConversations: [Conversation] {
        switch activeFilter {
        case .all:
            return viewModel.conversations
        case .unread:
            return viewModel.conversations.filter { $0.hasUnread }
        case .archived:
            // TODO: Implement archived state tracking
            return []
        case .pinned:
            return viewModel.conversations.filter { 
                ConversationStateStore.shared.isPinned(conversationId: $0.id)
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Filter tabs
            filterBar
            
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(filteredConversations) { conversation in
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
                                // Mark as read when opened
                                ConversationStateStore.shared.markAsRead(conversationId: conversation.id)
                            }
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
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
            } else if viewModel.requiresReauthentication {
                // Special UI for authentication errors
                authenticationRequiredView
            } else if let error = viewModel.errorMessage, viewModel.conversations.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 32))
                        .foregroundStyle(.orange)
                    
                    Text("Something went wrong")
                        .font(.headline)
                    
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    
                    Button("Try Again") {
                        Task { await viewModel.loadInbox() }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(24)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: .black.opacity(0.15), radius: 20)
            } else if viewModel.conversations.isEmpty && !viewModel.isLoading {
                ContentUnavailableView("No Messages", systemImage: "tray")
            } else if filteredConversations.isEmpty && !viewModel.isLoading && activeFilter != .all {
                ContentUnavailableView(
                    "No \(activeFilter.rawValue) Messages",
                    systemImage: activeFilter.icon
                )
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("InboxFilter1"))) { _ in
            withAnimation(.easeInOut(duration: 0.2)) { activeFilter = .unread }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("InboxFilter2"))) { _ in
            withAnimation(.easeInOut(duration: 0.2)) { activeFilter = .all }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("InboxFilter3"))) { _ in
            withAnimation(.easeInOut(duration: 0.2)) { activeFilter = .archived }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("InboxFilter4"))) { _ in
            withAnimation(.easeInOut(duration: 0.2)) { activeFilter = .pinned }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("MarkAllAsRead"))) { _ in
            let allIds = viewModel.conversations.map { $0.id }
            ConversationStateStore.shared.markAllAsRead(conversationIds: allIds)
        }
        .onAppear {
            // Ensure viewModel is configured for this account
            viewModel.configure(service: service, myEmail: myEmail)
        }
    }
    
    // MARK: - Authentication Required View
    private var authenticationRequiredView: some View {
        VStack(spacing: 16) {
            // Icon with animation
            Image(systemName: "key.horizontal")
                .font(.system(size: 40))
                .foregroundStyle(.orange)
                .symbolEffect(.pulse)
            
            Text("Session Expired")
                .font(.title2.bold())
            
            if let email = viewModel.reauthEmail {
                Text("Your session for **\(email)** has expired.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            Text("Please sign in again to continue using PowerUserMail.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            VStack(spacing: 10) {
                Button {
                    onReauthenticate?()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.clockwise")
                        Text("Sign In Again")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                
                Button("Switch Account") {
                    NotificationCenter.default.post(
                        name: Notification.Name("ShowAccountSwitcher"),
                        object: nil
                    )
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }
            .padding(.top, 8)
        }
        .padding(32)
        .frame(maxWidth: 320)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.2), radius: 24)
    }
    
    // MARK: - Filter Bar
    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(InboxFilter.allCases, id: \.self) { filter in
                    FilterPill(
                        filter: filter,
                        isActive: activeFilter == filter,
                        action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                activeFilter = filter
                            }
                        }
                    )
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.5))
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

// MARK: - Filter Pill
struct FilterPill: View {
    let filter: InboxFilter
    let isActive: Bool
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                // Keyboard shortcut indicator (compact)
                Text("⌘\(filter.shortcutNumber)")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(isActive ? .white.opacity(0.8) : .secondary)
                
                Text(filter.rawValue)
                    .font(.system(size: 12, weight: .medium))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isActive ? Color.accentColor : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(
                        isActive ? Color.clear : Color.secondary.opacity(isHovered ? 0.5 : 0.3),
                        lineWidth: 1
                    )
            )
            .foregroundStyle(isActive ? .white : .primary)
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovered = hovering
            }
        }
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
    
    private var isPinned: Bool {
        ConversationStateStore.shared.isPinned(conversationId: conversation.id)
    }
    
    private var isMuted: Bool {
        ConversationStateStore.shared.isMuted(conversationId: conversation.id)
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
                    
                    if isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.orange)
                    }
                    
                    if isMuted {
                        Image(systemName: "bell.slash.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    
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
        .contextMenu {
            // Section 1: Status actions
            Button {
                ConversationStateStore.shared.togglePinned(conversationId: conversation.id)
            } label: {
                Label(
                    ConversationStateStore.shared.isPinned(conversationId: conversation.id) ? "Unpin" : "Pin to Top",
                    systemImage: ConversationStateStore.shared.isPinned(conversationId: conversation.id) ? "pin.slash" : "pin"
                )
            }
            
            Button {
                ConversationStateStore.shared.toggleRead(conversationId: conversation.id)
            } label: {
                Label(
                    hasUnread ? "Mark as Read" : "Mark as Unread",
                    systemImage: hasUnread ? "envelope.open" : "envelope.badge"
                )
            }
            
            Button {
                ConversationStateStore.shared.toggleMuted(conversationId: conversation.id)
            } label: {
                Label(
                    ConversationStateStore.shared.isMuted(conversationId: conversation.id) ? "Unmute" : "Mute",
                    systemImage: ConversationStateStore.shared.isMuted(conversationId: conversation.id) ? "bell" : "bell.slash"
                )
            }
            
            Divider()
            
            // Section 2: Thread organization
            if isTopic {
                Button {
                    PromotedThreadStore.shared.demote(threadId: conversation.id)
                } label: {
                    Label("Merge back to Person", systemImage: "arrow.down.backward.square")
                }
            } else {
                Button {
                    // Promote all messages in this conversation
                    for message in conversation.messages {
                        PromotedThreadStore.shared.promote(threadId: message.threadId)
                    }
                } label: {
                    Label("Promote to Topic", systemImage: "arrow.up.forward.square")
                }
            }
            
            Divider()
            
            // Section 3: Destructive actions
            Button {
                // TODO: Implement archive via API
            } label: {
                Label("Archive", systemImage: "archivebox")
            }
            
            Button(role: .destructive) {
                // TODO: Implement delete via API
            } label: {
                Label("Delete", systemImage: "trash")
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
