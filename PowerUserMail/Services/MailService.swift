import AuthenticationServices
import CryptoKit
import Foundation
import Network

enum MailServiceError: Error, LocalizedError {
    case authenticationRequired
    case tokenExpired(email: String)  // Token is invalid/expired and needs re-auth
    case refreshFailed(email: String)  // Refresh token failed - need full re-auth
    case invalidResponse
    case networkFailure
    case unsupported
    case custom(String)

    var errorDescription: String? {
        switch self {
        case .authenticationRequired:
            return "Authentication required."
        case .tokenExpired(let email):
            return "Your session for \(email) has expired. Please sign in again."
        case .refreshFailed(let email):
            return "Unable to refresh credentials for \(email). Please sign in again to continue."
        case .invalidResponse:
            return "Received invalid data from server."
        case .networkFailure:
            return "Network request failed. Please check your connection."
        case .unsupported:
            return "Operation unsupported by provider."
        case .custom(let message):
            return message
        }
    }

    /// Whether this error requires the user to re-authenticate
    var requiresReauthentication: Bool {
        switch self {
        case .authenticationRequired, .tokenExpired, .refreshFailed:
            return true
        default:
            return false
        }
    }
}

protocol MailService {
    var provider: MailProvider { get }
    var account: Account? { get }
    var isAuthenticated: Bool { get }
    func authenticate() async throws -> Account
    func restoreAccount(_ account: Account)  // Restore a previously authenticated account
    func fetchInbox() async throws -> [EmailThread]
    func fetchInboxStream() -> AsyncThrowingStream<EmailThread, Error>
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

// MARK: - Account-specific keychain keys (supports multiple accounts per provider)

private func accessTokenKey(for provider: MailProvider, email: String) -> String {
    "powerusermail.\(provider.rawValue).\(email.lowercased()).accessToken"
}
private func refreshTokenKey(for provider: MailProvider, email: String) -> String {
    "powerusermail.\(provider.rawValue).\(email.lowercased()).refreshToken"
}
private func expiryKey(for provider: MailProvider, email: String) -> String {
    "powerusermail.\(provider.rawValue).\(email.lowercased()).expiry"
}

// Legacy keys (for backward compatibility - will be migrated)
private func legacyAccessTokenKey(for provider: MailProvider) -> String {
    "powerusermail.\(provider.rawValue).accessToken"
}
private func legacyRefreshTokenKey(for provider: MailProvider) -> String {
    "powerusermail.\(provider.rawValue).refreshToken"
}
private func legacyEmailKey(for provider: MailProvider) -> String {
    "powerusermail.\(provider.rawValue).email"
}
private func legacyExpiryKey(for provider: MailProvider) -> String {
    "powerusermail.\(provider.rawValue).expiry"
}

private func storeTokensForAccount(
    provider: MailProvider, email: String, accessToken: String, refreshToken: String?,
    expiresIn: Int?
) {
    print("💾 Storing tokens for \(email)")
    print("   📝 Access token: \(accessToken.prefix(20))...")
    print(
        "   🔄 Refresh token: \(refreshToken != nil ? "present (\(refreshToken!.prefix(20))...)" : "❌ MISSING")"
    )
    KeychainHelper.shared.save(accessToken, account: accessTokenKey(for: provider, email: email))
    if let refresh = refreshToken {
        KeychainHelper.shared.save(refresh, account: refreshTokenKey(for: provider, email: email))
        print("   ✅ Refresh token saved to keychain")
    } else {
        print("   ⚠️ No refresh token to store - Google may not have returned one")
    }
    if let expires = expiresIn {
        let expiry = Date().addingTimeInterval(TimeInterval(expires))
        UserDefaults.standard.set(
            expiry.timeIntervalSince1970, forKey: expiryKey(for: provider, email: email))
    }
}

/// Clear only the access token for an account (keep refresh token since it's still valid)
private func clearAccessTokenForAccount(provider: MailProvider, email: String) {
    print("🗑️ Clearing invalid access token for \(email) (keeping refresh token)")
    KeychainHelper.shared.delete(account: accessTokenKey(for: provider, email: email))
    UserDefaults.standard.removeObject(forKey: expiryKey(for: provider, email: email))
}

/// Clear ALL tokens for an account (only when refresh token is proven invalid)
private func clearTokensForAccount(provider: MailProvider, email: String) {
    print("🗑️ Clearing ALL tokens for \(email) (refresh token is invalid)")
    KeychainHelper.shared.delete(account: accessTokenKey(for: provider, email: email))
    KeychainHelper.shared.delete(account: refreshTokenKey(for: provider, email: email))
    UserDefaults.standard.removeObject(forKey: expiryKey(for: provider, email: email))
}

private func accessTokenExpiry(for provider: MailProvider, email: String) -> Date? {
    let interval = UserDefaults.standard.double(forKey: expiryKey(for: provider, email: email))
    return interval > 0 ? Date(timeIntervalSince1970: interval) : nil
}

// Legacy function - kept for backward compatibility during migration
private func storeTokensForProvider(
    _ provider: MailProvider, accessToken: String, refreshToken: String?, expiresIn: Int?
) {
    KeychainHelper.shared.save(accessToken, account: legacyAccessTokenKey(for: provider))
    if let refresh = refreshToken {
        KeychainHelper.shared.save(refresh, account: legacyRefreshTokenKey(for: provider))
    }
    if let expires = expiresIn {
        let expiry = Date().addingTimeInterval(TimeInterval(expires))
        UserDefaults.standard.set(
            expiry.timeIntervalSince1970, forKey: legacyExpiryKey(for: provider))
    }
}

// Legacy functions - kept for backward compatibility but NOT used for multi-account
private func loadStoredAccount(for provider: MailProvider) -> Account? {
    guard let access = KeychainHelper.shared.read(account: legacyAccessTokenKey(for: provider))
    else {
        return nil
    }
    let refresh = KeychainHelper.shared.read(account: legacyRefreshTokenKey(for: provider))
    let email = KeychainHelper.shared.read(account: legacyEmailKey(for: provider)) ?? ""
    return Account(
        provider: provider, emailAddress: email, displayName: "", accessToken: access,
        refreshToken: refresh, lastSyncDate: nil, isAuthenticated: true)
}

private func saveEmailForProvider(_ provider: MailProvider, email: String) {
    KeychainHelper.shared.save(email, account: legacyEmailKey(for: provider))
}

private func accessTokenExpiry(for provider: MailProvider) -> Date? {
    guard
        let ts = UserDefaults.standard.value(forKey: legacyExpiryKey(for: provider))
            as? TimeInterval
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

struct GoogleUserInfo: Codable {
    let email: String?
    let name: String?
    let picture: String?
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
        // Don't auto-load - let AccountViewModel manage this
    }

    func restoreAccount(_ account: Account) {
        print("🔄 Gmail: Restoring account \(account.emailAddress)")
        self.account = account

        // Get refresh token - prefer existing one in keychain over account's (might be stale)
        var refreshTokenToStore = account.refreshToken
        if refreshTokenToStore == nil || refreshTokenToStore?.isEmpty == true {
            // Try to get existing refresh token from keychain
            if let existing = KeychainHelper.shared.read(
                account: refreshTokenKey(for: provider, email: account.emailAddress)),
                !existing.isEmpty
            {
                refreshTokenToStore = existing
                print("   ♻️ Using existing refresh token from keychain")
            }
        }

        // Restore tokens to keychain with EMAIL-SPECIFIC keys
        if !account.accessToken.isEmpty {
            storeTokensForAccount(
                provider: provider,
                email: account.emailAddress,
                accessToken: account.accessToken,
                refreshToken: refreshTokenToStore,
                expiresIn: 3600  // Will refresh if needed
            )
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

        // Fetch User Profile with rate limit handling
        let profileURL = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/profile")!
        var request = URLRequest(url: profileURL)
        request.setValue("Bearer \(tokens.accessToken)", forHTTPHeaderField: "Authorization")

        let (profileData, profileResponse) = try await URLSession.shared.data(for: request)

        // Check for rate limit on profile fetch
        if let httpResponse = profileResponse as? HTTPURLResponse, httpResponse.statusCode == 429 {
            let retrySeconds = parseRetryAfter(response: httpResponse, data: profileData)
            let waitMinutes = Int((retrySeconds ?? 60) / 60)
            throw MailServiceError.custom(
                "Gmail is temporarily rate limiting requests. Please wait \(waitMinutes) minute(s) and try again."
            )
        }

        guard let httpResponse = profileResponse as? HTTPURLResponse,
            (200...299).contains(httpResponse.statusCode)
        else {
            throw MailServiceError.custom("Failed to fetch Gmail profile")
        }

        let profile = try JSONDecoder().decode(GmailProfile.self, from: profileData)

        // Try to fetch profile picture from Google userinfo endpoint
        var profilePictureURL: String? = nil
        var displayName = "Gmail User"

        do {
            let userInfoURL = URL(string: "https://www.googleapis.com/oauth2/v2/userinfo")!
            var userInfoRequest = URLRequest(url: userInfoURL)
            userInfoRequest.setValue(
                "Bearer \(tokens.accessToken)", forHTTPHeaderField: "Authorization")

            let userInfo: GoogleUserInfo = try await URLSession.shared.data(for: userInfoRequest)
            profilePictureURL = userInfo.picture
            if let name = userInfo.name, !name.isEmpty {
                displayName = name
            }
        } catch {
            // Profile picture fetch failed, continue without it
            print("Could not fetch user profile picture: \(error)")
        }

        // If Google didn't return a refresh token, try to use existing one from keychain
        var refreshTokenToUse = tokens.refreshToken
        if refreshTokenToUse == nil {
            let existingRefresh = KeychainHelper.shared.read(
                account: refreshTokenKey(for: provider, email: profile.emailAddress))
            if let existing = existingRefresh, !existing.isEmpty {
                print("♻️ Google didn't return refresh token, using existing one from keychain")
                refreshTokenToUse = existing
            } else {
                print("⚠️ WARNING: No refresh token available! You may need to:")
                print("   1. Go to https://myaccount.google.com/permissions")
                print("   2. Remove PowerUserMail from connected apps")
                print("   3. Sign in again to get a fresh refresh token")
            }
        }

        let newAccount = Account(
            provider: provider, emailAddress: profile.emailAddress, displayName: displayName,
            accessToken: tokens.accessToken, refreshToken: refreshTokenToUse,
            isAuthenticated: true, profilePictureURL: profilePictureURL)
        account = newAccount

        // Reset rate limiter for this account after successful auth
        await RateLimiter.shared.reset(for: profile.emailAddress)

        // Persist tokens with EMAIL-SPECIFIC keys (critical for multi-account support)
        print("💾 Storing credentials for: \(profile.emailAddress)")
        storeTokensForAccount(
            provider: provider, email: profile.emailAddress,
            accessToken: tokens.accessToken, refreshToken: refreshTokenToUse,
            expiresIn: tokens.expiresIn)

        return newAccount
    }

    func fetchInbox() async throws -> [EmailThread] {
        guard let account = account else { throw MailServiceError.authenticationRequired }

        // Ensure valid access token for THIS SPECIFIC ACCOUNT
        let token = try await ensureValidAccessToken(
            for: provider, email: account.emailAddress, config: config)

        var allThreads: [EmailThread] = []
        var nextPageToken: String? = nil

        // Safety limit to prevent infinite loops during dev
        let maxPages = 5
        var pageCount = 0

        repeat {
            // Check rate limiter before list request
            let waitTime = await RateLimiter.shared.shouldWait(for: account.emailAddress)
            if waitTime > 0 {
                print("⏳ Gmail: Waiting \(Int(waitTime))s before list request...")
                try await Task.sleep(nanoseconds: UInt64(waitTime * 1_000_000_000))
            }

            await RateLimiter.shared.willMakeRequest(for: account.emailAddress)

            var components = URLComponents(
                string: "https://gmail.googleapis.com/gmail/v1/users/me/threads")!
            var queryItems = [URLQueryItem(name: "maxResults", value: "20")]
            if let pageToken = nextPageToken {
                queryItems.append(URLQueryItem(name: "pageToken", value: pageToken))
            }
            components.queryItems = queryItems

            var listRequest = URLRequest(url: components.url!)
            listRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            let (data, response) = try await URLSession.shared.data(for: listRequest)

            // Check for rate limit
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 429 {
                let retrySeconds = parseRetryAfter(response: httpResponse, data: data)
                await RateLimiter.shared.requestRateLimited(
                    for: account.emailAddress, retryAfterSeconds: retrySeconds)
                print("🚫 Gmail: Rate limited on list request, waiting...")
                try await Task.sleep(nanoseconds: UInt64((retrySeconds ?? 60) * 1_000_000_000))
                continue
            }

            let listResponse = try JSONDecoder().decode(GmailThreadListResponse.self, from: data)
            await RateLimiter.shared.requestSucceeded(for: account.emailAddress)

            nextPageToken = listResponse.nextPageToken

            if let threads = listResponse.threads {
                // Fetch details with rate limiting - process in batches
                let batchSize = 5
                let delayBetweenBatches: UInt64 = 200_000_000  // 200ms

                for batch in stride(from: 0, to: threads.count, by: batchSize) {
                    let endIndex = min(batch + batchSize, threads.count)
                    let batchThreads = Array(threads[batch..<endIndex])

                    // Check rate limiter before each batch
                    let batchWaitTime = await RateLimiter.shared.shouldWait(
                        for: account.emailAddress)
                    if batchWaitTime > 0 {
                        try await Task.sleep(nanoseconds: UInt64(batchWaitTime * 1_000_000_000))
                    }

                    await withTaskGroup(of: EmailThread?.self) { group in
                        for threadSummary in batchThreads {
                            group.addTask {
                                do {
                                    await RateLimiter.shared.willMakeRequest(
                                        for: account.emailAddress)

                                    let detailURL = URL(
                                        string:
                                            "https://gmail.googleapis.com/gmail/v1/users/me/threads/\(threadSummary.id)"
                                    )!
                                    var detailRequest = URLRequest(url: detailURL)
                                    detailRequest.setValue(
                                        "Bearer \(token)", forHTTPHeaderField: "Authorization")

                                    let (detailData, detailResponse) = try await URLSession.shared
                                        .data(for: detailRequest)

                                    // Check for rate limit
                                    if let httpResp = detailResponse as? HTTPURLResponse,
                                        httpResp.statusCode == 429
                                    {
                                        let retrySeconds = self.parseRetryAfter(
                                            response: httpResp, data: detailData)
                                        await RateLimiter.shared.requestRateLimited(
                                            for: account.emailAddress,
                                            retryAfterSeconds: retrySeconds)
                                        return nil
                                    }

                                    let threadDetail = try JSONDecoder().decode(
                                        GmailThreadDetail.self, from: detailData)
                                    await RateLimiter.shared.requestSucceeded(
                                        for: account.emailAddress)

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
                                    await RateLimiter.shared.requestFailed(
                                        for: account.emailAddress)
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

                    // Delay between batches
                    if endIndex < threads.count {
                        try await Task.sleep(nanoseconds: delayBetweenBatches)
                    }
                }
            }

            pageCount += 1
        } while nextPageToken != nil && pageCount < maxPages

        return allThreads
    }

    func fetchInboxStream() -> AsyncThrowingStream<EmailThread, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    guard let account = self.account else {
                        continuation.finish(throwing: MailServiceError.authenticationRequired)
                        return
                    }

                    print("📧 Gmail: Fetching inbox for \(account.emailAddress)")

                    // Get token - this will refresh if needed
                    var token: String
                    do {
                        token = try await ensureValidAccessToken(
                            for: self.provider, email: account.emailAddress, config: self.config)
                    } catch {
                        print("❌ Gmail: Token validation failed for \(account.emailAddress)")
                        continuation.finish(throwing: error)
                        return
                    }

                    var nextPageToken: String? = nil
                    let maxPages = 5
                    var pageCount = 0
                    var hasRetried = false  // Only retry token refresh once
                    var shouldContinue = true  // Track if we should keep fetching pages

                    while shouldContinue && pageCount < maxPages {
                        // Check rate limiter before list request
                        let waitTime = await RateLimiter.shared.shouldWait(
                            for: account.emailAddress)
                        if waitTime > 0 {
                            print("⏳ Gmail: Waiting \(Int(waitTime))s before list request...")
                            try? await Task.sleep(nanoseconds: UInt64(waitTime * 1_000_000_000))
                        }

                        await RateLimiter.shared.willMakeRequest(for: account.emailAddress)

                        var components = URLComponents(
                            string: "https://gmail.googleapis.com/gmail/v1/users/me/threads")!
                        var queryItems = [URLQueryItem(name: "maxResults", value: "20")]
                        if let pageToken = nextPageToken {
                            queryItems.append(URLQueryItem(name: "pageToken", value: pageToken))
                        }
                        components.queryItems = queryItems

                        var listRequest = URLRequest(url: components.url!)
                        listRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

                        do {
                            let (data, response) = try await URLSession.shared.data(
                                for: listRequest)

                            // Check for rate limit on list request
                            if let httpResponse = response as? HTTPURLResponse {
                                if httpResponse.statusCode == 429 {
                                    let retrySeconds = parseRetryAfter(
                                        response: httpResponse, data: data)
                                    await RateLimiter.shared.requestRateLimited(
                                        for: account.emailAddress, retryAfterSeconds: retrySeconds)
                                    print("🚫 Gmail: Rate limited on list request, waiting...")
                                    try? await Task.sleep(
                                        nanoseconds: UInt64((retrySeconds ?? 60) * 1_000_000_000))
                                    continue  // Retry this page
                                }
                                
                                // Check for 401 Unauthorized - token is invalid
                                if httpResponse.statusCode == 401 {
                                    print("⚠️ Gmail: Got 401 on list request - token is invalid")
                                    throw APIError.unauthorized
                                }
                            }
                            
                            let listResponse = try JSONDecoder().decode(
                                GmailThreadListResponse.self, from: data)
                            await RateLimiter.shared.requestSucceeded(for: account.emailAddress)

                            nextPageToken = listResponse.nextPageToken

                            if let threads = listResponse.threads {
                                // Fetch thread details with rate limiting
                                // Process in controlled batches to avoid 429 errors
                                let batchSize = 5  // Max concurrent requests
                                let delayBetweenBatches: UInt64 = 200_000_000  // 200ms in nanoseconds

                                for batch in stride(from: 0, to: threads.count, by: batchSize) {
                                    let endIndex = min(batch + batchSize, threads.count)
                                    let batchThreads = Array(threads[batch..<endIndex])

                                    // Check rate limiter before each batch
                                    let waitTime = await RateLimiter.shared.shouldWait(
                                        for: account.emailAddress)
                                    if waitTime > 0 {
                                        print(
                                            "⏳ Gmail: Waiting \(Int(waitTime))s before next batch..."
                                        )
                                        try? await Task.sleep(
                                            nanoseconds: UInt64(waitTime * 1_000_000_000))
                                    }

                                    // Process batch concurrently
                                    await withTaskGroup(of: EmailThread?.self) { group in
                                        for threadSummary in batchThreads {
                                            group.addTask {
                                                do {
                                                    // Mark that we're making a request
                                                    await RateLimiter.shared.willMakeRequest(
                                                        for: account.emailAddress)

                                                    let detailURL = URL(
                                                        string:
                                                            "https://gmail.googleapis.com/gmail/v1/users/me/threads/\(threadSummary.id)"
                                                    )!
                                                    var detailRequest = URLRequest(url: detailURL)
                                                    detailRequest.setValue(
                                                        "Bearer \(token)",
                                                        forHTTPHeaderField: "Authorization")

                                                    let (data, response) =
                                                        try await URLSession.shared.data(
                                                            for: detailRequest)

                                                    // Check for rate limit response
                                                    if let httpResponse = response
                                                        as? HTTPURLResponse
                                                    {
                                                        if httpResponse.statusCode == 429 {
                                                            // Parse Retry-After header or body
                                                            let retrySeconds = self.parseRetryAfter(
                                                                response: httpResponse, data: data)
                                                            await RateLimiter.shared
                                                                .requestRateLimited(
                                                                    for: account.emailAddress,
                                                                    retryAfterSeconds: retrySeconds)
                                                            return nil
                                                        }
                                                    }

                                                    let threadDetail = try JSONDecoder().decode(
                                                        GmailThreadDetail.self, from: data)

                                                    // Success - notify rate limiter
                                                    await RateLimiter.shared.requestSucceeded(
                                                        for: account.emailAddress)

                                                    let messages = threadDetail.messages.map {
                                                        self.mapGmailMessage($0)
                                                    }
                                                    let subject =
                                                        messages.first?.subject ?? "No Subject"
                                                    let participants = Array(
                                                        Set(
                                                            messages.map { $0.from }
                                                                + messages.flatMap { $0.to }))

                                                    return EmailThread(
                                                        id: threadDetail.id, subject: subject,
                                                        messages: messages,
                                                        participants: participants)
                                                } catch {
                                                    print(
                                                        "Failed to fetch thread details: \(error)")
                                                    await RateLimiter.shared.requestFailed(
                                                        for: account.emailAddress)
                                                    return nil
                                                }
                                            }
                                        }

                                        // Yield each thread as it completes
                                        for await thread in group {
                                            if let thread = thread {
                                                continuation.yield(thread)
                                            }
                                        }
                                    }

                                    // Small delay between batches
                                    if endIndex < threads.count {
                                        try? await Task.sleep(nanoseconds: delayBetweenBatches)
                                    }
                                }
                            }

                            pageCount += 1
                            
                            // Check if we should continue to the next page
                            if nextPageToken == nil {
                                shouldContinue = false
                            }
                        } catch APIError.unauthorized {
                            // Token was rejected by server - try to refresh once
                            if !hasRetried {
                                print("⚠️ Gmail: Token rejected by server, attempting refresh...")
                                hasRetried = true

                                // Force clear the access token so ensureValidAccessToken will refresh
                                clearAccessTokenForAccount(
                                    provider: self.provider, email: account.emailAddress)

                                do {
                                    token = try await ensureValidAccessToken(
                                        for: self.provider, email: account.emailAddress,
                                        config: self.config)
                                    print("✅ Gmail: Token refreshed, retrying request...")
                                    continue  // Retry the current page
                                } catch {
                                    print("❌ Gmail: Token refresh failed, need re-authentication")
                                    continuation.finish(
                                        throwing: MailServiceError.tokenExpired(
                                            email: account.emailAddress))
                                    return
                                }
                            } else {
                                // Already retried, give up
                                print(
                                    "❌ Gmail: Token still invalid after refresh for \(account.emailAddress)"
                                )
                                continuation.finish(
                                    throwing: MailServiceError.tokenExpired(
                                        email: account.emailAddress))
                                return
                            }
                        }
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func mapGmailMessage(_ msg: GmailMessage) -> Email {
        let headers = msg.payload?.headers ?? []
        let subject =
            headers.first(where: { $0.name.lowercased() == "subject" })?.value ?? "(No Subject)"
        let from = headers.first(where: { $0.name.lowercased() == "from" })?.value ?? "Unknown"
        let to =
            headers.first(where: { $0.name.lowercased() == "to" })?.value.components(
                separatedBy: ",") ?? []

        // Extract body - prefer HTML over plain text
        let body = extractBody(from: msg.payload, snippet: msg.snippet ?? "")

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

    /// Parse Retry-After from HTTP response (header or JSON body)
    private func parseRetryAfter(response: HTTPURLResponse, data: Data) -> Double? {
        // First try the Retry-After header
        if let retryAfterHeader = response.value(forHTTPHeaderField: "Retry-After") {
            // Could be seconds or HTTP date
            if let seconds = Double(retryAfterHeader) {
                return seconds
            }
            // Try parsing as ISO date
            if let seconds = HTTPURLResponse.parseRetryAfterValue(retryAfterHeader), seconds > 0 {
                return seconds
            }
        }

        // Try parsing Gmail's JSON error message which contains the timestamp
        if let bodyString = String(data: data, encoding: .utf8) {
            if let seconds = parseRetryAfterFromGmailError(bodyString) {
                return seconds
            }
        }

        // Try parsing JSON error response for retryDelay field
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let error = json["error"] as? [String: Any]
        {
            if let details = error["details"] as? [[String: Any]] {
                for detail in details {
                    if let retryDelay = detail["retryDelay"] as? String {
                        return parseRetryDelayString(retryDelay)
                    }
                }
            }
        }

        // Default to 60 seconds if no Retry-After found
        return 60.0
    }

    /// Parse retry delay strings like "30s", "1m30s", etc.
    private func parseRetryDelayString(_ delayStr: String) -> Double {
        var totalSeconds: Double = 0
        var currentNumber = ""

        for char in delayStr {
            if char.isNumber {
                currentNumber += String(char)
            } else if char == "s" || char == "S" {
                if let num = Double(currentNumber) {
                    totalSeconds += num
                }
                currentNumber = ""
            } else if char == "m" || char == "M" {
                if let num = Double(currentNumber) {
                    totalSeconds += num * 60
                }
                currentNumber = ""
            } else if char == "h" || char == "H" {
                if let num = Double(currentNumber) {
                    totalSeconds += num * 3600
                }
                currentNumber = ""
            }
        }

        return totalSeconds > 0 ? totalSeconds : 60.0
    }

    /// Recursively extract body from Gmail message parts, preferring HTML
    private func extractBody(from payload: GmailMessagePayload?, snippet: String) -> String {
        guard let payload = payload else { return snippet }

        var htmlBody: String?
        var plainBody: String?

        // Check if payload has direct body data
        if let mimeType = payload.parts == nil ? "text/plain" : nil,
            let data = payload.body?.data,
            let decoded = data.base64UrlDecoded()
        {
            // Single part message
            if payload.headers?.contains(where: {
                $0.name.lowercased() == "content-type"
                    && $0.value.lowercased().contains("text/html")
            }) == true {
                htmlBody = decoded
            } else {
                plainBody = decoded
            }
        }

        // Recursively search parts for HTML and plain text
        func searchParts(_ parts: [GmailMessagePart]?) {
            guard let parts = parts else { return }

            for part in parts {
                let mimeType = part.mimeType?.lowercased() ?? ""

                if mimeType == "text/html", let data = part.body?.data,
                    let decoded = data.base64UrlDecoded()
                {
                    htmlBody = decoded
                } else if mimeType == "text/plain", let data = part.body?.data,
                    let decoded = data.base64UrlDecoded(), plainBody == nil
                {
                    plainBody = decoded
                } else if mimeType.contains("multipart") || part.parts != nil {
                    // Recurse into nested parts
                    searchParts(part.parts)
                }
            }
        }

        searchParts(payload.parts)

        // Prefer HTML, fall back to plain text, then snippet
        return htmlBody ?? plainBody ?? snippet
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

        // Ensure valid access token for THIS SPECIFIC ACCOUNT
        let token = try await ensureValidAccessToken(
            for: provider, email: account.emailAddress, config: config)

        let url = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages/send")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Construct MIME message with proper RFC 2047 encoding for headers
        var mime = "MIME-Version: 1.0\r\n"
        if !message.to.isEmpty { mime += "To: \(message.to.joined(separator: ", "))\r\n" }
        if !message.cc.isEmpty { mime += "Cc: \(message.cc.joined(separator: ", "))\r\n" }
        if !message.bcc.isEmpty { mime += "Bcc: \(message.bcc.joined(separator: ", "))\r\n" }

        // RFC 2047 encode subject for non-ASCII characters
        let encodedSubject = message.subject.mimeEncodedHeader()
        mime += "Subject: \(encodedSubject)\r\n"
        mime += "Content-Type: text/plain; charset=\"UTF-8\"\r\n"
        mime += "Content-Transfer-Encoding: base64\r\n\r\n"

        // Base64 encode the body for safe transfer
        let bodyData = message.body.data(using: .utf8) ?? Data()
        let encodedBody = bodyData.base64EncodedString(options: .lineLength76Characters)
        mime += encodedBody

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
        // Don't auto-load - let AccountViewModel manage this
    }

    func restoreAccount(_ account: Account) {
        print("🔄 Outlook: Restoring account \(account.emailAddress)")
        self.account = account
        // Restore tokens to keychain with EMAIL-SPECIFIC keys
        if !account.accessToken.isEmpty {
            storeTokensForAccount(
                provider: provider,
                email: account.emailAddress,
                accessToken: account.accessToken,
                refreshToken: account.refreshToken ?? "",
                expiresIn: 3600  // Will refresh if needed
            )
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

        // Fetch profile picture URL from Microsoft Graph
        // Note: MS Graph returns the actual image data, so we'll store it as a data URL or use a placeholder
        var profilePictureURL: String? = nil

        do {
            let photoURL = URL(string: "https://graph.microsoft.com/v1.0/me/photo/$value")!
            var photoRequest = URLRequest(url: photoURL)
            photoRequest.setValue(
                "Bearer \(tokens.accessToken)", forHTTPHeaderField: "Authorization")

            let (data, response) = try await URLSession.shared.data(for: photoRequest)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                // Convert to data URL for easy display
                let base64 = data.base64EncodedString()
                profilePictureURL = "data:image/jpeg;base64,\(base64)"
            }
        } catch {
            // Profile picture fetch failed, continue without it
            print("Could not fetch Outlook profile picture: \(error)")
        }

        let newAccount = Account(
            provider: provider, emailAddress: email, displayName: name,
            accessToken: tokens.accessToken, refreshToken: tokens.refreshToken,
            isAuthenticated: true, profilePictureURL: profilePictureURL)
        account = newAccount

        // Reset rate limiter for this account after successful auth
        await RateLimiter.shared.reset(for: email)

        // Persist tokens with EMAIL-SPECIFIC keys (critical for multi-account support)
        print("💾 Storing credentials for: \(email)")
        storeTokensForAccount(
            provider: provider, email: email,
            accessToken: tokens.accessToken, refreshToken: tokens.refreshToken,
            expiresIn: tokens.expiresIn)

        return newAccount
    }

    func fetchInbox() async throws -> [EmailThread] {
        guard let account = account else { throw MailServiceError.authenticationRequired }

        // Ensure valid access token for THIS SPECIFIC ACCOUNT
        let token = try await ensureValidAccessToken(
            for: provider, email: account.emailAddress, config: config)

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

    func fetchInboxStream() -> AsyncThrowingStream<EmailThread, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    guard let account = self.account else {
                        continuation.finish(throwing: MailServiceError.authenticationRequired)
                        return
                    }

                    print("📧 Outlook: Fetching inbox for \(account.emailAddress)")

                    // Get token - this will refresh if needed
                    var token: String
                    do {
                        token = try await ensureValidAccessToken(
                            for: self.provider, email: account.emailAddress, config: self.config)
                    } catch {
                        print("❌ Outlook: Token validation failed for \(account.emailAddress)")
                        continuation.finish(throwing: error)
                        return
                    }

                    var conversationGroups: [String: [OutlookMessage]] = [:]
                    var yieldedConversations: Set<String> = []

                    var nextLink: String? =
                        "https://graph.microsoft.com/v1.0/me/mailFolders/inbox/messages?$top=20&$select=id,conversationId,subject,bodyPreview,body,from,toRecipients,receivedDateTime,isRead&$orderby=receivedDateTime desc"

                    let maxPages = 5
                    var pageCount = 0
                    var hasRetried = false  // Only retry token refresh once

                    while let link = nextLink, pageCount < maxPages {
                        var request = URLRequest(url: URL(string: link)!)
                        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

                        do {
                            let response: OutlookMessageListResponse = try await URLSession.shared
                                .data(
                                    for: request)

                            // Process messages and yield conversations as they become complete
                            for message in response.value {
                                let convId = message.conversationId ?? UUID().uuidString

                                if conversationGroups[convId] == nil {
                                    conversationGroups[convId] = []
                                }
                                conversationGroups[convId]?.append(message)

                                // Yield new conversations immediately
                                if !yieldedConversations.contains(convId) {
                                    let messages = conversationGroups[convId]!
                                    let mappedMessages = messages.map { self.mapOutlookMessage($0) }
                                    let subject = mappedMessages.first?.subject ?? "No Subject"
                                    let participants = Array(
                                        Set(
                                            mappedMessages.map { $0.from }
                                                + mappedMessages.flatMap { $0.to }))

                                    let thread = EmailThread(
                                        id: convId, subject: subject, messages: mappedMessages,
                                        participants: participants)

                                    continuation.yield(thread)
                                    yieldedConversations.insert(convId)
                                }
                            }

                            nextLink = response.nextLink
                            pageCount += 1
                        } catch APIError.unauthorized {
                            // Token was rejected by server - try to refresh once
                            if !hasRetried {
                                print("⚠️ Outlook: Token rejected by server, attempting refresh...")
                                hasRetried = true

                                // Force clear the access token so ensureValidAccessToken will refresh
                                clearAccessTokenForAccount(
                                    provider: self.provider, email: account.emailAddress)

                                do {
                                    token = try await ensureValidAccessToken(
                                        for: self.provider, email: account.emailAddress,
                                        config: self.config)
                                    print("✅ Outlook: Token refreshed, retrying request...")
                                    continue  // Retry the current page
                                } catch {
                                    print("❌ Outlook: Token refresh failed, need re-authentication")
                                    continuation.finish(
                                        throwing: MailServiceError.tokenExpired(
                                            email: account.emailAddress))
                                    return
                                }
                            } else {
                                // Already retried, give up
                                print(
                                    "❌ Outlook: Token still invalid after refresh for \(account.emailAddress)"
                                )
                                continuation.finish(
                                    throwing: MailServiceError.tokenExpired(
                                        email: account.emailAddress))
                                return
                            }
                        }
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
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

        // Ensure valid access token for THIS SPECIFIC ACCOUNT
        let token = try await ensureValidAccessToken(
            for: provider, email: account.emailAddress, config: config)

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

// MARK: - Custom IMAP Service

final class IMAPService: MailService {
    private(set) var account: Account?
    var provider: MailProvider { .imap }
    var isAuthenticated: Bool { account?.isAuthenticated == true }
    
    private var config: IMAPConfiguration?
    private var connection: NWConnection?
    private var commandTag = 0
    private var responseBuffer = Data()
    
    init() {}
    
    init(config: IMAPConfiguration) {
        self.config = config
    }
    
    func configure(_ config: IMAPConfiguration) {
        self.config = config
    }
    
    func restoreAccount(_ account: Account) {
        print("🔄 IMAP: Restoring account \(account.emailAddress)")
        self.account = account
        
        // Restore configuration from keychain
        if let configData = KeychainHelper.shared.read(account: imapConfigKey(for: account.emailAddress)),
           let data = configData.data(using: .utf8),
           let savedConfig = try? JSONDecoder().decode(IMAPConfiguration.self, from: data) {
            self.config = savedConfig
            print("   ✅ IMAP config restored for \(account.emailAddress)")
        }
    }
    
    private func imapConfigKey(for email: String) -> String {
        "powerusermail.imap.\(email.lowercased()).config"
    }
    
    private func imapPasswordKey(for email: String) -> String {
        "powerusermail.imap.\(email.lowercased()).password"
    }
    
    func authenticate() async throws -> Account {
        guard let config = config else {
            throw MailServiceError.custom("IMAP configuration not set")
        }
        
        // Test connection to IMAP server
        try await testConnection(config: config)
        
        let email = config.username
        let displayName = email.components(separatedBy: "@").first?.capitalized ?? "IMAP User"
        
        let newAccount = Account(
            provider: .imap,
            emailAddress: email,
            displayName: displayName,
            accessToken: "", // Not used for IMAP
            refreshToken: nil,
            isAuthenticated: true
        )
        
        account = newAccount
        
        // Store config in keychain (without password)
        var configToStore = config
        configToStore.password = "" // Password stored separately
        if let configData = try? JSONEncoder().encode(configToStore),
           let configString = String(data: configData, encoding: .utf8) {
            KeychainHelper.shared.save(configString, account: imapConfigKey(for: email))
        }
        
        // Store password separately in keychain
        KeychainHelper.shared.save(config.password, account: imapPasswordKey(for: email))
        
        print("✅ IMAP: Authenticated as \(email)")
        return newAccount
    }
    
    private func testConnection(config: IMAPConfiguration) async throws {
        // Create TLS parameters for secure connection
        let tlsOptions = NWProtocolTLS.Options()
        
        // Allow self-signed certificates for testing (you might want to make this configurable)
        sec_protocol_options_set_verify_block(
            tlsOptions.securityProtocolOptions,
            { _, _, completion in
                completion(true) // Accept all certificates - for dev/testing
            },
            .main
        )
        
        let parameters = NWParameters(tls: config.useSSL ? tlsOptions : nil)
        
        let connection = NWConnection(
            host: NWEndpoint.Host(config.imapHost),
            port: NWEndpoint.Port(integerLiteral: UInt16(config.imapPort)),
            using: parameters
        )
        
        // Use withCheckedThrowingContinuation for async/await pattern
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var hasResumed = false
            
            connection.stateUpdateHandler = { state in
                guard !hasResumed else { return }
                
                switch state {
                case .ready:
                    print("✅ IMAP: Connected to \(config.imapHost):\(config.imapPort)")
                    hasResumed = true
                    
                    // Now try to login
                    self.performIMAPLogin(connection: connection, config: config) { result in
                        connection.cancel()
                        switch result {
                        case .success:
                            continuation.resume()
                        case .failure(let error):
                            continuation.resume(throwing: error)
                        }
                    }
                    
                case .failed(let error):
                    hasResumed = true
                    connection.cancel()
                    continuation.resume(throwing: MailServiceError.custom("Connection failed: \(error.localizedDescription)"))
                    
                case .cancelled:
                    if !hasResumed {
                        hasResumed = true
                        continuation.resume(throwing: MailServiceError.custom("Connection cancelled"))
                    }
                    
                default:
                    break
                }
            }
            
            connection.start(queue: .global())
            
            // Timeout after 15 seconds
            DispatchQueue.global().asyncAfter(deadline: .now() + 15) {
                if !hasResumed {
                    hasResumed = true
                    connection.cancel()
                    continuation.resume(throwing: MailServiceError.custom("Connection timeout"))
                }
            }
        }
    }
    
    private func performIMAPLogin(connection: NWConnection, config: IMAPConfiguration, completion: @escaping (Result<Void, Error>) -> Void) {
        // Read server greeting first
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, _, error in
            guard let self = self else { return }
            
            if let error = error {
                completion(.failure(MailServiceError.custom("Failed to read greeting: \(error.localizedDescription)")))
                return
            }
            
            if let data = data, let greeting = String(data: data, encoding: .utf8) {
                print("📨 IMAP Greeting: \(greeting.trimmingCharacters(in: .whitespacesAndNewlines))")
                
                // Send LOGIN command
                self.commandTag += 1
                let tag = "A\(String(format: "%04d", self.commandTag))"
                let loginCommand = "\(tag) LOGIN \(config.username) \(config.password)\r\n"
                
                connection.send(content: loginCommand.data(using: .utf8), completion: .contentProcessed { sendError in
                    if let sendError = sendError {
                        completion(.failure(MailServiceError.custom("Failed to send login: \(sendError.localizedDescription)")))
                        return
                    }
                    
                    // Read login response
                    connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { responseData, _, _, recvError in
                        if let recvError = recvError {
                            completion(.failure(MailServiceError.custom("Failed to read login response: \(recvError.localizedDescription)")))
                            return
                        }
                        
                        if let responseData = responseData, let response = String(data: responseData, encoding: .utf8) {
                            print("📨 IMAP Login Response: \(response.trimmingCharacters(in: .whitespacesAndNewlines))")
                            
                            if response.contains("\(tag) OK") {
                                // Login successful, send LOGOUT
                                self.commandTag += 1
                                let logoutTag = "A\(String(format: "%04d", self.commandTag))"
                                let logoutCommand = "\(logoutTag) LOGOUT\r\n"
                                
                                connection.send(content: logoutCommand.data(using: .utf8), completion: .contentProcessed { _ in
                                    completion(.success(()))
                                })
                            } else if response.contains("NO") || response.contains("BAD") {
                                completion(.failure(MailServiceError.custom("Login failed: Invalid credentials")))
                            } else {
                                completion(.failure(MailServiceError.custom("Unexpected response: \(response)")))
                            }
                        } else {
                            completion(.failure(MailServiceError.custom("Empty login response")))
                        }
                    }
                })
            } else {
                completion(.failure(MailServiceError.custom("No server greeting received")))
            }
        }
    }
    
    func fetchInbox() async throws -> [EmailThread] {
        guard let account = account, let config = config else {
            throw MailServiceError.authenticationRequired
        }
        
        // Get password from keychain
        guard let password = KeychainHelper.shared.read(account: imapPasswordKey(for: account.emailAddress)) else {
            throw MailServiceError.custom("IMAP password not found")
        }
        
        var fullConfig = config
        fullConfig.password = password
        
        return try await fetchIMAPMessages(config: fullConfig)
    }
    
    private func fetchIMAPMessages(config: IMAPConfiguration) async throws -> [EmailThread] {
        // For now, return a simplified implementation
        // A full implementation would require a complete IMAP protocol handler
        // Consider using a library like swift-nio-imap in the future
        
        return try await withCheckedThrowingContinuation { continuation in
            let tlsOptions = NWProtocolTLS.Options()
            sec_protocol_options_set_verify_block(
                tlsOptions.securityProtocolOptions,
                { _, _, completion in completion(true) },
                .main
            )
            
            let parameters = NWParameters(tls: config.useSSL ? tlsOptions : nil)
            let connection = NWConnection(
                host: NWEndpoint.Host(config.imapHost),
                port: NWEndpoint.Port(integerLiteral: UInt16(config.imapPort)),
                using: parameters
            )
            
            var threads: [EmailThread] = []
            var hasResumed = false
            
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    self.fetchEmailsFromConnection(connection: connection, config: config) { result in
                        guard !hasResumed else { return }
                        hasResumed = true
                        connection.cancel()
                        
                        switch result {
                        case .success(let fetchedThreads):
                            continuation.resume(returning: fetchedThreads)
                        case .failure(let error):
                            continuation.resume(throwing: error)
                        }
                    }
                case .failed(let error):
                    guard !hasResumed else { return }
                    hasResumed = true
                    connection.cancel()
                    continuation.resume(throwing: MailServiceError.custom("Connection failed: \(error.localizedDescription)"))
                default:
                    break
                }
            }
            
            connection.start(queue: .global())
            
            // Timeout
            DispatchQueue.global().asyncAfter(deadline: .now() + 30) {
                guard !hasResumed else { return }
                hasResumed = true
                connection.cancel()
                continuation.resume(throwing: MailServiceError.custom("Fetch timeout"))
            }
        }
    }
    
    private func fetchEmailsFromConnection(connection: NWConnection, config: IMAPConfiguration, completion: @escaping (Result<[EmailThread], Error>) -> Void) {
        var responseBuffer = ""
        var threads: [EmailThread] = []
        var commandTag = 0
        
        func sendCommand(_ command: String, expectTag: String, then: @escaping (String) -> Void) {
            connection.send(content: "\(command)\r\n".data(using: .utf8), completion: .contentProcessed { error in
                if let error = error {
                    completion(.failure(MailServiceError.custom("Send failed: \(error.localizedDescription)")))
                    return
                }
                
                readUntilTag(expectTag, then: then)
            })
        }
        
        func readUntilTag(_ tag: String, then: @escaping (String) -> Void) {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, _, error in
                if let data = data, let str = String(data: data, encoding: .utf8) {
                    responseBuffer += str
                    
                    // Check if we have the complete response
                    if responseBuffer.contains("\(tag) OK") || responseBuffer.contains("\(tag) NO") || responseBuffer.contains("\(tag) BAD") {
                        let response = responseBuffer
                        responseBuffer = ""
                        then(response)
                    } else {
                        // Continue reading
                        readUntilTag(tag, then: then)
                    }
                } else if let error = error {
                    completion(.failure(MailServiceError.custom("Read failed: \(error.localizedDescription)")))
                }
            }
        }
        
        // Read greeting
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, _, _ in
            guard let _ = data else {
                completion(.failure(MailServiceError.custom("No greeting")))
                return
            }
            
            // Login
            commandTag += 1
            let loginTag = "A\(String(format: "%04d", commandTag))"
            sendCommand("\(loginTag) LOGIN \(config.username) \(config.password)", expectTag: loginTag) { loginResp in
                guard loginResp.contains("\(loginTag) OK") else {
                    completion(.failure(MailServiceError.custom("Login failed")))
                    return
                }
                
                // Select INBOX
                commandTag += 1
                let selectTag = "A\(String(format: "%04d", commandTag))"
                sendCommand("\(selectTag) SELECT INBOX", expectTag: selectTag) { selectResp in
                    guard selectResp.contains("\(selectTag) OK") else {
                        completion(.failure(MailServiceError.custom("SELECT failed")))
                        return
                    }
                    
                    // Fetch last 20 messages headers
                    commandTag += 1
                    let fetchTag = "A\(String(format: "%04d", commandTag))"
                    sendCommand("\(fetchTag) FETCH 1:20 (UID FLAGS ENVELOPE BODY.PEEK[TEXT]<0.500>)", expectTag: fetchTag) { fetchResp in
                        // Parse the FETCH response
                        threads = self.parseIMAPFetchResponse(fetchResp, email: config.username)
                        
                        // Logout
                        commandTag += 1
                        let logoutTag = "A\(String(format: "%04d", commandTag))"
                        sendCommand("\(logoutTag) LOGOUT", expectTag: logoutTag) { _ in
                            completion(.success(threads))
                        }
                    }
                }
            }
        }
    }
    
    private func parseIMAPFetchResponse(_ response: String, email: String) -> [EmailThread] {
        var threads: [EmailThread] = []
        
        // Simple parser for IMAP ENVELOPE responses
        // Format: * n FETCH (UID nn FLAGS (...) ENVELOPE (...) BODY[TEXT] {...})
        
        let lines = response.components(separatedBy: "\r\n")
        var currentMessage: [String: String] = [:]
        
        for line in lines {
            if line.starts(with: "* ") && line.contains("FETCH") {
                // Parse envelope
                if let envelopeRange = line.range(of: "ENVELOPE (") {
                    let envelopeStart = envelopeRange.upperBound
                    // Find matching closing paren (simplified)
                    if let envelopeEnd = findMatchingParen(in: line, from: envelopeStart) {
                        let envelope = String(line[envelopeStart..<envelopeEnd])
                        let parsed = parseEnvelope(envelope)
                        
                        let messageId = "imap-\(UUID().uuidString)"
                        let message = Email(
                            id: messageId,
                            threadId: messageId,
                            subject: parsed["subject"] ?? "(No Subject)",
                            from: parsed["from"] ?? "Unknown",
                            to: [email],
                            preview: "",
                            body: "",
                            receivedAt: parseIMAPDate(parsed["date"] ?? "") ?? Date()
                        )
                        
                        let thread = EmailThread(
                            id: messageId,
                            subject: message.subject,
                            messages: [message],
                            participants: [message.from, email]
                        )
                        threads.append(thread)
                    }
                }
            }
        }
        
        return threads
    }
    
    private func findMatchingParen(in str: String, from start: String.Index) -> String.Index? {
        var depth = 1
        var index = start
        
        while index < str.endIndex && depth > 0 {
            let char = str[index]
            if char == "(" { depth += 1 }
            else if char == ")" { depth -= 1 }
            index = str.index(after: index)
        }
        
        return depth == 0 ? str.index(before: index) : nil
    }
    
    private func parseEnvelope(_ envelope: String) -> [String: String] {
        var result: [String: String] = [:]
        
        // ENVELOPE format: (date subject from sender reply-to to cc bcc in-reply-to message-id)
        // This is a simplified parser
        
        // Extract quoted strings
        let regex = try? NSRegularExpression(pattern: "\"([^\"\\\\]|\\\\.)*\"", options: [])
        let range = NSRange(envelope.startIndex..., in: envelope)
        
        if let matches = regex?.matches(in: envelope, options: [], range: range) {
            if matches.count >= 1, let dateRange = Range(matches[0].range, in: envelope) {
                result["date"] = String(envelope[dateRange]).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            }
            if matches.count >= 2, let subjectRange = Range(matches[1].range, in: envelope) {
                result["subject"] = String(envelope[subjectRange]).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            }
        }
        
        // Try to extract from address
        if let fromMatch = envelope.range(of: "\\(\\(NIL NIL \"([^\"]+)\" \"([^\"]+)\"\\)\\)", options: .regularExpression) {
            let fromStr = String(envelope[fromMatch])
            // Extract email parts
            if let nameMatch = fromStr.range(of: "\"[^\"]+\"", options: .regularExpression) {
                result["from"] = String(fromStr[nameMatch]).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            }
        }
        
        return result
    }
    
    private func parseIMAPDate(_ dateStr: String) -> Date? {
        // IMAP date format: "03-Dec-2025 10:30:00 +0000"
        let formatter = DateFormatter()
        formatter.dateFormat = "dd-MMM-yyyy HH:mm:ss Z"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.date(from: dateStr)
    }
    
    func fetchInboxStream() -> AsyncThrowingStream<EmailThread, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let threads = try await self.fetchInbox()
                    for thread in threads {
                        continuation.yield(thread)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    func fetchMessage(id: String) async throws -> Email {
        throw MailServiceError.unsupported
    }
    
    func send(message: DraftMessage) async throws {
        guard let account = account, let config = config else {
            throw MailServiceError.authenticationRequired
        }
        
        guard let password = KeychainHelper.shared.read(account: imapPasswordKey(for: account.emailAddress)) else {
            throw MailServiceError.custom("SMTP password not found")
        }
        
        // Send via SMTP
        try await sendSMTP(message: message, config: config, password: password)
    }
    
    private func sendSMTP(message: DraftMessage, config: IMAPConfiguration, password: String) async throws {
        // Create connection to SMTP server
        let tlsOptions = NWProtocolTLS.Options()
        sec_protocol_options_set_verify_block(
            tlsOptions.securityProtocolOptions,
            { _, _, completion in completion(true) },
            .main
        )
        
        // Use STARTTLS for port 587, direct TLS for 465
        let useTLS = config.smtpPort == 465
        let parameters = NWParameters(tls: useTLS ? tlsOptions : nil)
        
        let connection = NWConnection(
            host: NWEndpoint.Host(config.smtpHost),
            port: NWEndpoint.Port(integerLiteral: UInt16(config.smtpPort)),
            using: parameters
        )
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var hasResumed = false
            
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    self.performSMTPSend(connection: connection, message: message, config: config, password: password) { result in
                        guard !hasResumed else { return }
                        hasResumed = true
                        connection.cancel()
                        
                        switch result {
                        case .success:
                            continuation.resume()
                        case .failure(let error):
                            continuation.resume(throwing: error)
                        }
                    }
                case .failed(let error):
                    guard !hasResumed else { return }
                    hasResumed = true
                    connection.cancel()
                    continuation.resume(throwing: MailServiceError.custom("SMTP connection failed: \(error.localizedDescription)"))
                default:
                    break
                }
            }
            
            connection.start(queue: .global())
            
            DispatchQueue.global().asyncAfter(deadline: .now() + 30) {
                guard !hasResumed else { return }
                hasResumed = true
                connection.cancel()
                continuation.resume(throwing: MailServiceError.custom("SMTP timeout"))
            }
        }
    }
    
    private func performSMTPSend(connection: NWConnection, message: DraftMessage, config: IMAPConfiguration, password: String, completion: @escaping (Result<Void, Error>) -> Void) {
        var responseBuffer = ""
        
        func send(_ command: String, expectCode: String, then: @escaping () -> Void) {
            let data = "\(command)\r\n".data(using: .utf8)!
            connection.send(content: data, completion: .contentProcessed { error in
                if let error = error {
                    completion(.failure(MailServiceError.custom("SMTP send failed: \(error.localizedDescription)")))
                    return
                }
                
                connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, _, error in
                    if let data = data, let response = String(data: data, encoding: .utf8) {
                        responseBuffer = response
                        if response.contains(expectCode) || response.hasPrefix(expectCode) {
                            then()
                        } else {
                            completion(.failure(MailServiceError.custom("SMTP error: \(response)")))
                        }
                    } else {
                        completion(.failure(MailServiceError.custom("SMTP no response")))
                    }
                }
            })
        }
        
        // Read greeting
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, _, _ in
            guard let data = data, let greeting = String(data: data, encoding: .utf8), greeting.contains("220") else {
                completion(.failure(MailServiceError.custom("No SMTP greeting")))
                return
            }
            
            // EHLO
            send("EHLO localhost", expectCode: "250") {
                // AUTH LOGIN
                send("AUTH LOGIN", expectCode: "334") {
                    // Username (base64)
                    let user64 = Data(config.username.utf8).base64EncodedString()
                    send(user64, expectCode: "334") {
                        // Password (base64)
                        let pass64 = Data(password.utf8).base64EncodedString()
                        send(pass64, expectCode: "235") {
                            // MAIL FROM
                            send("MAIL FROM:<\(config.username)>", expectCode: "250") {
                                // RCPT TO (for each recipient)
                                let recipients = message.to + message.cc + message.bcc
                                
                                func sendRecipients(_ remaining: [String]) {
                                    if let recipient = remaining.first {
                                        send("RCPT TO:<\(recipient)>", expectCode: "250") {
                                            sendRecipients(Array(remaining.dropFirst()))
                                        }
                                    } else {
                                        // DATA
                                        send("DATA", expectCode: "354") {
                                            // Construct email content
                                            var emailContent = "From: \(config.username)\r\n"
                                            emailContent += "To: \(message.to.joined(separator: ", "))\r\n"
                                            if !message.cc.isEmpty {
                                                emailContent += "Cc: \(message.cc.joined(separator: ", "))\r\n"
                                            }
                                            emailContent += "Subject: \(message.subject)\r\n"
                                            emailContent += "MIME-Version: 1.0\r\n"
                                            emailContent += "Content-Type: text/plain; charset=UTF-8\r\n"
                                            emailContent += "\r\n"
                                            emailContent += message.body
                                            emailContent += "\r\n.\r\n"
                                            
                                            send(emailContent, expectCode: "250") {
                                                send("QUIT", expectCode: "221") {
                                                    completion(.success(()))
                                                }
                                            }
                                        }
                                    }
                                }
                                
                                sendRecipients(recipients)
                            }
                        }
                    }
                }
            }
        }
    }
    
    func archive(id: String) async throws {
        throw MailServiceError.unsupported
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

    /// RFC 2047 MIME encoding for email headers (Subject, etc.)
    /// Encodes non-ASCII characters so they display correctly in email clients

    func mimeEncodedHeader() -> String {
        // Check if encoding is needed (contains non-ASCII characters)
        let needsEncoding = self.unicodeScalars.contains { !$0.isASCII }

        if !needsEncoding {
            return self
        }

        // Use RFC 2047 Base64 encoding: =?charset?encoding?encoded_text?=
        guard let data = self.data(using: .utf8) else { return self }
        let base64 = data.base64EncodedString()
        return "=?UTF-8?B?\(base64)?="
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

        print("🎫 Token exchange complete:")
        print("   - access_token: \(tokens.accessToken.prefix(20))...")
        print(
            "   - refresh_token: \(tokens.refreshToken != nil ? "present" : "❌ NOT RETURNED BY GOOGLE")"
        )
        print("   - expires_in: \(tokens.expiresIn ?? -1)s")

        // Persist tokens for this provider (legacy)
        storeTokensForProvider(
            provider, accessToken: tokens.accessToken, refreshToken: tokens.refreshToken,
            expiresIn: tokens.expiresIn)

        return tokens
    }

    // Exchange a refresh token for a new access token
    func refreshAccessToken(refreshToken: String, config: OAuthConfiguration, email: String? = nil)
        async throws
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
        guard let httpResponse = response as? HTTPURLResponse else {
            throw MailServiceError.networkFailure
        }

        // Handle refresh token failures
        if httpResponse.statusCode != 200 {
            if let errorText = String(data: data, encoding: .utf8) {
                print("⚠️ Refresh token exchange failed (\(httpResponse.statusCode)): \(errorText)")
            }

            // 400/401 typically means the refresh token is invalid/revoked
            if httpResponse.statusCode == 400 || httpResponse.statusCode == 401 {
                throw MailServiceError.refreshFailed(email: email ?? "unknown")
            }

            throw MailServiceError.networkFailure
        }

        let decoder = JSONDecoder()
        let tokenResp = try decoder.decode(TokenResponse.self, from: data)
        return tokenResp
    }

    // Ensure we have a valid access token for this provider (refresh if expired)
    // Account-specific token validation
    func ensureValidAccessToken(
        for provider: MailProvider, email: String, config: OAuthConfiguration
    ) async throws
        -> String
    {
        print("🔑 Checking token for \(email)")

        // Check account-specific token first
        if let expiry = accessTokenExpiry(for: provider, email: email), expiry > Date(),
            let access = KeychainHelper.shared.read(
                account: accessTokenKey(for: provider, email: email))
        {
            print("✓ Token found for \(email) (expires: \(expiry))")
            return access
        }

        print("⏰ Token expired or missing for \(email), attempting refresh...")

        // Try to refresh using account-specific refresh token
        guard
            let refresh = KeychainHelper.shared.read(
                account: refreshTokenKey(for: provider, email: email))
        else {
            print("❌ No refresh token for \(email) - need re-authentication")
            throw MailServiceError.tokenExpired(email: email)
        }

        print("🔄 Refreshing token for \(email)")
        do {
            let newTokens = try await refreshAccessToken(
                refreshToken: refresh, config: config, email: email)
            storeTokensForAccount(
                provider: provider, email: email, accessToken: newTokens.accessToken,
                refreshToken: newTokens.refreshToken ?? refresh, expiresIn: newTokens.expiresIn)
            print("✅ Token refreshed successfully for \(email)")
            return newTokens.accessToken
        } catch let error as MailServiceError {
            // Clear invalid tokens so we don't keep trying
            clearTokensForAccount(provider: provider, email: email)
            throw error
        } catch {
            // Clear tokens and wrap as refresh failed
            clearTokensForAccount(provider: provider, email: email)
            print("❌ Token refresh failed for \(email): \(error)")
            throw MailServiceError.refreshFailed(email: email)
        }
    }

    // Legacy function - for backward compatibility
    func ensureValidAccessToken(for provider: MailProvider, config: OAuthConfiguration) async throws
        -> String
    {
        if let expiry = accessTokenExpiry(for: provider), expiry > Date(),
            let access = KeychainHelper.shared.read(account: legacyAccessTokenKey(for: provider))
        {
            return access
        }

        guard
            let refresh = KeychainHelper.shared.read(account: legacyRefreshTokenKey(for: provider))
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

/// Custom error to signal a 401 that might be recoverable with token refresh
enum APIError: Error {
    case unauthorized  // 401 - might be recoverable
    case forbidden  // 403 - not recoverable
    case rateLimited(retryAfter: Double?)  // 429 - rate limited
    case other(Int)
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
                throw APIError.unauthorized
            }
            if httpResponse.statusCode == 403 {
                throw APIError.forbidden
            }
            if httpResponse.statusCode == 429 {
                // Parse Retry-After from header first, then try body
                var retryAfter = httpResponse.parseRetryAfter()

                // If header didn't have it, try parsing from the error body
                if retryAfter == nil, let errorText = String(data: data, encoding: .utf8) {
                    retryAfter = parseRetryAfterFromGmailError(errorText)
                }

                // Default to 120 seconds if we couldn't parse a time
                let finalRetryAfter = retryAfter ?? 120
                print("🚫 Rate limited (429), retry after: \(Int(finalRetryAfter))s")
                throw APIError.rateLimited(retryAfter: finalRetryAfter)
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

// MARK: - Retry-After Header Parsing

extension HTTPURLResponse {
    /// Parse the Retry-After header value (can be seconds or HTTP date)
    func parseRetryAfter() -> Double? {
        guard let retryAfter = value(forHTTPHeaderField: "Retry-After") else {
            return nil
        }

        return Self.parseRetryAfterValue(retryAfter)
    }

    /// Parse a retry-after value from any source (header or body)
    static func parseRetryAfterValue(_ retryAfter: String) -> Double? {
        // Try parsing as seconds first
        if let seconds = Double(retryAfter) {
            return seconds
        }

        // Try parsing as HTTP date (e.g., "Wed, 21 Oct 2015 07:28:00 GMT")
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        formatter.locale = Locale(identifier: "en_US_POSIX")

        if let date = formatter.date(from: retryAfter) {
            let seconds = date.timeIntervalSinceNow
            return seconds > 0 ? seconds : 1  // At least 1 second
        }

        // Try ISO 8601 format (used by Google in error messages)
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = isoFormatter.date(from: retryAfter) {
            let seconds = date.timeIntervalSinceNow
            return seconds > 0 ? seconds : 1  // At least 1 second
        }

        // Try ISO 8601 without fractional seconds
        let isoFormatterSimple = ISO8601DateFormatter()
        if let date = isoFormatterSimple.date(from: retryAfter) {
            let seconds = date.timeIntervalSinceNow
            return seconds > 0 ? seconds : 1
        }

        return nil
    }
}

/// Parse retry time from Gmail's error response body
func parseRetryAfterFromGmailError(_ errorBody: String) -> Double? {
    // Gmail format: "Retry after 2025-12-03T17:34:17.248Z"
    if let range = errorBody.range(of: "Retry after ") {
        let afterRetry = errorBody[range.upperBound...]
        // Extract the timestamp (ends at quote or comma or end)
        let timestamp = afterRetry.prefix(while: { $0 != "\"" && $0 != "," && $0 != "}" })
        let cleaned = String(timestamp).trimmingCharacters(in: .whitespaces)
        if let seconds = HTTPURLResponse.parseRetryAfterValue(cleaned) {
            // If the time is in the past (negative seconds), ignore it
            if seconds <= 0 {
                print("📅 Gmail retry-after timestamp \(cleaned) is in the past, ignoring")
                return nil
            }
            print("📅 Parsed Gmail retry-after: \(cleaned) = \(Int(seconds))s from now")
            return seconds
        }
    }
    return nil
}
