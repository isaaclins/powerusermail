import Combine
import Foundation

@MainActor
final class InboxViewModel: ObservableObject {
    @Published private(set) var conversations: [Conversation] = []
    @Published private(set) var isLoading = false
    @Published private(set) var loadingProgress: String = ""
    @Published var errorMessage: String?
    @Published var selectedConversation: Conversation?
    
    /// When true, the user needs to sign in again (token expired/revoked)
    @Published private(set) var requiresReauthentication = false
    /// The email that needs re-authentication
    @Published private(set) var reauthEmail: String?

    private var service: MailService?
    private var myEmail: String = ""
    private var timer: Timer?
    private var loadedThreads: [EmailThread] = []
    private var isConfigured = false
    private var authFailureCount = 0
    private let maxAuthFailures = 2  // Stop retrying after this many consecutive failures

    init() {
        NotificationCenter.default.addObserver(
            forName: Notification.Name("ReloadInbox"), object: nil, queue: .main
        ) { [weak self] _ in
            self?.reload()
        }
    }
    
    func configure(service: MailService, myEmail: String) {
        // CRITICAL: Check if this is a different account or same account
        let isSameAccount = isConfigured && self.myEmail.lowercased() == myEmail.lowercased()
        
        // Skip ONLY if exact same account is already fully configured and loaded (and not requiring reauth)
        if isSameAccount && !conversations.isEmpty && !requiresReauthentication {
            print("✓ Same account already configured: \(myEmail)")
            return
        }
        
        print("🔄 Configuring account: \(myEmail) (was: \(self.myEmail.isEmpty ? "none" : self.myEmail))")
        
        // Stop existing polling FIRST
        timer?.invalidate()
        timer = nil
        
        // CRITICAL: ALWAYS clear ALL data when configuring ANY account
        // This ensures complete isolation
        print("🧹 Clearing all cached data for account isolation")
        loadedThreads.removeAll()
        conversations.removeAll()
        selectedConversation = nil
        errorMessage = nil
        loadingProgress = ""
        isLoading = false
        
        // Reset auth state
        requiresReauthentication = false
        reauthEmail = nil
        authFailureCount = 0
        
        // Reset notification manager
        NotificationManager.shared.resetForNewAccount()
        
        // Set new account info
        self.service = service
        self.myEmail = myEmail
        self.isConfigured = true
        
        // Start polling for new account
        startPolling()
        
        // Initial load
        Task { await loadInbox() }
    }
    
    /// Force clear all data (call when signing out or switching accounts)
    func clearAllData() {
        timer?.invalidate()
        timer = nil
        loadedThreads = []
        conversations = []
        selectedConversation = nil
        errorMessage = nil
        loadingProgress = ""
        isLoading = false
        isConfigured = false
        myEmail = ""
        service = nil
        requiresReauthentication = false
        reauthEmail = nil
        authFailureCount = 0
    }
    
    /// Reset authentication state (call after user re-authenticates)
    func resetAuthState() {
        requiresReauthentication = false
        reauthEmail = nil
        authFailureCount = 0
        errorMessage = nil
    }

    deinit {
        timer?.invalidate()
    }

    private func startPolling() {
        timer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.loadInbox()
            }
        }
    }

    func loadInbox() async {
        // Don't load if we're already loading, no service, or auth is broken
        guard !isLoading, let service = service, !requiresReauthentication else { return }
        
        isLoading = true
        errorMessage = nil
        
        // Clear for fresh load, but keep existing if this is a refresh
        let isRefresh = !loadedThreads.isEmpty
        if !isRefresh {
            loadedThreads = []
            conversations = []
        }
        
        var threadCount = 0
        
        do {
            // Use streaming API for progressive loading
            for try await thread in service.fetchInboxStream() {
                threadCount += 1
                loadingProgress = "Loading \(threadCount) conversations..."
                
                // Check if we already have this thread (for refreshes)
                if let existingIndex = loadedThreads.firstIndex(where: { $0.id == thread.id }) {
                    loadedThreads[existingIndex] = thread
                } else {
                    loadedThreads.append(thread)
                }
                
                // Update UI progressively
                processConversations(from: loadedThreads)
            }
            
            loadingProgress = ""
            // Reset failure count on success
            authFailureCount = 0
        } catch let error as MailServiceError where error.requiresReauthentication {
            // Authentication failed - need user to sign in again
            handleAuthenticationFailure(error: error)
        } catch {
            // Other errors - show message but keep trying
            authFailureCount += 1
            errorMessage = error.localizedDescription
            
            // If we've had too many failures, stop polling
            if authFailureCount >= maxAuthFailures {
                print("⚠️ Too many consecutive failures, stopping polling")
                timer?.invalidate()
                timer = nil
            }
        }
        
        isLoading = false
    }
    
    private func handleAuthenticationFailure(error: MailServiceError) {
        print("🔐 Authentication failure detected: \(error.localizedDescription ?? "unknown")")
        
        // Extract email from error if available
        switch error {
        case .tokenExpired(let email), .refreshFailed(let email):
            reauthEmail = email
        default:
            reauthEmail = myEmail
        }
        
        // Stop polling - no point retrying with broken auth
        timer?.invalidate()
        timer = nil
        
        // Set state so UI can show re-auth prompt
        requiresReauthentication = true
        errorMessage = error.localizedDescription
        
        // Post notification for any listeners
        NotificationCenter.default.post(
            name: Notification.Name("AuthenticationRequired"),
            object: nil,
            userInfo: ["email": reauthEmail ?? myEmail]
        )
    }

    private func processConversations(from threads: [EmailThread]) {
        // Flatten all messages
        let allMessages = threads.flatMap { $0.messages }

        let promotedIDs = PromotedThreadStore.shared.promotedThreadIDs

        // 1. Separate Promoted vs Standard
        let promotedMessages = allMessages.filter { promotedIDs.contains($0.threadId) }
        let standardMessages = allMessages.filter { !promotedIDs.contains($0.threadId) }

        var finalConversations: [Conversation] = []

        // 2. Group Standard by Counterpart (Person)
        let groupedByPerson = Dictionary(grouping: standardMessages) { message -> String in
            if message.from.localizedCaseInsensitiveContains(self.myEmail) {
                if let other = message.to.first(where: {
                    !$0.localizedCaseInsensitiveContains(self.myEmail)
                }) {
                    return other
                }
                return message.to.first ?? message.from
            } else {
                return message.from
            }
        }

        for (person, msgs) in groupedByPerson {
            finalConversations.append(
                Conversation(
                    id: person,
                    person: person,
                    messages: msgs.sorted(by: { $0.receivedAt < $1.receivedAt })
                ))
        }

        // 3. Group Promoted by Thread ID (Topic)
        let groupedByThread = Dictionary(grouping: promotedMessages, by: { $0.threadId })
        for (threadId, msgs) in groupedByThread {
            let topic = msgs.first?.subject ?? "Unknown Topic"
            finalConversations.append(
                Conversation(
                    id: threadId,
                    person: "Topic: \(topic)",
                    messages: msgs.sorted(by: { $0.receivedAt < $1.receivedAt })
                ))
        }

        // Sort conversations: pinned first, then by latest message time
        let sortedConversations = finalConversations.sorted { c1, c2 in
            let pinned1 = ConversationStateStore.shared.isPinned(conversationId: c1.id)
            let pinned2 = ConversationStateStore.shared.isPinned(conversationId: c2.id)
            
            // Pinned conversations come first
            if pinned1 != pinned2 {
                return pinned1
            }
            
            // Then sort by latest message time
            guard let m1 = c1.latestMessage, let m2 = c2.latestMessage else { return false }
            return m1.receivedAt > m2.receivedAt
        }
        
        self.conversations = sortedConversations
        
        // Check for new messages and send notifications
        NotificationManager.shared.checkForNewMessages(conversations: sortedConversations, myEmail: myEmail)
        
        // Update badge count with unread count
        let unreadCount = sortedConversations.filter { $0.hasUnread }.count
        NotificationManager.shared.updateBadgeCount(unreadCount)
    }

    func reload() {
        Task { 
            loadedThreads = []  // Force full reload
            await loadInbox() 
        }
    }

    func select(conversation: Conversation) {
        selectedConversation = conversation
    }
}
