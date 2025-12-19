import Foundation
import SwiftUI
import Combine
import UserNotifications

/// Central settings store persisted to UserDefaults.
@MainActor
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    @Published var payload: SettingsPayload {
        didSet { persist() }
    }

    private let storageKey = "SettingsStore.v1"
    private let defaults = UserDefaults.standard

    init() {
        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode(SettingsPayload.self, from: data) {
            payload = decoded
        } else {
            payload = SettingsPayload()
        }
    }

    // MARK: - Derived Bindings

    func binding<Value>(_ keyPath: WritableKeyPath<SettingsPayload, Value>) -> Binding<Value> {
        Binding(
            get: { self.payload[keyPath: keyPath] },
            set: { self.payload[keyPath: keyPath] = $0 }
        )
    }

    // MARK: - Actions

    func requestNotificationPermission() async {
        await NotificationManager.shared.requestAuthorization()
        await NotificationManager.shared.refreshAuthorizationStatus()
    }

    func openSystemNotificationSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") else { return }
        NSWorkspace.shared.open(url)
    }

    func sendTestNotification() {
        let demo = Email(
            id: UUID().uuidString,
            threadId: UUID().uuidString,
            subject: "Test Notification",
            from: "PowerUserMail",
            to: [],
            preview: "This is a sample notification from Settings.",
            body: "This is a sample notification from Settings.",
            receivedAt: Date(),
            isRead: false,
            isArchived: false,
            attachments: []
        )
        NotificationManager.shared.checkForNewMessages(
            conversations: [Conversation(id: demo.threadId, person: "PowerUserMail", messages: [demo])],
            myEmail: payload.lastActiveEmail
        )
    }

    func clearBadge() {
        NotificationManager.shared.clearBadge()
    }

    func resetAppState() {
        // Clear settings
        defaults.removeObject(forKey: storageKey)
        payload = SettingsPayload()

        // Clear app caches/user defaults that are safe to reset
        UserDefaults.standard.removePersistentDomain(forName: Bundle.main.bundleIdentifier ?? "")
        NotificationManager.shared.resetForNewAccount()
    }

    func clearLocalCache() {
        let fileManager = FileManager.default
        if let cacheDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first {
            try? fileManager.removeItem(at: cacheDir)
        }
    }

    // MARK: - Persistence

    private func persist() {
        if let data = try? JSONEncoder().encode(payload) {
            defaults.set(data, forKey: storageKey)
        }
    }
}

// MARK: - Data Model

struct SettingsPayload: Codable {
    // Accounts
    var lastActiveEmail: String = ""

    // Notifications
    var notificationsEnabled: Bool = true
    var notificationSoundEnabled: Bool = true
    var badgeMode: BadgeMode = .unread
    var quietHours: QuietHours = QuietHours()

    // Appearance
    var theme: AppTheme = .system

    // Mail Handling
    var markAsReadDelay: MarkAsReadDelay = .immediate
    var categories: [MailCategory] = []
    var autoArchiveRules: [Rule] = []
    var categoryRules: [Rule] = []

    // Inbox Behavior
    var pollingMode: PollingMode = .auto
    var autoRefreshOnWake: Bool = true

    // Composer
    var perAccountSignature: [String: String] = [:]
    var smartAutocomplete: Bool = true
    var grammarCheck: Bool = true
    var undoSendEnabled: Bool = true
    var defaultFontName: String = "San Francisco"
    var defaultFontSize: Double = 14
    var attachmentWarning: Bool = true

    // Shortcuts
    var commandPaletteEnabled: Bool = true
    var shortcutOverrides: [String: String] = [:]  // command title -> shortcut display

    // Privacy & Security
    var cacheSizeLimitMB: Int = 512
    var attachmentDownloadPolicy: AttachmentDownloadPolicy = .ask
    var remoteImagesPolicy: RemoteImagesPolicy = .ask

    // Updates & Diagnostics
    var diagnosticsOptIn: Bool = false

    // Advanced
    var featureFlags: [FeatureFlag] = []
    var developerMode: Bool = false
}

// MARK: - Supporting Types

enum AppTheme: String, CaseIterable, Codable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

enum BadgeMode: String, CaseIterable, Codable, Identifiable {
    case all, unread, mentions, none
    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
}

enum PollingMode: String, CaseIterable, Codable, Identifiable {
    case auto, normal, lowPower
    var id: String { rawValue }
    var description: String {
        switch self {
        case .auto: return "Adaptive"
        case .normal: return "Standard"
        case .lowPower: return "Lower frequency"
        }
    }
}

enum MarkAsReadDelay: String, CaseIterable, Codable, Identifiable {
    case immediate
    case seconds5
    case seconds15
    case seconds30

    var id: String { rawValue }
    var seconds: Int {
        switch self {
        case .immediate: return 0
        case .seconds5: return 5
        case .seconds15: return 15
        case .seconds30: return 30
        }
    }
    var displayName: String {
        switch self {
        case .immediate: return "Immediate"
        default: return "After \(seconds) seconds"
        }
    }
}

enum AttachmentDownloadPolicy: String, CaseIterable, Codable, Identifiable {
    case auto, ask
    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
}

enum RemoteImagesPolicy: String, CaseIterable, Codable, Identifiable {
    case always, ask, block
    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
}

struct QuietHours: Codable, Equatable {
    var enabled: Bool = false
    var startHour: Int = 22
    var endHour: Int = 7
}

struct MailCategory: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var colorHex: String = "#5B8DEF"
    var position: Int = 0
}

struct Rule: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var keywords: [String]
    var sender: String?
    var subjectContains: String?
    var destinationCategoryId: UUID?
    var autoArchive: Bool = false
}

struct FeatureFlag: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var key: String
    var enabled: Bool
    var description: String
}

