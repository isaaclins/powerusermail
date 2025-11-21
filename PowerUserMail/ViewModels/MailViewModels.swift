import Foundation
import Combine

@MainActor
final class ComposeViewModel: ObservableObject {
    @Published var draft = DraftMessage()
    @Published var isSending = false
    @Published var errorMessage: String?

    private let service: MailService

    init(service: MailService) {
        self.service = service
    }

    func sendDraft() async {
        guard !isSending else { return }
        isSending = true
        defer { isSending = false }
        do {
            try await service.send(message: draft)
            draft = DraftMessage()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

@MainActor
final class DetailViewModel: ObservableObject {
    @Published private(set) var message: Email?
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let service: MailService

    init(service: MailService) {
        self.service = service
    }

    func loadMessage(id: String) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            message = try await service.fetchMessage(id: id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
