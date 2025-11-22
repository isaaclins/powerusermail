import AuthenticationServices
import CryptoKit
import Foundation

enum MailServiceError: Error, LocalizedError {
    case authenticationRequired
    case invalidResponse
    case networkFailure
    case unsupported
    case custom(String)

    var errorDescription: String? {
        switch self {
        case .authenticationRequired:
            return "Authentication required."
        case .invalidResponse:
            return "Received invalid data from server."
        case .networkFailure:
            return "Network request failed."
        case .unsupported:
            return "Operation unsupported by provider."
        case .custom(let message):
            return message
        }
    }
}

protocol MailService {
    var provider: MailProvider { get }
    var account: Account? { get }
    var isAuthenticated: Bool { get }
    func authenticate() async throws -> Account
    func fetchInbox() async throws -> [EmailThread]
    func fetchMessage(id: String) async throws -> Email
    func send(message: DraftMessage) async throws
    func archive(id: String) async throws
}

// MARK: - Persistence Helpers (Keychain + UserDefaults)

final class KeychainHelper {
    static let shared = KeychainHelper()

    func save(_ string: String, account: String) {
        guard let data = string.data(using: .utf8) else { return }
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: account,
            kSecValueData: data,
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    func read(account: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: account,
            kSecReturnData: kCFBooleanTrue!,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data,
            let str = String(data: data, encoding: .utf8)
        else { return nil }
        return str
    }

    func delete(account: String) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword, kSecAttrAccount: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

private func accessTokenKey(for provider: MailProvider) -> String {
    "powerusermail.\(provider.rawValue).accessToken"
}
private func refreshTokenKey(for provider: MailProvider) -> String {
    "powerusermail.\(provider.rawValue).refreshToken"
}
private func emailKey(for provider: MailProvider) -> String {
    "powerusermail.\(provider.rawValue).email"
}
private func expiryKey(for provider: MailProvider) -> String {
    "powerusermail.\(provider.rawValue).expiry"
}

private func storeTokensForProvider(
    _ provider: MailProvider, accessToken: String, refreshToken: String?, expiresIn: Int?
) {
    KeychainHelper.shared.save(accessToken, account: accessTokenKey(for: provider))
    if let refresh = refreshToken {
        KeychainHelper.shared.save(refresh, account: refreshTokenKey(for: provider))
    }
    if let expires = expiresIn {
        let expiry = Date().addingTimeInterval(TimeInterval(expires))
        UserDefaults.standard.set(expiry.timeIntervalSince1970, forKey: expiryKey(for: provider))
    }
}

private func loadStoredAccount(for provider: MailProvider) -> Account? {
    guard let access = KeychainHelper.shared.read(account: accessTokenKey(for: provider)) else {
        return nil
    }
    let refresh = KeychainHelper.shared.read(account: refreshTokenKey(for: provider))
    let email = KeychainHelper.shared.read(account: emailKey(for: provider)) ?? ""
    return Account(
        provider: provider, emailAddress: email, displayName: "", accessToken: access,
        refreshToken: refresh, lastSyncDate: nil, isAuthenticated: true)
}

private func saveEmailForProvider(_ provider: MailProvider, email: String) {
    KeychainHelper.shared.save(email, account: emailKey(for: provider))
}

private func accessTokenExpiry(for provider: MailProvider) -> Date? {
    guard let ts = UserDefaults.standard.value(forKey: expiryKey(for: provider)) as? TimeInterval
    else { return nil }
    return Date(timeIntervalSince1970: ts)
}

// MARK: - OAuth Configuration & Helpers

struct OAuthConfiguration {
    let authEndpoint: String
    let tokenEndpoint: String
    let clientId: String
    let redirectUri: String
    let scopes: [String]
}

struct PKCE {
    let codeVerifier: String
    let codeChallenge: String

    init() {
        var buffer = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, buffer.count, &buffer)
        self.codeVerifier = Data(buffer).base64URLEncodedString()

        let data = Data(codeVerifier.utf8)
        let hashed = SHA256.hash(data: data)
        self.codeChallenge = Data(hashed).base64URLEncodedString()
    }
}

extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - API Response Models

// Gmail Models
struct GmailProfile: Codable {
    let emailAddress: String
    let messagesTotal: Int
    let threadsTotal: Int
    let historyId: String
}

struct GmailThreadListResponse: Codable {
    let threads: [GmailThreadSummary]?
    let nextPageToken: String?
    let resultSizeEstimate: Int?
}

struct GmailThreadSummary: Codable {
    let id: String
    let snippet: String?
    let historyId: String?
}

struct GmailThreadDetail: Codable {
    let id: String
    let messages: [GmailMessage]
}

struct GmailMessage: Codable {
    let id: String
    let threadId: String
    let snippet: String?
    let payload: GmailMessagePayload?
    let internalDate: String?
}

struct GmailMessagePayload: Codable {
    let headers: [GmailHeader]?
    let body: GmailBody?
    let parts: [GmailMessagePart]?
}

struct GmailHeader: Codable {
    let name: String
    let value: String
}

struct GmailBody: Codable {
    let data: String?
    let size: Int?
}

struct GmailMessagePart: Codable {
    let partId: String?
    let mimeType: String?
    let filename: String?
    let headers: [GmailHeader]?
    let body: GmailBody?
    let parts: [GmailMessagePart]?
}

// Outlook Models
struct OutlookProfile: Codable {
    let displayName: String?
    let mail: String?
    let userPrincipalName: String?
}

struct OutlookMessageListResponse: Codable {
    let value: [OutlookMessage]
    let nextLink: String?

    enum CodingKeys: String, CodingKey {
        case value
        case nextLink = "@odata.nextLink"
    }
}

struct OutlookMessage: Codable {
    let id: String
    let conversationId: String?
    let subject: String?
    let bodyPreview: String?
    let body: OutlookBody?
    let from: OutlookRecipient?
    let toRecipients: [OutlookRecipient]?
    let receivedDateTime: String?
    let isRead: Bool?
}

struct OutlookBody: Codable {
    let contentType: String?
    let content: String?
}

struct OutlookRecipient: Codable {
    let emailAddress: OutlookEmailAddress?
}

struct OutlookEmailAddress: Codable {
    let name: String?
    let address: String?
}

// MARK: - Services

final class GmailService: NSObject, MailService {
    private(set) var account: Account?
    var provider: MailProvider { .gmail }
    var isAuthenticated: Bool { account?.isAuthenticated == true }

    override init() {
        super.init()
        if let stored = loadStoredAccount(for: .gmail) {
            account = stored
        }
    }

    // TODO: Replace with your actual Google Client ID and Redirect URI
    private let config = OAuthConfiguration(
        authEndpoint: "https://accounts.google.com/o/oauth2/v2/auth",
        tokenEndpoint: "https://oauth2.googleapis.com/token",
        clientId: "684667393164-oev1qt9hrou3fd7jgssivfdh1ccth2l6.apps.googleusercontent.com",
        redirectUri:
            "com.googleusercontent.apps.684667393164-oev1qt9hrou3fd7jgssivfdh1ccth2l6:/oauth2redirect",
        scopes: ["https://mail.google.com/"]
    )

    func authenticate() async throws -> Account {
        let tokens = try await performOAuthFlow(config: config, provider: provider)

        // Fetch User Profile
        let profileURL = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/profile")!
        var request = URLRequest(url: profileURL)
        request.setValue("Bearer \(tokens.accessToken)", forHTTPHeaderField: "Authorization")

        let profile: GmailProfile = try await URLSession.shared.data(for: request)

        let newAccount = Account(
            provider: provider, emailAddress: profile.emailAddress, displayName: "Gmail User",
            accessToken: tokens.accessToken, refreshToken: tokens.refreshToken,
            isAuthenticated: true)
        account = newAccount

        // Persist email + tokens
        saveEmailForProvider(provider, email: profile.emailAddress)
        storeTokensForProvider(
            provider, accessToken: tokens.accessToken, refreshToken: tokens.refreshToken,
            expiresIn: tokens.expiresIn)

        return newAccount
    }

    func fetchInbox() async throws -> [EmailThread] {
        guard account != nil else { throw MailServiceError.authenticationRequired }

        // Ensure valid access token (refresh if needed)
        let token = try await ensureValidAccessToken(for: provider, config: config)

        var allThreads: [EmailThread] = []
        var nextPageToken: String? = nil

        // Safety limit to prevent infinite loops during dev
        let maxPages = 5
        var pageCount = 0

        repeat {
            var components = URLComponents(
                string: "https://gmail.googleapis.com/gmail/v1/users/me/threads")!
            var queryItems = [URLQueryItem(name: "maxResults", value: "20")]
            if let pageToken = nextPageToken {
                queryItems.append(URLQueryItem(name: "pageToken", value: pageToken))
            }
            components.queryItems = queryItems

            var listRequest = URLRequest(url: components.url!)
            listRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            let listResponse: GmailThreadListResponse = try await URLSession.shared.data(
                for: listRequest)

            nextPageToken = listResponse.nextPageToken

            if let threads = listResponse.threads {
                // Fetch details for this batch
                await withTaskGroup(of: EmailThread?.self) { group in
                    for threadSummary in threads {
                        group.addTask {
                            do {
                                let detailURL = URL(
                                    string:
                                        "https://gmail.googleapis.com/gmail/v1/users/me/threads/\(threadSummary.id)"
                                )!
                                var detailRequest = URLRequest(url: detailURL)
                                detailRequest.setValue(
                                    "Bearer \(token)", forHTTPHeaderField: "Authorization")
                                let threadDetail: GmailThreadDetail = try await URLSession.shared
                                    .data(for: detailRequest)

                                let messages = threadDetail.messages.map {
                                    self.mapGmailMessage($0)
                                }
                                let subject = messages.first?.subject ?? "No Subject"
                                let participants = Array(
                                    Set(messages.map { $0.from } + messages.flatMap { $0.to }))

                                return EmailThread(
                                    id: threadDetail.id, subject: subject, messages: messages,
                                    participants: participants)
                            } catch {
                                print("Failed to fetch thread details: \(error)")
                                return nil
                            }
                        }
                    }

                    for await thread in group {
                        if let thread = thread {
                            allThreads.append(thread)
                        }
                    }
                }
            }

            pageCount += 1
        } while nextPageToken != nil && pageCount < maxPages

        return allThreads
    }

    private func mapGmailMessage(_ msg: GmailMessage) -> Email {
        let headers = msg.payload?.headers ?? []
        let subject =
            headers.first(where: { $0.name.lowercased() == "subject" })?.value ?? "(No Subject)"
        let from = headers.first(where: { $0.name.lowercased() == "from" })?.value ?? "Unknown"
        let to =
            headers.first(where: { $0.name.lowercased() == "to" })?.value.components(
                separatedBy: ",") ?? []

        var body = msg.snippet ?? ""
        if let parts = msg.payload?.parts {
            for part in parts {
                if part.mimeType == "text/plain", let data = part.body?.data {
                    body = data.base64UrlDecoded() ?? body
                }
            }
        } else if let data = msg.payload?.body?.data {
            body = data.base64UrlDecoded() ?? body
        }

        let dateStr = msg.internalDate ?? "0"
        let date = Date(timeIntervalSince1970: (Double(dateStr) ?? 0) / 1000)

        return Email(
            id: msg.id,
            threadId: msg.threadId,
            subject: subject,
            from: from,
            to: to,
            preview: msg.snippet ?? "",
            body: body,
            receivedAt: date
        )
    }

    func fetchMessage(id: String) async throws -> Email {
        guard let account = account else { throw MailServiceError.authenticationRequired }
        let url = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages/\(id)")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(account.accessToken)", forHTTPHeaderField: "Authorization")

        let msg: GmailMessage = try await URLSession.shared.data(for: request)
        return mapGmailMessage(msg)
    }

    func send(message: DraftMessage) async throws {
        guard let account = account else { throw MailServiceError.authenticationRequired }

        // Ensure valid access token
        let token = try await ensureValidAccessToken(for: provider, config: config)

        let url = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages/send")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Construct MIME message
        var mime = ""
        if !message.to.isEmpty { mime += "To: \(message.to.joined(separator: ", "))\r\n" }
        if !message.cc.isEmpty { mime += "Cc: \(message.cc.joined(separator: ", "))\r\n" }
        if !message.bcc.isEmpty { mime += "Bcc: \(message.bcc.joined(separator: ", "))\r\n" }

        mime += "Subject: \(message.subject)\r\n"
        mime += "Content-Type: text/plain; charset=\"UTF-8\"\r\n\r\n"
        mime += message.body

        guard let mimeData = mime.data(using: .utf8) else {
            throw MailServiceError.custom("Failed to encode message")
        }

        let raw = mimeData.base64URLEncodedString()
        let body = ["raw": raw]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
            (200...299).contains(httpResponse.statusCode)
        else {
            throw MailServiceError.custom("Failed to send email")
        }
    }

    func archive(id: String) async throws {
        guard isAuthenticated else { throw MailServiceError.authenticationRequired }
    }
}

final class OutlookService: NSObject, MailService {
    private(set) var account: Account?
    var provider: MailProvider { .outlook }
    var isAuthenticated: Bool { account?.isAuthenticated == true }

    override init() {
        super.init()
        if let stored = loadStoredAccount(for: .outlook) {
            account = stored
        }
    }

    // TODO: Replace with your actual Microsoft Client ID and Redirect URI
    private let config = OAuthConfiguration(
        authEndpoint: "https://login.microsoftonline.com/common/oauth2/v2.0/authorize",
        tokenEndpoint: "https://login.microsoftonline.com/common/oauth2/v2.0/token",
        clientId: "YOUR_MICROSOFT_CLIENT_ID",
        redirectUri: "msauth.com.isaaclins.PowerUserMail://auth",
        scopes: [
            "https://graph.microsoft.com/mail.read", "https://graph.microsoft.com/mail.send",
            "offline_access", "User.Read",
        ]
    )

    func authenticate() async throws -> Account {
        let tokens = try await performOAuthFlow(config: config, provider: provider)

        // Fetch User Profile
        let profileURL = URL(string: "https://graph.microsoft.com/v1.0/me")!
        var request = URLRequest(url: profileURL)
        request.setValue("Bearer \(tokens.accessToken)", forHTTPHeaderField: "Authorization")

        let profile: OutlookProfile = try await URLSession.shared.data(for: request)

        let email = profile.mail ?? profile.userPrincipalName ?? "user@outlook.com"
        let name = profile.displayName ?? "Outlook User"

        let newAccount = Account(
            provider: provider, emailAddress: email, displayName: name,
            accessToken: tokens.accessToken, refreshToken: tokens.refreshToken,
            isAuthenticated: true)
        account = newAccount

        // Persist email + tokens
        saveEmailForProvider(provider, email: email)
        storeTokensForProvider(
            provider, accessToken: tokens.accessToken, refreshToken: tokens.refreshToken,
            expiresIn: tokens.expiresIn)

        return newAccount
    }

    func fetchInbox() async throws -> [EmailThread] {
        guard account != nil else { throw MailServiceError.authenticationRequired }

        // Ensure valid access token (refresh if needed)
        let token = try await ensureValidAccessToken(for: provider, config: config)

        var allMessages: [OutlookMessage] = []
        var nextLink: String? =
            "https://graph.microsoft.com/v1.0/me/mailFolders/inbox/messages?$top=50&$select=id,conversationId,subject,bodyPreview,body,from,toRecipients,receivedDateTime,isRead"

        let maxPages = 5
        var pageCount = 0

        while let link = nextLink, pageCount < maxPages {
            var request = URLRequest(url: URL(string: link)!)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            let response: OutlookMessageListResponse = try await URLSession.shared.data(
                for: request)
            allMessages.append(contentsOf: response.value)
            nextLink = response.nextLink
            pageCount += 1
        }

        // Group by conversationId
        let grouped = Dictionary(
            grouping: allMessages, by: { $0.conversationId ?? UUID().uuidString })

        return grouped.map { (conversationId, messages) in
            let mappedMessages = messages.map { mapOutlookMessage($0) }
            let subject = mappedMessages.first?.subject ?? "No Subject"
            let participants = Array(
                Set(mappedMessages.map { $0.from } + mappedMessages.flatMap { $0.to }))

            return EmailThread(
                id: conversationId, subject: subject, messages: mappedMessages,
                participants: participants)
        }
    }

    private func mapOutlookMessage(_ msg: OutlookMessage) -> Email {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = formatter.date(from: msg.receivedDateTime ?? "") ?? Date()

        return Email(
            id: msg.id,
            threadId: msg.conversationId ?? "",
            subject: msg.subject ?? "(No Subject)",
            from: msg.from?.emailAddress?.address ?? "Unknown",
            to: (msg.toRecipients ?? []).compactMap { $0.emailAddress?.address },
            preview: msg.bodyPreview ?? "",
            body: msg.body?.content ?? "",
            receivedAt: date,
            isRead: msg.isRead ?? false
        )
    }

    func fetchMessage(id: String) async throws -> Email {
        guard let account = account else { throw MailServiceError.authenticationRequired }
        let url = URL(string: "https://graph.microsoft.com/v1.0/me/messages/\(id)")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(account.accessToken)", forHTTPHeaderField: "Authorization")

        let msg: OutlookMessage = try await URLSession.shared.data(for: request)
        return mapOutlookMessage(msg)
    }

    func send(message: DraftMessage) async throws {
        guard let account = account else { throw MailServiceError.authenticationRequired }

        // Ensure valid access token
        let token = try await ensureValidAccessToken(for: provider, config: config)

        let url = URL(string: "https://graph.microsoft.com/v1.0/me/sendMail")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let messageDict: [String: Any] = [
            "subject": message.subject,
            "body": [
                "contentType": "Text",
                "content": message.body,
            ],
            "toRecipients": message.to.map { ["emailAddress": ["address": $0]] },
            "ccRecipients": message.cc.map { ["emailAddress": ["address": $0]] },
            "bccRecipients": message.bcc.map { ["emailAddress": ["address": $0]] },
        ]

        let body: [String: Any] = [
            "message": messageDict,
            "saveToSentItems": true,
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
            (200...299).contains(httpResponse.statusCode)
        else {
            throw MailServiceError.custom("Failed to send email")
        }
    }

    func archive(id: String) async throws {
        guard isAuthenticated else { throw MailServiceError.authenticationRequired }
    }
}

extension String {
    func base64UrlDecoded() -> String? {
        var base64 =
            self
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 {
            base64.append("=")
        }
        guard let data = Data(base64Encoded: base64) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

// MARK: - OAuth Implementation

struct TokenResponse: Codable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }
}

extension MailService {
    // Helper to perform the full OAuth flow
    func performOAuthFlow(config: OAuthConfiguration, provider: MailProvider) async throws
        -> TokenResponse
    {
        let pkce = PKCE()

        // 1. Construct Authorization URL
        var components = URLComponents(string: config.authEndpoint)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: config.clientId),
            URLQueryItem(name: "redirect_uri", value: config.redirectUri),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: config.scopes.joined(separator: " ")),
            URLQueryItem(name: "code_challenge", value: pkce.codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]

        // Request offline access for providers that support refresh tokens (Google)
        if provider == .gmail || config.authEndpoint.contains("accounts.google.com") {
            components.queryItems?.append(URLQueryItem(name: "access_type", value: "offline"))
            components.queryItems?.append(URLQueryItem(name: "prompt", value: "consent"))
        }

        guard let authURL = components.url else {
            throw MailServiceError.custom("Invalid auth URL")
        }

        // 2. Present ASWebAuthenticationSession
        let callbackURL = try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<URL, Error>) in
            let session = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: URL(string: config.redirectUri)?.scheme
            ) { callbackURL, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let callbackURL = callbackURL else {
                    continuation.resume(throwing: MailServiceError.invalidResponse)
                    return
                }
                continuation.resume(returning: callbackURL)
            }

            session.presentationContextProvider =
                self as? ASWebAuthenticationPresentationContextProviding
            session.prefersEphemeralWebBrowserSession = true
            session.start()
        }

        // 3. Extract Authorization Code
        guard
            let code = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "code" })?.value
        else {
            throw MailServiceError.custom("No authorization code found")
        }

        // 4. Exchange Code for Tokens
        let tokens = try await exchangeCodeForToken(code: code, pkce: pkce, config: config)

        // Persist tokens for this provider
        storeTokensForProvider(
            provider, accessToken: tokens.accessToken, refreshToken: tokens.refreshToken,
            expiresIn: tokens.expiresIn)

        return tokens
    }

    // Exchange a refresh token for a new access token
    func refreshAccessToken(refreshToken: String, config: OAuthConfiguration) async throws
        -> TokenResponse
    {
        var request = URLRequest(url: URL(string: config.tokenEndpoint)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let bodyParams = [
            "client_id": config.clientId,
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
        ]

        var comps = URLComponents()
        comps.queryItems = bodyParams.map { URLQueryItem(name: $0.key, value: $0.value) }
        request.httpBody = comps.query?.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            if let errorText = String(data: data, encoding: .utf8) {
                print("Refresh token exchange failed: \(errorText)")
            }
            throw MailServiceError.custom("Refresh token exchange failed")
        }

        let decoder = JSONDecoder()
        let tokenResp = try decoder.decode(TokenResponse.self, from: data)
        return tokenResp
    }

    // Ensure we have a valid access token for this provider (refresh if expired)
    func ensureValidAccessToken(for provider: MailProvider, config: OAuthConfiguration) async throws
        -> String
    {
        if let expiry = accessTokenExpiry(for: provider), expiry > Date(),
            let access = KeychainHelper.shared.read(account: accessTokenKey(for: provider))
        {
            return access
        }

        // Try to refresh
        guard let refresh = KeychainHelper.shared.read(account: refreshTokenKey(for: provider))
        else {
            throw MailServiceError.authenticationRequired
        }

        let newTokens = try await refreshAccessToken(refreshToken: refresh, config: config)
        storeTokensForProvider(
            provider, accessToken: newTokens.accessToken,
            refreshToken: newTokens.refreshToken ?? refresh, expiresIn: newTokens.expiresIn)

        return newTokens.accessToken
    }

    private func exchangeCodeForToken(code: String, pkce: PKCE, config: OAuthConfiguration)
        async throws -> TokenResponse
    {
        var request = URLRequest(url: URL(string: config.tokenEndpoint)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let bodyParams = [
            "client_id": config.clientId,
            "code": code,
            "redirect_uri": config.redirectUri,
            "grant_type": "authorization_code",
            "code_verifier": pkce.codeVerifier,
        ]

        request.httpBody =
            bodyParams
            .map {
                "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
            }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            if let errorText = String(data: data, encoding: .utf8) {
                print("Token exchange failed: \(errorText)")
            }
            throw MailServiceError.custom("Token exchange failed")
        }

        let decoder = JSONDecoder()
        return try decoder.decode(TokenResponse.self, from: data)
    }
}

extension GmailService: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApplication.shared.windows.first ?? ASPresentationAnchor()
    }
}

extension OutlookService: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApplication.shared.windows.first ?? ASPresentationAnchor()
    }
}

enum MockMailData {
    static func sampleEmail(id: String) -> Email {
        Email(
            id: id, threadId: "thread-\(id)", subject: "Subject \(id)", from: "sender@example.com",
            to: ["user@example.com"], preview: "Preview text", body: "Full email body",
            receivedAt: Date().addingTimeInterval(Double.random(in: -3600...0)))
    }

    static var sampleThreads: [EmailThread] {
        (0..<10).map { idx in
            let email = sampleEmail(id: "email-\(idx)")
            return EmailThread(
                id: "thread-\(idx)", subject: "Thread \(idx)", messages: [email],
                participants: [email.from] + email.to)
        }
    }
}

extension URLSession {
    fileprivate func data<T: Decodable>(for request: URLRequest) async throws -> T {
        let (data, response) = try await self.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw MailServiceError.networkFailure
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            if let errorText = String(data: data, encoding: .utf8) {
                print("Request failed: \(httpResponse.statusCode), body: \(errorText)")
            }
            if httpResponse.statusCode == 401 {
                throw MailServiceError.authenticationRequired
            }
            throw MailServiceError.custom("Request failed with status \(httpResponse.statusCode)")
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            print("Decoding error: \(error)")
            if let text = String(data: data, encoding: .utf8) {
                print("Received data: \(text)")
            }
            throw error
        }
    }
}
