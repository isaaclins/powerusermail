import Combine
import Foundation

@MainActor
final class AccountViewModel: ObservableObject {
    @Published private(set) var accounts: [Account] = []
    @Published var selectedAccount: Account?
    @Published var errorMessage: String?
    @Published var isAuthenticating = false

    // Services keyed by account ID to support multiple accounts per provider
    private var services: [String: MailService] = [:]
    
    // UserDefaults key for persisting accounts
    private let accountsKey = "savedAccounts"

    init() {
        // Load stored accounts from UserDefaults
        loadAccounts()
        
        // Auto-select the first account if available
        if let firstAccount = self.accounts.first {
            self.selectedAccount = firstAccount
        }
    }
    
    // MARK: - Persistence
    
    private func loadAccounts() {
        guard let data = UserDefaults.standard.data(forKey: accountsKey),
              let savedAccounts = try? JSONDecoder().decode([Account].self, from: data) else {
            return
        }
        
        accounts = savedAccounts
        
        // Recreate services for each account
        for account in savedAccounts {
            let service = createService(for: account.provider)
            service.restoreAccount(account)
            services[account.id.uuidString] = service
        }
    }
    
    private func saveAccounts() {
        if let data = try? JSONEncoder().encode(accounts) {
            UserDefaults.standard.set(data, forKey: accountsKey)
        }
    }
    
    private func createService(for provider: MailProvider) -> MailService {
        switch provider {
        case .gmail:
            return GmailService()
        case .outlook:
            return OutlookService()
        }
    }

    // MARK: - Authentication

    func authenticate(provider: MailProvider) async {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        defer { isAuthenticating = false }

        // Create a new service instance for this authentication
        let service = createService(for: provider)

        do {
            let account = try await service.authenticate()
            
            // Check if this email is already connected
            if let existingIndex = accounts.firstIndex(where: { $0.emailAddress.lowercased() == account.emailAddress.lowercased() }) {
                // Update existing account
                accounts[existingIndex] = account
                services[account.id.uuidString] = service
            } else {
                // Add new account
                accounts.append(account)
                services[account.id.uuidString] = service
            }
            
            selectedAccount = account
            saveAccounts()
            
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    // MARK: - Account Management

    func service(for provider: MailProvider) -> MailService? {
        guard let account = selectedAccount else { return nil }
        return services[account.id.uuidString]
    }
    
    func service(for account: Account) -> MailService? {
        return services[account.id.uuidString]
    }
    
    func removeAccount(_ account: Account) {
        accounts.removeAll { $0.id == account.id }
        services.removeValue(forKey: account.id.uuidString)
        
        // If we removed the selected account, select another one
        if selectedAccount?.id == account.id {
            selectedAccount = accounts.first
        }
        
        saveAccounts()
    }
    
    func signOutAll() {
        accounts.removeAll()
        services.removeAll()
        selectedAccount = nil
        UserDefaults.standard.removeObject(forKey: accountsKey)
    }
}
