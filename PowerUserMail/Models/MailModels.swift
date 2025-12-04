import Foundation

enum MailProvider: String, CaseIterable, Codable, Identifiable {
    case gmail
    case outlook
    case imap

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .gmail:
            return "Gmail"
        case .outlook:
            return "Outlook"
        case .imap:
            return "IMAP"
        }
    }

    var iconSystemName: String {
        switch self {
        case .gmail:
            return "envelope.open.fill"
        case .outlook:
            return "envelope.circle.fill"
        case .imap:
            return "server.rack"
        }
    }

    var assetName: String {
        switch self {
        case .gmail:
            return "GmailLogo"
        case .outlook:
            return "OutlookLogo"
        case .imap:
            return ""  // Will use system icon instead
        }
    }
    
    /// Whether this provider uses OAuth (vs direct credentials)
    var usesOAuth: Bool {
        switch self {
        case .gmail, .outlook:
            return true
        case .imap:
            return false
        }
    }
}

// MARK: - IMAP Configuration
struct IMAPConfiguration: Codable, Equatable {
    var imapHost: String
    var imapPort: Int
    var smtpHost: String
    var smtpPort: Int
    var username: String
    var password: String  // Will be stored in Keychain
    var useSSL: Bool
    var useTLS: Bool
    
    init(
        imapHost: String = "",
        imapPort: Int = 993,
        smtpHost: String = "",
        smtpPort: Int = 587,
        username: String = "",
        password: String = "",
        useSSL: Bool = true,
        useTLS: Bool = true
    ) {
        self.imapHost = imapHost
        self.imapPort = imapPort
        self.smtpHost = smtpHost
        self.smtpPort = smtpPort
        self.username = username
        self.password = password
        self.useSSL = useSSL
        self.useTLS = useTLS
    }
}

struct Account: Identifiable, Codable, Equatable {
    let id: UUID
    var provider: MailProvider
    var emailAddress: String
    var displayName: String
    var accessToken: String
    var refreshToken: String?
    var lastSyncDate: Date?
    var isAuthenticated: Bool
    var profilePictureURL: String?

    init(
        id: UUID = UUID(), provider: MailProvider, emailAddress: String, displayName: String,
        accessToken: String, refreshToken: String? = nil, lastSyncDate: Date? = nil,
        isAuthenticated: Bool = false, profilePictureURL: String? = nil
    ) {
        self.id = id
        self.provider = provider
        self.emailAddress = emailAddress
        self.displayName = displayName
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.lastSyncDate = lastSyncDate
        self.isAuthenticated = isAuthenticated
        self.profilePictureURL = profilePictureURL
    }
    
    /// Returns the profile picture URL or a Gravatar fallback
    var effectiveProfilePictureURL: URL? {
        if let urlString = profilePictureURL, let url = URL(string: urlString) {
            return url
        }
        return gravatarURL
    }
    
    /// Gravatar URL based on email hash
    var gravatarURL: URL? {
        let email = emailAddress.lowercased().trimmingCharacters(in: .whitespaces)
        guard let data = email.data(using: .utf8) else { return nil }
        
        // MD5 hash for Gravatar
        let hash = data.md5Hash
        return URL(string: "https://www.gravatar.com/avatar/\(hash)?s=200&d=identicon")
    }
}

// MARK: - MD5 Hash Extension for Gravatar
import Foundation
import CryptoKit

extension Data {
    var md5Hash: String {
        let digest = Insecure.MD5.hash(data: self)
        return digest.map { String(format: "%02hhx", $0) }.joined()
    }
}

struct EmailAttachment: Identifiable, Hashable, Codable {
    let id: UUID
    var fileName: String
    var mimeType: String
    var sizeInBytes: Int

    init(id: UUID = UUID(), fileName: String, mimeType: String, sizeInBytes: Int) {
        self.id = id
        self.fileName = fileName
        self.mimeType = mimeType
        self.sizeInBytes = sizeInBytes
    }
}

struct Email: Identifiable, Hashable, Codable {
    let id: String
    var threadId: String
    var subject: String
    var from: String
    var to: [String]
    var cc: [String]
    var bcc: [String]
    var preview: String
    var body: String
    var receivedAt: Date
    var isRead: Bool
    var isArchived: Bool
    var attachments: [EmailAttachment]

    init(
        id: String, threadId: String, subject: String, from: String, to: [String],
        cc: [String] = [], bcc: [String] = [], preview: String, body: String, receivedAt: Date,
        isRead: Bool = false, isArchived: Bool = false, attachments: [EmailAttachment] = []
    ) {
        self.id = id
        self.threadId = threadId
        self.subject = subject
        self.from = from
        self.to = to
        self.cc = cc
        self.bcc = bcc
        self.preview = preview
        self.body = body
        self.receivedAt = receivedAt
        self.isRead = isRead
        self.isArchived = isArchived
        self.attachments = attachments
    }
}

struct EmailThread: Identifiable, Hashable, Codable {
    let id: String
    var subject: String
    var messages: [Email]
    var participants: [String]
    var isMuted: Bool

    init(
        id: String, subject: String, messages: [Email], participants: [String],
        isMuted: Bool = false
    ) {
        self.id = id
        self.subject = subject
        self.messages = messages
        self.participants = participants
        self.isMuted = isMuted
    }

    var lastMessage: Email? { messages.sorted(by: { $0.receivedAt > $1.receivedAt }).first }
}

struct DraftMessage: Identifiable, Hashable {
    let id: UUID
    var to: [String]
    var cc: [String]
    var bcc: [String]
    var subject: String
    var body: String
    var isDirty: Bool

    init(
        id: UUID = UUID(), to: [String] = [], cc: [String] = [], bcc: [String] = [],
        subject: String = "", body: String = "", isDirty: Bool = false
    ) {
        self.id = id
        self.to = to
        self.cc = cc
        self.bcc = bcc
        self.subject = subject
        self.body = body
        self.isDirty = isDirty
    }
}

struct Conversation: Identifiable, Hashable {
    let id: String
    let person: String
    let messages: [Email]

    var latestMessage: Email? {
        messages.max(by: { $0.receivedAt < $1.receivedAt })
    }
    
    /// Returns true if conversation has unread messages and hasn't been locally marked as read
    var hasUnread: Bool {
        // If locally marked as read, consider it read
        if ConversationStateStore.shared.isRead(conversationId: id) {
            return false
        }
        // Otherwise, check the server-side read status
        return messages.contains { !$0.isRead }
    }
    
    var unreadCount: Int {
        if ConversationStateStore.shared.isRead(conversationId: id) {
            return 0
        }
        return messages.filter { !$0.isRead }.count
    }
}

// MARK: - Relative Time Formatter
extension Date {
    func relativeTimeString() -> String {
        let now = Date()
        let interval = now.timeIntervalSince(self)
        
        if interval < 60 {
            return "Just now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes) min ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return hours == 1 ? "1 hour ago" : "\(hours) hours ago"
        } else if interval < 172800 {
            return "Yesterday"
        } else if interval < 604800 {
            let days = Int(interval / 86400)
            return "\(days) days ago"
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .none
            return formatter.string(from: self)
        }
    }
}
