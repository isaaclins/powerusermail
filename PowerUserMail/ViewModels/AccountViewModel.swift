import Combine
import Foundation

@MainActor
final class AccountViewModel: ObservableObject {
    @Published private(set) var accounts: [Account] = []
    @Published var selectedAccount: Account?
    @Published var errorMessage: String?
    @Published var isAuthenticating = false

    private var services: [MailProvider: MailService]

    init(services: [MailProvider: MailService]? = nil) {
        if let services {
            self.services = services
        } else {
            var defaults: [MailProvider: MailService] = [:]
            defaults[.gmail] = GmailService()
            defaults[.outlook] = OutlookService()
            self.services = defaults
        }

        // Load stored accounts
        self.accounts = self.services.values.compactMap { $0.account }
        
        // Auto-select the first account if available
        if let firstAccount = self.accounts.first {
            self.selectedAccount = firstAccount
        }
    }

    func authenticate(provider: MailProvider) async {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        defer { isAuthenticating = false }

        guard let service = services[provider] else {
            errorMessage = MailServiceError.unsupported.localizedDescription
            return
        }

        do {
            let account = try await service.authenticate()
            if let existingIndex = accounts.firstIndex(where: { $0.provider == provider }) {
                accounts[existingIndex] = account
            } else {
                accounts.append(account)
            }
            selectedAccount = account
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func service(for provider: MailProvider) -> MailService? {
        services[provider]
    }
}
