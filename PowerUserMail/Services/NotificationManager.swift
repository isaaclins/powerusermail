//
//  NotificationManager.swift
//  PowerUserMail
//
//  Handles local push notifications for new emails
//

import Combine
import Foundation
import UserNotifications

@MainActor
final class NotificationManager: ObservableObject {
    static let shared = NotificationManager()

    @Published private(set) var isAuthorized = false
    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    private var knownMessageIDs: Set<String> = []
    private var hasInitialized = false
    private var isInitialLoad = true  // Track if we're still in initial load phase
    private var initialLoadMessageCount = 0  // Track how many messages we expect

    private init() {
        Task {
            await refreshAuthorizationStatus()
        }
    }

    // MARK: - Authorization

    func requestAuthorization() async {
        let center = UNUserNotificationCenter.current()

        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            isAuthorized = granted

            if granted {
                print("✅ Notification authorization granted")
            } else {
                print("❌ Notification authorization denied")
            }
        } catch {
            print("❌ Notification authorization error: \(error)")
        }

        await refreshAuthorizationStatus()
    }

    func refreshAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationStatus = settings.authorizationStatus

        let allowedStatuses: [UNAuthorizationStatus] = [.authorized, .provisional,]
        isAuthorized = allowedStatuses.contains(settings.authorizationStatus)

        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            print("🔔 Notification permissions: \(settings.authorizationStatus.rawValue)")
        case .denied:
            print("❌ Notifications denied at system level")
        case .notDetermined:
            print("ℹ️ Notification permission not determined")
        @unknown default:
            print("⚠️ Unknown notification authorization status: \(settings.authorizationStatus.rawValue)")
        }
    }

    // MARK: - Track Known Messages

    /// Initialize with existing messages (call on first load to avoid notifying for old emails)
    func initializeKnownMessages(_ messageIDs: [String]) {
        guard !hasInitialized else { return }
        knownMessageIDs = Set(messageIDs)
        hasInitialized = true
        print("📧 Initialized with \(knownMessageIDs.count) known messages")
    }

    /// Check for new messages and send notifications
    func checkForNewMessages(conversations: [Conversation], myEmail: String) {
        let allIDs = conversations.flatMap { $0.messages.map { $0.id } }

        // First load - just track all messages, don't notify
        if !hasInitialized {
            initializeKnownMessages(allIDs)
            return
        }

        // During initial streaming load, just keep tracking IDs without notifying
        // This prevents spam during the progressive loading of ~100 threads
        if isInitialLoad {
            let newCount = allIDs.count
            if newCount > initialLoadMessageCount {
                // Still loading more messages
                initialLoadMessageCount = newCount
                for id in allIDs {
                    knownMessageIDs.insert(id)
                }
                return
            } else {
                // No new messages came in this check - initial load is complete
                isInitialLoad = false
                print("📧 Initial load complete with \(knownMessageIDs.count) messages")
                return
            }
        }

        var newMessages: [Email] = []

        for conversation in conversations {
            for message in conversation.messages {
                // Skip messages we've already seen
                if knownMessageIDs.contains(message.id) {
                    continue
                }

                // Skip messages from self
                if message.from.localizedCaseInsensitiveContains(myEmail) {
                    knownMessageIDs.insert(message.id)
                    continue
                }

                // This is a new message from someone else
                newMessages.append(message)
                knownMessageIDs.insert(message.id)
            }
        }

        // Send notifications for new messages
        for message in newMessages {
            sendNotification(for: message)

            // Mark the conversation as unread
            if let conversation = conversations.first(where: {
                $0.messages.contains(where: { $0.id == message.id })
            }) {
                // Remove from read state to mark as unread
                if ConversationStateStore.shared.isRead(conversationId: conversation.id) {
                    ConversationStateStore.shared.toggleRead(conversationId: conversation.id)
                }
            }
        }

        if !newMessages.isEmpty {
            print("🔔 Found \(newMessages.count) new message(s)")
        }
    }

    // MARK: - Send Notification

    private func sendNotification(for email: Email) {
        guard isAuthorized else { return }

        let content = UNMutableNotificationContent()
        content.title = extractSenderName(from: email.from)
        content.subtitle = email.subject
        content.body = email.preview.isEmpty ? email.body.prefix(100).description : email.preview
        content.sound = .default
        content.categoryIdentifier = "NEW_EMAIL"

        // Add user info for handling tap
        content.userInfo = [
            "emailId": email.id,
            "threadId": email.threadId,
            "from": email.from,
        ]

        // Create unique identifier
        let identifier = "email-\(email.id)"

        // Trigger immediately
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)

        let request = UNNotificationRequest(
            identifier: identifier, content: content, trigger: trigger)

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ Failed to send notification: \(error)")
            } else {
                print("🔔 Notification sent for email from \(email.from)")
            }
        }
    }

    /// Extract display name from email address
    private func extractSenderName(from email: String) -> String {
        // Handle format: "Name <email@example.com>"
        if let nameEnd = email.firstIndex(of: "<") {
            let name = String(email[..<nameEnd]).trimmingCharacters(in: .whitespaces)
            if !name.isEmpty {
                return name.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            }
        }

        // Handle format: "email@example.com"
        if let atIndex = email.firstIndex(of: "@") {
            return String(email[..<atIndex])
        }

        return email
    }

    // MARK: - Badge Management

    func updateBadgeCount(_ count: Int) {
        UNUserNotificationCenter.current().setBadgeCount(count) { error in
            if let error = error {
                print("❌ Failed to update badge: \(error)")
            }
        }
    }

    func clearBadge() {
        updateBadgeCount(0)
    }

    // MARK: - Account Switching

    /// Reset state when switching accounts - CRITICAL for data isolation
    func resetForNewAccount() {
        print("🔄 NotificationManager: Resetting for new account")
        knownMessageIDs.removeAll()
        hasInitialized = false
        isInitialLoad = true
        initialLoadMessageCount = 0
        clearBadge()

        // Clear any pending notifications from the previous account
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
    }
}
