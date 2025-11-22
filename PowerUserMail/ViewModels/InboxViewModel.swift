import Combine
import Foundation

@MainActor
final class InboxViewModel: ObservableObject {
    @Published private(set) var conversations: [Conversation] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    @Published var selectedConversation: Conversation?

    private let service: MailService
    private let myEmail: String
    private var timer: Timer?

    init(service: MailService, myEmail: String) {
        self.service = service
        self.myEmail = myEmail
        NotificationCenter.default.addObserver(
            forName: Notification.Name("ReloadInbox"), object: nil, queue: .main
        ) { [weak self] _ in
            self?.reload()
        }

        // Start polling every 15 seconds
        startPolling()
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

        // 2. Group Standard by Counterpart (Person)
        // If I am the sender, group by the recipient. If I am the receiver, group by the sender.
        let groupedByPerson = Dictionary(grouping: standardMessages) { message -> String in
            if message.from.localizedCaseInsensitiveContains(self.myEmail) {
                // I sent this. Who did I send it to?
                // Try to find a recipient that isn't me
                if let other = message.to.first(where: {
                    !$0.localizedCaseInsensitiveContains(self.myEmail)
                }) {
                    return other
                }
                // If I sent it to myself, or no other recipients found
                return message.to.first ?? message.from
            } else {
                // Someone sent it to me. Group by sender.
                return message.from
            }
        }

        for (person, msgs) in groupedByPerson {
            finalConversations.append(
                Conversation(
                    id: person,  // Use the person's email as the ID for the conversation
                    person: person,
                    messages: msgs.sorted(by: { $0.receivedAt < $1.receivedAt })
                ))
        }

        // 3. Group Promoted by Thread ID (Topic)
        let groupedByThread = Dictionary(grouping: promotedMessages, by: { $0.threadId })
        for (threadId, msgs) in groupedByThread {
            // Use the subject of the first message as the "Person" name (Topic Name)
            // Or maybe prefix it?
            let topic = msgs.first?.subject ?? "Unknown Topic"
            finalConversations.append(
                Conversation(
                    id: threadId,
                    person: "Topic: \(topic)",  // Distinguish visually
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
