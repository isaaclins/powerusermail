import SwiftUI
#if os(macOS)
import AppKit
import UserNotifications
#else
import UserNotifications
#endif

// MARK: - Inbox Filter (Demo has only 3 filters)
enum InboxFilter: String, CaseIterable {
    case all = "All"
    case unread = "Unread"
    case archived = "Archived"

    var shortcutNumber: Int {
        switch self {
        case .all: return 1
        case .unread: return 2
        case .archived: return 3
        }
    }

    var icon: String {
        switch self {
        case .all: return "tray"
        case .unread: return "envelope.badge"
        case .archived: return "archivebox"
        }
    }
}

struct InboxView: View {
    @ObservedObject var viewModel: InboxViewModel
    @Binding var selectedConversation: Conversation?
    @State private var activeFilter: InboxFilter = .unread  // Demo shows Unread selected by default
    @State private var searchText = ""
    @ObservedObject private var stateStore = ConversationStateStore.shared
    @StateObject private var notificationManager = NotificationManager.shared

    let service: MailService
    let myEmail: String
    var onReauthenticate: (() -> Void)?
    var onOpenCommandPalette: (() -> Void)?

    init(
        viewModel: InboxViewModel, service: MailService, myEmail: String,
        selectedConversation: Binding<Conversation?>, onReauthenticate: (() -> Void)? = nil,
        onOpenCommandPalette: (() -> Void)? = nil
    ) {
        self.viewModel = viewModel
        self.service = service
        self.myEmail = myEmail
        _selectedConversation = selectedConversation
        self.onReauthenticate = onReauthenticate
        self.onOpenCommandPalette = onOpenCommandPalette
    }

    /// Conversations filtered by active filter/search, with pinned always visible and first
    private var filteredConversations: [Conversation] {
        let stateStore = ConversationStateStore.shared

        let conversations = viewModel.conversations

        func applySearch(_ list: [Conversation]) -> [Conversation] {
            guard !searchText.isEmpty else { return list }
            return list.filter { conv in
                conv.person.localizedCaseInsensitiveContains(searchText)
                    || conv.messages.contains { $0.subject.localizedCaseInsensitiveContains(searchText) }
            }
        }

        // Base groups
        var pinnedAll = conversations.filter { stateStore.isPinned(conversationId: $0.id) }
        var pinnedArchived = conversations.filter {
            stateStore.isPinned(conversationId: $0.id) && stateStore.isArchived(conversationId: $0.id)
        }
        var pinnedNonArchived = conversations.filter {
            stateStore.isPinned(conversationId: $0.id) && !stateStore.isArchived(conversationId: $0.id)
        }

        // Non-pinned groups
        var nonPinnedAll = conversations.filter { !stateStore.isPinned(conversationId: $0.id) }
        var nonPinnedArchived = conversations.filter {
            !stateStore.isPinned(conversationId: $0.id) && stateStore.isArchived(conversationId: $0.id)
        }
        var nonPinnedUnread = conversations.filter {
            !stateStore.isPinned(conversationId: $0.id) && !stateStore.isArchived(conversationId: $0.id) && $0.hasUnread
        }

        // Apply search
        pinnedAll = applySearch(pinnedAll)
        pinnedArchived = applySearch(pinnedArchived)
        pinnedNonArchived = applySearch(pinnedNonArchived)
        nonPinnedAll = applySearch(nonPinnedAll)
        nonPinnedArchived = applySearch(nonPinnedArchived)
        nonPinnedUnread = applySearch(nonPinnedUnread)

        if activeFilter == .archived {
            return pinnedArchived + nonPinnedArchived
        } else if activeFilter == .unread {
            // Only include unread pinned that are not archived
            let pinnedUnread = pinnedNonArchived.filter { $0.hasUnread }
            return pinnedUnread + nonPinnedUnread
        } else {
            // All: show everything (archived and non-archived), pinned first
            return pinnedAll + nonPinnedAll
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if notificationManager.authorizationStatus == .denied {
                notificationPermissionBanner
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            // Top bar (search + settings)
            topBar

            // Filter tabs
            filterBar

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filteredConversations) { conversation in
                        ConversationRow(
                            conversation: conversation,
                            isSelected: selectedConversation?.id == conversation.id,
                            displayName: displayName(for: conversation.person),
                            showPinIcon: ConversationStateStore.shared.isPinned(
                                conversationId: conversation.id),
                            showArchiveIcon: ConversationStateStore.shared.isArchived(
                                conversationId: conversation.id)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                viewModel.select(conversation: conversation)
                                selectedConversation = conversation
                        ConversationStateStore.shared.markAsRead(
                            conversationId: conversation.id)
                            }
                        }
                    }
                }
            }
        }
        .focusable(true)
        .focusEffectDisabled(true)
        .onKeyPress(.downArrow) {
            moveSelection(1)
            return .handled
        }
        .onKeyPress(.upArrow) {
            moveSelection(-1)
            return .handled
        }
        .safeAreaInset(edge: .bottom) {
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
                    Text(
                        viewModel.loadingProgress.isEmpty
                            ? "Loading chats…" : viewModel.loadingProgress
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
            } else if viewModel.requiresReauthentication {
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
            } else if filteredConversations.isEmpty && !viewModel.isLoading && activeFilter != .all
            {
                ContentUnavailableView(
                    "No \(activeFilter.rawValue) Messages",
                    systemImage: activeFilter.icon
                )
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("InboxFilter1"))) {
            _ in
            withAnimation(.easeInOut(duration: 0.2)) { activeFilter = .unread }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("InboxFilter2"))) {
            _ in
            withAnimation(.easeInOut(duration: 0.2)) { activeFilter = .all }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("InboxFilter3"))) {
            _ in
            withAnimation(.easeInOut(duration: 0.2)) { activeFilter = .archived }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("MarkAllAsRead"))) {
            _ in
            let allIds = viewModel.conversations.map { $0.id }
            ConversationStateStore.shared.markAllAsRead(conversationIds: allIds)
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("MarkAllAsUnread"))) {
            _ in
            let allIds = viewModel.conversations.map { $0.id }
            ConversationStateStore.shared.markAllAsUnread(conversationIds: allIds)
        }
#if os(macOS)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await notificationManager.refreshAuthorizationStatus() }
        }
#endif
        .onAppear {
            // Configure and load inbox when view appears
            viewModel.configure(service: service, myEmail: myEmail)
        }
        .task {
            // Ensure inbox loads on first appear (handles app launch case)
            if viewModel.conversations.isEmpty && !viewModel.isLoading {
                await viewModel.loadInbox()
            }
        }
    }

    // MARK: - Notification permission banner
    private var notificationPermissionBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "bell.slash")
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text("Notifications are disabled")
                    .font(.callout.weight(.semibold))
                Text("Enable macOS notifications to get alerts for new mail.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

#if os(macOS)
            Button("Open Settings") {
                openNotificationSettings()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
#endif
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.1), radius: 6, y: 2)
    }

#if os(macOS)
    private func openNotificationSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") else { return }
        NSWorkspace.shared.open(url)
    }
#endif

    /// Move selection with keyboard arrows (only when this view has focus)
    private func moveSelection(_ delta: Int) {
        let items = filteredConversations
        guard !items.isEmpty else { return }

        let currentIndex = items.firstIndex(where: { $0.id == selectedConversation?.id })
        let targetIndex: Int
        if let currentIndex {
            targetIndex = max(0, min(items.count - 1, currentIndex + delta))
        } else {
            targetIndex = delta >= 0 ? 0 : items.count - 1
        }

        let target = items[targetIndex]
        withAnimation(.easeInOut(duration: 0.15)) {
            viewModel.select(conversation: target)
            selectedConversation = target
            ConversationStateStore.shared.markAsRead(conversationId: target.id)
        }
    }

    // MARK: - Top Bar (Search + Settings)
    private var topBar: some View {
        HStack(spacing: 8) {
            Button {
                onOpenCommandPalette?()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)

                    Text("Search emails...")
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text("⌘K")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.secondary.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)

            settingsButton
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private var settingsButton: some View {
#if os(macOS)
        if #available(macOS 14.0, *) {
            SettingsLink {
                Image(systemName: "gearshape")
                    .foregroundStyle(.secondary)
                    .frame(width: 36, height: 36)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .help("Settings")
        } else {
            Button {
                openAppSettings()
            } label: {
                Image(systemName: "gearshape")
                    .foregroundStyle(.secondary)
                    .frame(width: 36, height: 36)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .help("Settings")
        }
#else
        EmptyView()
#endif
    }

#if os(macOS)
    private func openAppSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
#endif

    // MARK: - Authentication Required View
    private var authenticationRequiredView: some View {
        VStack(spacing: 16) {
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

    // MARK: - Filter Bar (demo style)
    private var filterBar: some View {
        HStack(spacing: 8) {
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
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    /// Extract a cleaner display name from email addresses
    private func displayName(for person: String) -> String {
        if person.hasPrefix("Topic:") {
            return person
        }

        if let nameEnd = person.firstIndex(of: "<") {
            let name = String(person[..<nameEnd]).trimmingCharacters(in: .whitespaces)
            if !name.isEmpty {
                return name
            }
        }

        if let atIndex = person.firstIndex(of: "@") {
            let localPart = String(person[..<atIndex])
            let formatted =
                localPart
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

// MARK: - Filter Pill (demo style - simpler)
struct FilterPill: View {
    let filter: InboxFilter
    let isActive: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text("⌘\(filter.shortcutNumber)")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(isActive ? .white.opacity(0.9) : .secondary)

                Text(filter.rawValue)
                    .font(.system(size: 13, weight: .medium))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        isActive
                            ? Color.accentColor : Color.secondary.opacity(isHovered ? 0.15 : 0.1))
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

// MARK: - Conversation Row (demo style)
struct ConversationRow: View {
    let conversation: Conversation
    let isSelected: Bool
    let displayName: String
    var showPinIcon: Bool = false
    var showArchiveIcon: Bool = false

    @State private var isHovered = false
    @ObservedObject private var stateStore = ConversationStateStore.shared

    private var isTopic: Bool {
        PromotedThreadStore.shared.isPromoted(threadId: conversation.id)
    }

    private var hasUnread: Bool {
        // Check if marked as read in the store - this will now trigger updates when store changes
        if stateStore.readConversationIDs.contains(conversation.id) {
            return false
        }
        return conversation.messages.contains { !$0.isRead }
    }

    var body: some View {
        HStack(spacing: 12) {
            // Profile picture (larger like demo ~44px)
            if isTopic {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.purple.opacity(0.8), .purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Image(systemName: "number")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 44, height: 44)
            } else {
                SenderProfilePicture(email: conversation.person, size: 44)
            }

            // Content
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(displayName)
                        .font(.system(size: 15, weight: hasUnread ? .semibold : .regular))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    // Pin icon for pinned conversations
                    if showPinIcon {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.orange)
                    }
                    if showArchiveIcon {
                        Image(systemName: "archivebox")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if let last = conversation.latestMessage {
                        Text(last.receivedAt.relativeTimeString())
                            .font(.system(size: 12))
                            .foregroundStyle(hasUnread ? Color.accentColor : Color.secondary)
                    }
                }

                HStack {
                    if let last = conversation.latestMessage {
                        Text(last.preview.isEmpty ? last.subject : last.preview)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    // Unread indicator on the RIGHT (like demo)
                    if hasUnread {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 8, height: 8)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(backgroundColor)
        )
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovered = hovering
            }
        }
        .contextMenu {
            Button {
                ConversationStateStore.shared.togglePinned(conversationId: conversation.id)
            } label: {
                Label(
                    ConversationStateStore.shared.isPinned(conversationId: conversation.id)
                        ? "Unpin" : "Pin to Top",
                    systemImage: ConversationStateStore.shared.isPinned(
                        conversationId: conversation.id) ? "pin.slash" : "pin"
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
                    ConversationStateStore.shared.isMuted(conversationId: conversation.id)
                        ? "Unmute" : "Mute",
                    systemImage: ConversationStateStore.shared.isMuted(
                        conversationId: conversation.id) ? "bell" : "bell.slash"
                )
            }

            Divider()

            if isTopic {
                Button {
                    PromotedThreadStore.shared.demote(threadId: conversation.id)
                } label: {
                    Label("Merge back to Person", systemImage: "arrow.down.backward.square")
                }
            } else {
                Button {
                    for message in conversation.messages {
                        PromotedThreadStore.shared.promote(threadId: message.threadId)
                    }
                } label: {
                    Label("Promote to Topic", systemImage: "arrow.up.forward.square")
                }
            }

            Divider()

            Button {
                NotificationCenter.default.post(
                    name: Notification.Name("ArchiveConversationById"),
                    object: nil,
                    userInfo: [
                        "id": conversation.id,
                        "archive": !ConversationStateStore.shared.isArchived(conversationId: conversation.id)
                    ])
            } label: {
                Label(
                    ConversationStateStore.shared.isArchived(conversationId: conversation.id)
                        ? "Move to Inbox" : "Archive",
                    systemImage: ConversationStateStore.shared.isArchived(conversationId: conversation.id)
                        ? "tray.and.arrow.up" : "archivebox"
                )
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
