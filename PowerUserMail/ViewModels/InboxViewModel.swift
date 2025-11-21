import Foundation
import Combine

@MainActor
final class InboxViewModel: ObservableObject {
    @Published private(set) var threads: [EmailThread] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    @Published var selectedThread: EmailThread?

    private let service: MailService

    init(service: MailService) {
        self.service = service
    }

    func loadInbox() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            threads = try await service.fetchInbox()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func select(thread: EmailThread) {
        selectedThread = thread
    }
}
