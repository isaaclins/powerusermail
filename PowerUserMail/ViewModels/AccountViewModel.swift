import Combine
import Foundation

@MainActor
final class AccountViewModel: ObservableObject {
    @Published private(set) var accounts: [Account] = []
    @Published var selectedAccount: Account?
    @Published var errorMessage: String?
    @Published var isAuthenticating = false

    // IMAP configuration state (for the settings form)
    @Published var imapConfig = IMAPConfiguration()
    @Published var showIMAPConfigSheet = false

    // Services keyed by account ID to support multiple accounts per provider
    private var services: [String: MailService] = [:]

    // UserDefaults key for persisting accounts
    private let accountsKey = "savedAccounts"

    init() {
        // Load stored accounts from UserDefaults
        loadAccounts()

        // Auto-select the first account if available
        // Note: Don't auto-select here - let ContentView handle it
        // to ensure proper view lifecycle
        if let firstAccount = self.accounts.first {
            self.selectedAccount = firstAccount
        }
    }

    // MARK: - Persistence

    private func loadAccounts() {
        guard let data = UserDefaults.standard.data(forKey: accountsKey),
            let savedAccounts = try? JSONDecoder().decode([Account].self, from: data)
        else {
            print("📭 No saved accounts found")
            return
        }

        print("📬 Loaded \(savedAccounts.count) saved accounts")
        accounts = savedAccounts

        // Recreate services for each account
        for account in savedAccounts {
            print("🔄 Restoring service for: \(account.emailAddress) (id: \(account.id.uuidString))")
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
        case .imap:
            return IMAPService()
        }
    }

    // MARK: - Authentication

    func authenticate(provider: MailProvider) async {
        // For IMAP, show configuration sheet instead of immediate OAuth
        if provider == .imap {
            showIMAPConfigSheet = true
            return
        }

        await performAuthentication(provider: provider)
    }

    /// Authenticate with IMAP using the current imapConfig
    func authenticateIMAP() async {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        defer { isAuthenticating = false }

        // Validate config
        guard !imapConfig.imapHost.isEmpty else {
            errorMessage = "IMAP server host is required"
            return
        }
        guard !imapConfig.username.isEmpty else {
            errorMessage = "Email/username is required"
            return
        }
        guard !imapConfig.password.isEmpty else {
            errorMessage = "Password is required"
            return
        }

        // Auto-fill SMTP if not provided
        if imapConfig.smtpHost.isEmpty {
            imapConfig.smtpHost = imapConfig.imapHost.replacingOccurrences(
                of: "imap.", with: "smtp.")
        }

        let service = IMAPService(config: imapConfig)

        do {
            let account = try await service.authenticate()

            // Check if this email is already connected
            if let existingIndex = accounts.firstIndex(where: {
                $0.emailAddress.lowercased() == account.emailAddress.lowercased()
            }) {
                accounts[existingIndex] = account
                services[account.id.uuidString] = service
            } else {
                accounts.append(account)
                services[account.id.uuidString] = service
            }

            selectedAccount = account
            saveAccounts()

            // Reset config and close sheet
            imapConfig = IMAPConfiguration()
            showIMAPConfigSheet = false

        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func performAuthentication(provider: MailProvider) async {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        defer { isAuthenticating = false }

        // Create a new service instance for this authentication
        let service = createService(for: provider)

        do {
            let account = try await service.authenticate()

            // Check if this email is already connected
            if let existingIndex = accounts.firstIndex(where: {
                $0.emailAddress.lowercased() == account.emailAddress.lowercased()
            }) {
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
        guard let account = selectedAccount else {
            print("⚠️ service(for:) - No selected account")
            return nil
        }
        let service = services[account.id.uuidString]
        if service == nil {
            print(
                "⚠️ service(for:) - No service found for account \(account.emailAddress) (id: \(account.id.uuidString))"
            )
            print("   Available services: \(services.keys.joined(separator: ", "))")
        }
        return service
    }

    func service(for account: Account) -> MailService? {
        let service = services[account.id.uuidString]
        if service == nil {
            print("⚠️ service(for account:) - No service found for \(account.emailAddress)")
        }
        return service
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
