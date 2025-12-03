import Combine
import Foundation

/// Gmail Push Notification service using Pub/Sub for real-time email updates
/// Falls back to polling when push is unavailable
@MainActor
final class GmailPushService: ObservableObject {
    static let shared = GmailPushService()

    /// Current sync state per account
    struct SyncState {
        var historyId: String?
        var lastSyncTime: Date?
        var isPushEnabled: Bool = false
        var watchExpiration: Date?
    }

    @Published private(set) var syncStates: [String: SyncState] = [:]

    // Callback for when new messages are detected
    var onNewMessages: ((_ email: String, _ messageIds: [String]) -> Void)?

    // Configuration
    private let pollInterval: TimeInterval = 300  // 5 minutes fallback polling
    private let watchRenewalBuffer: TimeInterval = 3600  // Renew watch 1 hour before expiry

    private var pollTimers: [String: Timer] = [:]
    private var watchRenewalTasks: [String: Task<Void, Never>] = [:]

    private init() {}

    // MARK: - Public API

    /// Start sync for an account - attempts push, falls back to polling
    func startSync(for email: String, accessToken: String) async {
        print("📡 GmailPush: Starting sync for \(email)")

        // Try to set up push notifications first
        let pushSuccess = await setupPushNotifications(for: email, accessToken: accessToken)

        if pushSuccess {
            print("✅ GmailPush: Push notifications enabled for \(email)")
        } else {
            print("⚠️ GmailPush: Push unavailable, using polling for \(email)")
        }

        // Always start fallback polling (less frequent if push is working)
        startFallbackPolling(for: email)

        // Get initial historyId
        await fetchInitialHistoryId(for: email, accessToken: accessToken)
    }

    /// Stop sync for an account
    func stopSync(for email: String) {
        print("🛑 GmailPush: Stopping sync for \(email)")

        pollTimers[email]?.invalidate()
        pollTimers[email] = nil

        watchRenewalTasks[email]?.cancel()
        watchRenewalTasks[email] = nil

        syncStates[email] = nil
    }

    /// Perform delta sync using historyId
    func performDeltaSync(for email: String, accessToken: String) async -> [String]? {
        guard let state = syncStates[email], let historyId = state.historyId else {
            print("⚠️ GmailPush: No historyId for \(email), need full sync")
            return nil
        }

        // Check rate limit first
        let waitTime = await RateLimiter.shared.shouldWait(for: email)
        if waitTime > 0 {
            print("⏳ GmailPush: Waiting \(Int(waitTime))s before delta sync for \(email)")
            try? await Task.sleep(nanoseconds: UInt64(waitTime * 1_000_000_000))
        }

        await RateLimiter.shared.willMakeRequest(for: email)

        do {
            let (newMessageIds, newHistoryId) = try await fetchHistoryChanges(
                for: email,
                accessToken: accessToken,
                startHistoryId: historyId
            )

            await RateLimiter.shared.requestSucceeded(for: email)

            // Update state
            var updatedState = syncStates[email] ?? SyncState()
            if let newId = newHistoryId {
                updatedState.historyId = newId
            }
            updatedState.lastSyncTime = Date()
            syncStates[email] = updatedState

            if !newMessageIds.isEmpty {
                print(
                    "📬 GmailPush: Delta sync found \(newMessageIds.count) new messages for \(email)"
                )
                onNewMessages?(email, newMessageIds)
            }

            return newMessageIds
        } catch let error as RateLimitError {
            await RateLimiter.shared.requestRateLimited(
                for: email, retryAfterSeconds: error.retryAfter)
            return nil
        } catch {
            await RateLimiter.shared.requestFailed(for: email)
            print("❌ GmailPush: Delta sync failed for \(email): \(error)")
            return nil
        }
    }

    /// Update historyId after a full sync
    func updateHistoryId(for email: String, historyId: String) {
        var state = syncStates[email] ?? SyncState()
        state.historyId = historyId
        state.lastSyncTime = Date()
        syncStates[email] = state
    }

    // MARK: - Push Notifications (Pub/Sub)

    private func setupPushNotifications(for email: String, accessToken: String) async -> Bool {
        // Note: Gmail Push requires a Google Cloud Pub/Sub topic and subscription
        // For a desktop app, you'd need a webhook endpoint to receive push notifications
        // This typically requires a server component

        // For now, we'll check if push could be enabled and return false
        // In a production app, you would:
        // 1. Have a server endpoint that receives Pub/Sub messages
        // 2. Call users.watch() to set up the watch
        // 3. Use a WebSocket or long-polling to your server to get notifications

        // Placeholder: Push not implemented yet, will use efficient polling
        var state = syncStates[email] ?? SyncState()
        state.isPushEnabled = false
        syncStates[email] = state

        return false
    }

    // MARK: - History API (Delta Sync)

    private func fetchInitialHistoryId(for email: String, accessToken: String) async {
        let waitTime = await RateLimiter.shared.shouldWait(for: email)
        if waitTime > 0 {
            try? await Task.sleep(nanoseconds: UInt64(waitTime * 1_000_000_000))
        }

        await RateLimiter.shared.willMakeRequest(for: email)

        do {
            // Get the current historyId from profile
            let url = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/profile")!
            var request = URLRequest(url: url)
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }

            if httpResponse.statusCode == 429 {
                throw RateLimitError(retryAfter: httpResponse.parseRetryAfter())
            }

            guard httpResponse.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }

            await RateLimiter.shared.requestSucceeded(for: email)

            struct ProfileResponse: Codable {
                let historyId: String
            }

            let profile = try JSONDecoder().decode(ProfileResponse.self, from: data)

            var state = syncStates[email] ?? SyncState()
            state.historyId = profile.historyId
            state.lastSyncTime = Date()
            syncStates[email] = state

            print("📍 GmailPush: Initial historyId for \(email): \(profile.historyId)")
        } catch let error as RateLimitError {
            await RateLimiter.shared.requestRateLimited(
                for: email, retryAfterSeconds: error.retryAfter)
        } catch {
            await RateLimiter.shared.requestFailed(for: email)
            print("❌ GmailPush: Failed to get initial historyId: \(error)")
        }
    }

    private func fetchHistoryChanges(
        for email: String,
        accessToken: String,
        startHistoryId: String
    ) async throws -> (messageIds: [String], newHistoryId: String?) {
        var components = URLComponents(
            string: "https://gmail.googleapis.com/gmail/v1/users/me/history")!
        components.queryItems = [
            URLQueryItem(name: "startHistoryId", value: startHistoryId),
            URLQueryItem(name: "historyTypes", value: "messageAdded"),
            URLQueryItem(name: "maxResults", value: "100"),
        ]

        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        // Handle rate limiting
        if httpResponse.statusCode == 429 {
            throw RateLimitError(retryAfter: httpResponse.parseRetryAfter())
        }

        // Handle historyId too old (need full sync)
        if httpResponse.statusCode == 404 {
            print("⚠️ GmailPush: historyId too old, need full sync")
            return ([], nil)
        }

        guard httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        struct HistoryResponse: Codable {
            let history: [HistoryRecord]?
            let historyId: String?
            let nextPageToken: String?
        }

        struct HistoryRecord: Codable {
            let id: String
            let messagesAdded: [MessageAddedEvent]?
        }

        struct MessageAddedEvent: Codable {
            let message: MessageRef
        }

        struct MessageRef: Codable {
            let id: String
            let threadId: String
        }

        let historyResponse = try JSONDecoder().decode(HistoryResponse.self, from: data)

        var messageIds: [String] = []
        if let history = historyResponse.history {
            for record in history {
                if let added = record.messagesAdded {
                    messageIds.append(contentsOf: added.map { $0.message.id })
                }
            }
        }

        return (messageIds, historyResponse.historyId)
    }

    // MARK: - Fallback Polling

    private func startFallbackPolling(for email: String) {
        // Cancel existing timer
        pollTimers[email]?.invalidate()

        // Use longer interval if push is enabled
        let interval = (syncStates[email]?.isPushEnabled == true) ? pollInterval * 2 : pollInterval

        print("⏰ GmailPush: Starting fallback polling for \(email) every \(Int(interval))s")

        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) {
            [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.onPollTimerFired(for: email)
            }
        }

        pollTimers[email] = timer
    }

    private func onPollTimerFired(for email: String) async {
        // Notify that it's time to sync
        // The actual sync will be handled by InboxViewModel
        NotificationCenter.default.post(
            name: Notification.Name("GmailPollTimer"),
            object: nil,
            userInfo: ["email": email]
        )
    }
}

// MARK: - Rate Limit Error

struct RateLimitError: Error {
    let retryAfter: Double?

    init(retryAfter: Double? = nil) {
        self.retryAfter = retryAfter
    }
}
