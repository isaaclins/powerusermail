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
    var isAuthenticated: Bool { get }
    func authenticate() async throws -> Account
    func fetchInbox() async throws -> [EmailThread]
    func fetchMessage(id: String) async throws -> Email
    func send(message: DraftMessage) async throws
    func archive(id: String) async throws
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

// MARK: - Services

final class GmailService: NSObject, MailService {
    private(set) var account: Account?
    var provider: MailProvider { .gmail }
    var isAuthenticated: Bool { account?.isAuthenticated == true }

    // TODO: Replace with your actual Google Client ID and Redirect URI
    private let config = OAuthConfiguration(
        authEndpoint: "https://accounts.google.com/o/oauth2/v2/auth",
        tokenEndpoint: "https://oauth2.googleapis.com/token",
        clientId: "YOUR_GOOGLE_CLIENT_ID",
        redirectUri: "com.googleusercontent.apps.YOUR_GOOGLE_CLIENT_ID:/oauth2redirect",
        scopes: ["https://mail.google.com/"]
    )

    func authenticate() async throws -> Account {
        let tokens = try await performOAuthFlow(config: config, provider: provider)
        // In a real app, you would fetch the user profile here to get the email/name
        let newAccount = Account(
            provider: provider, emailAddress: "user@gmail.com", displayName: "Gmail User",
            accessToken: tokens.accessToken, refreshToken: tokens.refreshToken,
            isAuthenticated: true)
        account = newAccount
        return newAccount
    }

    func fetchInbox() async throws -> [EmailThread] {
        guard isAuthenticated else { throw MailServiceError.authenticationRequired }
        return MockMailData.sampleThreads
    }

    func fetchMessage(id: String) async throws -> Email {
        guard isAuthenticated else { throw MailServiceError.authenticationRequired }
        return MockMailData.sampleEmail(id: id)
    }

    func send(message: DraftMessage) async throws {
        guard isAuthenticated else { throw MailServiceError.authenticationRequired }
    }

    func archive(id: String) async throws {
        guard isAuthenticated else { throw MailServiceError.authenticationRequired }
    }
}

final class OutlookService: NSObject, MailService {
    private(set) var account: Account?
    var provider: MailProvider { .outlook }
    var isAuthenticated: Bool { account?.isAuthenticated == true }

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
        // In a real app, you would fetch the user profile here
        let newAccount = Account(
            provider: provider, emailAddress: "user@outlook.com", displayName: "Outlook User",
            accessToken: tokens.accessToken, refreshToken: tokens.refreshToken,
            isAuthenticated: true)
        account = newAccount
        return newAccount
    }

    func fetchInbox() async throws -> [EmailThread] {
        guard isAuthenticated else { throw MailServiceError.authenticationRequired }
        return MockMailData.sampleThreads
    }

    func fetchMessage(id: String) async throws -> Email {
        guard isAuthenticated else { throw MailServiceError.authenticationRequired }
        return MockMailData.sampleEmail(id: id)
    }

    func send(message: DraftMessage) async throws {
        guard isAuthenticated else { throw MailServiceError.authenticationRequired }
    }

    func archive(id: String) async throws {
        guard isAuthenticated else { throw MailServiceError.authenticationRequired }
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
        return try await exchangeCodeForToken(code: code, pkce: pkce, config: config)
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
