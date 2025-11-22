import Foundation

enum MailProvider: String, CaseIterable, Codable, Identifiable {
    case gmail
    case outlook

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .gmail:
            return "Gmail"
        case .outlook:
            return "Outlook"
        }
    }

    var iconSystemName: String {
        switch self {
        case .gmail:
            return "envelope.open.fill"
        case .outlook:
            return "envelope.circle.fill"
        }
    }

    var assetName: String {
        switch self {
        case .gmail:
            return "GmailLogo"
        case .outlook:
            return "OutlookLogo"
        }
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

    init(
        id: UUID = UUID(), provider: MailProvider, emailAddress: String, displayName: String,
        accessToken: String, refreshToken: String? = nil, lastSyncDate: Date? = nil,
        isAuthenticated: Bool = false
    ) {
        self.id = id
        self.provider = provider
        self.emailAddress = emailAddress
        self.displayName = displayName
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.lastSyncDate = lastSyncDate
        self.isAuthenticated = isAuthenticated
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
}
