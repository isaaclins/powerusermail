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

    // Adaptive polling configuration
    private var basePollingInterval: TimeInterval = 60  // 60 seconds base (was 15)
    private var currentPollingInterval: TimeInterval = 60
    private let maxPollingInterval: TimeInterval = 300  // 5 minutes max backoff
    private var consecutiveSuccesses = 0
    private var isRateLimited = false
    private var rateLimitRetryTime: Date?

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

        print(
            "🔄 Configuring account: \(myEmail) (was: \(self.myEmail.isEmpty ? "none" : self.myEmail))"
        )

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
        timer?.invalidate()

        print("⏰ Starting polling with interval: \(Int(currentPollingInterval))s")

        timer = Timer.scheduledTimer(withTimeInterval: currentPollingInterval, repeats: true) {
            [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.loadInbox()
            }
        }
    }

    /// Adjust polling interval based on success/failure
    private func adjustPollingInterval(
        success: Bool, rateLimited: Bool = false, retryAfter: Double? = nil
    ) {
        // Don't restart polling if authentication is broken
        guard !requiresReauthentication else {
            print("⛔ Not adjusting polling - re-authentication required")
            timer?.invalidate()
            timer = nil
            return
        }

        if rateLimited {
            // Rate limited - back off significantly
            if let retry = retryAfter {
                currentPollingInterval = max(retry + 10, maxPollingInterval)  // Wait at least retry-after + buffer
                rateLimitRetryTime = Date().addingTimeInterval(retry)
            } else {
                currentPollingInterval = min(currentPollingInterval * 2, maxPollingInterval)
            }
            isRateLimited = true
            consecutiveSuccesses = 0
            print("🚫 Rate limited, backing off to \(Int(currentPollingInterval))s")
        } else if success {
            consecutiveSuccesses += 1
            isRateLimited = false
            rateLimitRetryTime = nil

            // After 5 consecutive successes, try reducing interval (but not below base)
            if consecutiveSuccesses >= 5 && currentPollingInterval > basePollingInterval {
                currentPollingInterval = max(currentPollingInterval / 1.5, basePollingInterval)
                consecutiveSuccesses = 0
                print("✅ Reducing polling interval to \(Int(currentPollingInterval))s")
            }
        } else {
            // Non-rate-limit failure - modest backoff
            consecutiveSuccesses = 0
            currentPollingInterval = min(currentPollingInterval * 1.5, maxPollingInterval)
            print("⚠️ Request failed, increasing interval to \(Int(currentPollingInterval))s")
        }

        // Restart timer with new interval
        startPolling()
    }

    func loadInbox() async {
        // Don't load if we're already loading, no service, or auth is broken
        guard !isLoading, let service = service, !requiresReauthentication else {
            if requiresReauthentication {
                print("⛔ Skipping inbox load - re-authentication required")
            }
            return
        }

        // Check if we're still in rate limit cooldown
        if let retryTime = rateLimitRetryTime, Date() < retryTime {
            let remaining = retryTime.timeIntervalSinceNow
            print("⏳ Rate limit cooldown: \(Int(remaining))s remaining, skipping fetch")
            return
        }

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

            // Reset rate limit state on success
            isRateLimited = false
            rateLimitRetryTime = nil

            // Adjust polling - success!
            adjustPollingInterval(success: true)
        } catch let error as MailServiceError where error.requiresReauthentication {
            // Authentication failed - need user to sign in again
            handleAuthenticationFailure(error: error)
        } catch APIError.rateLimited(let retryAfter) {
            // Rate limited - back off significantly
            let waitTime = retryAfter ?? 120  // Default to 2 minutes if not specified
            rateLimitRetryTime = Date().addingTimeInterval(waitTime)
            currentPollingInterval = max(waitTime + 30, maxPollingInterval)  // Wait longer than retry-after
            isRateLimited = true
            consecutiveSuccesses = 0

            // Restart timer with longer interval
            timer?.invalidate()
            print(
                "🚫 Rate limited! Will retry in \(Int(waitTime))s (polling now every \(Int(currentPollingInterval))s)"
            )
            startPolling()

            errorMessage = "Rate limited by Gmail. Will retry in \(Int(waitTime)) seconds."
        } catch {
            // Check if this is an auth error that slipped through
            if let mailError = error as? MailServiceError, mailError.requiresReauthentication {
                print("🔐 Auth error caught in fallback handler: \(mailError)")
                handleAuthenticationFailure(error: mailError)
                return
            }

            // Also check for string-based auth errors (just in case)
            let errorDescription = error.localizedDescription.lowercased()
            if errorDescription.contains("re-authentication")
                || errorDescription.contains("token expired")
                || errorDescription.contains("refresh failed")
                || errorDescription.contains("invalid credentials")
            {
                print("🔐 Auth-related error detected from description: \(error)")
                timer?.invalidate()
                timer = nil
                requiresReauthentication = true
                errorMessage = "Please sign in again to continue."
                return
            }

            // Other errors - show message but keep trying
            authFailureCount += 1
            errorMessage = error.localizedDescription
            print("❌ Non-auth error: \(type(of: error)) - \(error)")

            // Adjust polling - failure
            adjustPollingInterval(success: false)

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
        NotificationManager.shared.checkForNewMessages(
            conversations: sortedConversations, myEmail: myEmail)

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
