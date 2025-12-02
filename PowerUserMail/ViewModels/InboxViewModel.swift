import Combine
import Foundation

@MainActor
final class InboxViewModel: ObservableObject {
    @Published private(set) var conversations: [Conversation] = []
    @Published private(set) var isLoading = false
    @Published private(set) var loadingProgress: String = ""
    @Published var errorMessage: String?
    @Published var selectedConversation: Conversation?

    private var service: MailService?
    private var myEmail: String = ""
    private var timer: Timer?
    private var loadedThreads: [EmailThread] = []
    private var isConfigured = false

    init() {
        NotificationCenter.default.addObserver(
            forName: Notification.Name("ReloadInbox"), object: nil, queue: .main
        ) { [weak self] _ in
            self?.reload()
        }
    }
    
    func configure(service: MailService, myEmail: String) {
        // Skip if already configured with same values
        if isConfigured && self.myEmail == myEmail { return }
        
        self.service = service
        self.myEmail = myEmail
        self.isConfigured = true
        
        // Reset and start fresh
        timer?.invalidate()
        loadedThreads = []
        conversations = []
        
        // Start polling
        startPolling()
        
        // Initial load
        Task { await loadInbox() }
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
        guard !isLoading, let service = service else { return }
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
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
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
