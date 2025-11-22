import Foundation
import Combine

@MainActor
final class InboxViewModel: ObservableObject {
    @Published private(set) var conversations: [Conversation] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    @Published var selectedConversation: Conversation?

    private let service: MailService

    init(service: MailService) {
        self.service = service
        NotificationCenter.default.addObserver(forName: Notification.Name("ReloadInbox"), object: nil, queue: .main) { [weak self] _ in
            self?.reload()
        }
    }

    func loadInbox() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let threads = try await service.fetchInbox()
            processConversations(from: threads)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func processConversations(from threads: [EmailThread]) {
        // Flatten all messages
        let allMessages = threads.flatMap { $0.messages }
        
        let promotedIDs = PromotedThreadStore.shared.promotedThreadIDs
        
        // 1. Separate Promoted vs Standard
        let promotedMessages = allMessages.filter { promotedIDs.contains($0.threadId) }
        let standardMessages = allMessages.filter { !promotedIDs.contains($0.threadId) }
        
        var finalConversations: [Conversation] = []
        
        // 2. Group Standard by Sender (Person)
        let groupedByPerson = Dictionary(grouping: standardMessages, by: { $0.from })
        for (sender, msgs) in groupedByPerson {
            finalConversations.append(Conversation(
                id: sender,
                person: sender,
                messages: msgs.sorted(by: { $0.receivedAt < $1.receivedAt })
            ))
        }
        
        // 3. Group Promoted by Thread ID (Topic)
        let groupedByThread = Dictionary(grouping: promotedMessages, by: { $0.threadId })
        for (threadId, msgs) in groupedByThread {
            // Use the subject of the first message as the "Person" name (Topic Name)
            // Or maybe prefix it?
            let topic = msgs.first?.subject ?? "Unknown Topic"
            finalConversations.append(Conversation(
                id: threadId,
                person: "Topic: \(topic)", // Distinguish visually
                messages: msgs.sorted(by: { $0.receivedAt < $1.receivedAt })
            ))
        }
        
        // Sort conversations by latest message time
        self.conversations = finalConversations.sorted { c1, c2 in
            guard let m1 = c1.latestMessage, let m2 = c2.latestMessage else { return false }
            return m1.receivedAt > m2.receivedAt
        }
    }
    
    func reload() {
        Task { await loadInbox() }
    }

    func select(conversation: Conversation) {
        selectedConversation = conversation
    }
}
