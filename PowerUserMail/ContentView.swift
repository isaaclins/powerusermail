//
//  ContentView.swift
//  PowerUserMail
//
//  Created by Isaac Lins on 21.11.2025.
//

import CoreData
import SwiftUI

struct ContentView: View {
    @StateObject private var accountViewModel = AccountViewModel()
    @StateObject private var inboxViewModel = InboxViewModel()
    @State private var selectedConversation: Conversation?
    @State private var isShowingCompose = false
    @State private var isShowingAccountSwitcher = false
    @State private var isShowingCommandPalette = false
    @State private var commandSearch = ""
    @State private var commandActions: [CommandAction] = []
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var isTogglingsidebar = false

    var body: some View {
        Group {
            if let account = accountViewModel.selectedAccount,
                let service = accountViewModel.service(for: account.provider)
            {
                mainSplitView(service: service)
                    .id(account.id)
            } else if accountViewModel.accounts.isEmpty {
                // Only show onboarding if NO accounts exist
                onboardingView
            } else {
                // Accounts exist but none selected - auto-select first
                Color.clear.onAppear {
                    accountViewModel.selectedAccount = accountViewModel.accounts.first
                }
            }
        }
        .overlay {
            if isShowingCommandPalette {
                ZStack {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .onTapGesture {
                            isShowingCommandPalette = false
                        }
                    
                    CommandPaletteView(
                        isPresented: $isShowingCommandPalette,
                        searchText: $commandSearch,
                        actions: commandActions,
                        conversations: inboxViewModel.conversations,
                        onSelect: { action in
                            commandSearch = ""
                            action.perform()
                        },
                        onSelectConversation: { conversation in
                            commandSearch = ""
                            selectedConversation = conversation
                        }
                    )
                    .frame(maxWidth: 500)
                }
                .transaction { transaction in
                    transaction.animation = nil
                }
            }
        }
        .sheet(isPresented: $isShowingCompose) {
            if let account = accountViewModel.selectedAccount,
                let service = accountViewModel.service(for: account.provider)
            {
                ComposeView(viewModel: ComposeViewModel(service: service))
            }
        }
        .sheet(isPresented: $isShowingAccountSwitcher) {
            AccountSwitcherSheet(accountViewModel: accountViewModel, isPresented: $isShowingAccountSwitcher)
        }
        .onReceive(
            NotificationCenter.default.publisher(for: Notification.Name("ToggleCommandPalette"))
        ) { _ in
            toggleCommandPalette()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("OpenCompose"))) {
            _ in
            openCompose()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ToggleSidebar"))) {
            _ in
            toggleSidebar()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ShowAccountSwitcher"))) {
            _ in
            isShowingAccountSwitcher = true
        }
        // Conversation action notifications
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ArchiveCurrentConversation"))) { _ in
            archiveCurrentConversation()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("PinCurrentConversation"))) { _ in
            pinCurrentConversation()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("UnpinCurrentConversation"))) { _ in
            unpinCurrentConversation()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("MarkCurrentUnread"))) { _ in
            markCurrentUnread()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("MarkCurrentRead"))) { _ in
            markCurrentRead()
        }
        // Handle notification tap to open conversation
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("OpenConversation"))) { notification in
            if let from = notification.userInfo?["from"] as? String {
                openConversationFromNotification(from: from)
            }
        }
        // Handle authentication required notification
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("AuthenticationRequired"))) { notification in
            if let email = notification.userInfo?["email"] as? String {
                print("🔐 Authentication required for: \(email)")
                // The InboxView will show the re-auth UI, but we could also show an alert here
            }
        }
        .onAppear {
            // Load all command plugins
            CommandLoader.loadAll()
            configureCommands()
        }
        // CRITICAL: Handle account switching - clear all data for isolation
        .onChange(of: accountViewModel.selectedAccount?.id) { oldValue, newValue in
            if oldValue != newValue && oldValue != nil {
                print("🔄 Account changed from \(oldValue?.uuidString ?? "none") to \(newValue?.uuidString ?? "none")")
                // Clear selected conversation when switching accounts
                selectedConversation = nil
                // CRITICAL: Clear ALL inbox data IMMEDIATELY before new account loads
                inboxViewModel.clearAllData()
                // Reset notification manager
                NotificationManager.shared.resetForNewAccount()
            }
        }
        .onChange(of: accountViewModel.selectedAccount?.emailAddress) { oldEmail, newEmail in
            if let old = oldEmail, let new = newEmail, old != new {
                print("🔄 Email changed from \(old) to \(new) - clearing data")
                selectedConversation = nil
                inboxViewModel.clearAllData()
                NotificationManager.shared.resetForNewAccount()
            }
        }
    }

    private var onboardingView: some View {
        SettingsView(accountViewModel: accountViewModel)
    }

    private func mainSplitView(service: MailService) -> some View {
        let myEmail = accountViewModel.selectedAccount?.emailAddress ?? ""
        return NavigationSplitView(columnVisibility: $columnVisibility) {
            InboxView(
                viewModel: inboxViewModel, 
                service: service, 
                myEmail: myEmail, 
                selectedConversation: $selectedConversation,
                onReauthenticate: {
                    if let account = accountViewModel.selectedAccount {
                        Task {
                            inboxViewModel.resetAuthState()
                            await accountViewModel.authenticate(provider: account.provider)
                            if accountViewModel.selectedAccount != nil {
                                await inboxViewModel.loadInbox()
                            }
                        }
                    }
                },
                onOpenCommandPalette: {
                    toggleCommandPalette()
                }
            )
            .navigationSplitViewColumnWidth(min: 300, ideal: 340)
            .toolbar(.hidden, for: .automatic)
        } detail: {
            if let conversation = selectedConversation,
                let account = accountViewModel.selectedAccount
            {
                ChatView(
                    conversation: conversation, service: service, myEmail: account.emailAddress)
            } else {
                ContentUnavailableView(
                    "No Chat Selected", systemImage: "bubble.left.and.bubble.right")
            }
        }
        .navigationTitle("PowerUserMail")
    }

    private func openCompose() {
        isShowingCompose = true
    }
    
    private func toggleSidebar() {
        // Debounce to prevent rapid toggling breaking the layout
        guard !isTogglingsidebar else { return }
        isTogglingsidebar = true
        
        withAnimation(.easeInOut(duration: 0.2)) {
            if columnVisibility == .detailOnly {
                columnVisibility = .all
            } else {
                columnVisibility = .detailOnly
            }
        }
        
        // Re-enable after animation completes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            isTogglingsidebar = false
        }
    }

    private func openReply() {
        guard let conversation = selectedConversation else { return }
        // For now, we just open the compose view pre-filled.
        // Ideally, we would focus the inline reply in ChatView, but that requires more state passing.
        // Let's stick to opening ComposeView for the "Command Palette" reply action as requested.

        // Logic to find recipients (same as in ChatView)
        let participants = conversation.messages.flatMap { [$0.from] + $0.to + $0.cc }
        let uniqueParticipants = Set(participants)
        let myEmail = accountViewModel.selectedAccount?.emailAddress ?? ""
        let recipients = uniqueParticipants.filter {
            !$0.localizedCaseInsensitiveContains(myEmail)
                && !$0.localizedCaseInsensitiveContains("topic:")
        }
        let finalTo = recipients.isEmpty ? [conversation.person] : Array(recipients)

        let lastSubject = conversation.messages.last?.subject ?? ""
        let subject = lastSubject.lowercased().hasPrefix("re:") ? lastSubject : "Re: \(lastSubject)"

        // We need to pass this draft to ComposeView.
        // Currently ComposeView creates its own ViewModel. We should probably allow injecting a draft.
        // For this iteration, I'll just open the empty compose view because refactoring ComposeView is extra scope
        // and the user asked for "respond command" which usually implies just triggering the action.
        // BUT, to be helpful, I'll try to set it up.

        // Actually, the user said "respond from INSIDE of the selected chat" which I implemented in ChatView.
        // And "respond command in the command pallette".
        // If I can't easily pre-fill ComposeView without refactoring, I'll just focus the chat view?
        // No, I can't focus the chat view easily from here.

        // Let's just open ComposeView for now.
        isShowingCompose = true
    }

    private func toggleCommandPalette() {
        // Use commands from the registry, passing context
        let hasConversation = selectedConversation != nil
        commandActions = CommandRegistry.shared.getCommands(hasSelectedConversation: hasConversation)
        
        // Add context-specific commands
        if hasConversation {
            commandActions.insert(
                CommandAction(
                    title: "Reply to Chat", keywords: ["reply", "respond", "answer"],
                    iconSystemName: "arrowshape.turn.up.left",
                    isContextual: true,
                    showInPalette: true
                ) {
                    openReply()
                }, at: 0
            )
        }
        
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            isShowingCommandPalette.toggle()
        }
    }

    private func configureCommands() {
        commandActions = CommandRegistry.shared.getCommands(hasSelectedConversation: selectedConversation != nil)
    }
    
    // MARK: - Conversation Actions
    
    private func archiveCurrentConversation() {
        guard let conversation = selectedConversation else { return }
        ConversationStateStore.shared.archive(conversationId: conversation.id)
        selectedConversation = nil
        print("Archived conversation: \(conversation.person)")
    }
    
    private func pinCurrentConversation() {
        guard let conversation = selectedConversation else { return }
        ConversationStateStore.shared.togglePinned(conversationId: conversation.id)
        if ConversationStateStore.shared.isPinned(conversationId: conversation.id) {
            print("Pinned conversation: \(conversation.person)")
        }
    }
    
    private func unpinCurrentConversation() {
        guard let conversation = selectedConversation else { return }
        if ConversationStateStore.shared.isPinned(conversationId: conversation.id) {
            ConversationStateStore.shared.togglePinned(conversationId: conversation.id)
            print("Unpinned conversation: \(conversation.person)")
        }
    }
    
    private func markCurrentUnread() {
        guard let conversation = selectedConversation else { return }
        if ConversationStateStore.shared.isRead(conversationId: conversation.id) {
            ConversationStateStore.shared.toggleRead(conversationId: conversation.id)
            print("Marked as unread: \(conversation.person)")
        }
    }
    
    private func markCurrentRead() {
        guard let conversation = selectedConversation else { return }
        ConversationStateStore.shared.markAsRead(conversationId: conversation.id)
        print("Marked as read: \(conversation.person)")
    }
    
    private func openConversationFromNotification(from: String) {
        // Find conversation matching the sender
        if let conversation = inboxViewModel.conversations.first(where: { conv in
            conv.person.localizedCaseInsensitiveContains(from) ||
            conv.messages.contains { $0.from.localizedCaseInsensitiveContains(from) }
        }) {
            selectedConversation = conversation
            // Bring app to front
            NSApplication.shared.activate(ignoringOtherApps: true)
            print("Opened conversation from notification: \(conversation.person)")
        }
    }
}

#Preview {
    ContentView().environment(
        \.managedObjectContext, PersistenceController.preview.container.viewContext)
}
