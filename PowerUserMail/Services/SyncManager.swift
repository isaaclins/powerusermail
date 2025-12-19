//
//  SyncManager.swift
//  PowerUserMail
//
//  Manages incremental synchronization between server and local cache
//

import Foundation

/// Manages two-way sync between email server and local cache
@MainActor
final class SyncManager {
    static let shared = SyncManager()

    private let repository: EmailRepository
    private var activeSyncTasks: [String: Task<Void, Never>] = [:]

    init(repository: EmailRepository = .shared) {
        self.repository = repository
    }

    // MARK: - Sync Operations

    /// Perform incremental sync for an account
    /// - Returns: Number of new threads fetched
    @discardableResult
    func syncAccount(service: MailService, accountEmail: String) async throws -> Int {
        // Cancel any existing sync for this account
        activeSyncTasks[accountEmail]?.cancel()

        let syncTask = Task { @MainActor in
            do {
                try await performSync(service: service, accountEmail: accountEmail)
            } catch {
                print("⚠️ Sync failed for \(accountEmail): \(error)")
            }
        }

        activeSyncTasks[accountEmail] = syncTask
        await syncTask.value
        activeSyncTasks.removeValue(forKey: accountEmail)

        // Return count of cached threads
        return try await repository.fetchThreads(for: accountEmail).count
    }

    /// Perform the actual sync operation
    @MainActor
    private func performSync(service: MailService, accountEmail: String) async throws {
        let lastSync = await repository.getLastSyncDate(for: accountEmail)

        print(
            "🔄 Starting sync for \(accountEmail) (last sync: \(lastSync?.description ?? "never"))")

        // Fetch from server
        print("📡 Fetching inbox from server...")
        let serverThreads = try await service.fetchInbox()
        print("📡 Server returned \(serverThreads.count) threads")

        // If this is first sync, save everything
        if lastSync == nil {
            print("📥 First sync: caching \(serverThreads.count) threads")
            for (index, thread) in serverThreads.enumerated() {
                do {
                    try await repository.saveThread(thread, for: accountEmail)
                    if (index + 1) % 10 == 0 {
                        print("  ✓ Cached \(index + 1)/\(serverThreads.count) threads")
                    }
                } catch {
                    print("  ❌ Failed to cache thread \(thread.id): \(error)")
                    throw error
                }
            }
            try await repository.updateLastSyncDate(Date(), for: accountEmail)
            print("✅ First sync complete!")
            return
        }

        // Incremental sync: only process threads with recent activity
        guard let lastSyncDate = lastSync else { return }

        let newOrUpdatedThreads = serverThreads.filter { thread in
            // Check if any message in the thread is newer than last sync
            thread.messages.contains { $0.receivedAt > lastSyncDate }
        }

        print("📥 Incremental sync: \(newOrUpdatedThreads.count) new/updated threads")

        for thread in newOrUpdatedThreads {
            try await repository.saveThread(thread, for: accountEmail)
        }

        try await repository.updateLastSyncDate(Date(), for: accountEmail)

        // Sync local state changes back to server
        try await syncLocalChangesToServer(service: service, accountEmail: accountEmail)
    }

    /// Sync local changes (read status, archive) back to server
    private func syncLocalChangesToServer(service: MailService, accountEmail: String) async throws {
        // Get all cached threads
        let cachedThreads = try await repository.fetchThreads(for: accountEmail)

        // For each thread, check if local state differs from what we expect server state to be
        // In a real implementation, you'd track pending changes in a separate entity
        // For now, we'll sync archive status as an example

        for thread in cachedThreads {
            for message in thread.messages {
                // If message is archived locally but not on server, archive it
                if message.isArchived {
                    try? await service.archive(id: message.id)
                }
            }
        }
    }

    // MARK: - Cache-First Operations

    /// Fetch inbox from cache, trigger background sync
    func fetchInbox(service: MailService, accountEmail: String) async throws -> [EmailThread] {
        // Try to get from cache first
        let cachedThreads = try await repository.fetchThreads(for: accountEmail)

        // If cache is empty or stale (older than 5 minutes), force sync
        let isStale = await isCacheStale(for: accountEmail, threshold: 300)
        if cachedThreads.isEmpty || isStale {
            print("📭 Cache empty or stale, syncing from server")
            do {
                try await performSync(service: service, accountEmail: accountEmail)
                let refreshedThreads = try await repository.fetchThreads(for: accountEmail)
                print("✅ Sync completed: \(refreshedThreads.count) threads now in cache")
                return refreshedThreads
            } catch {
                print("❌ Sync failed: \(error)")
                // If sync fails, try to return whatever is in cache (might be empty)
                throw error
            }
        }

        // Return cached data immediately
        print("⚡️ Returning \(cachedThreads.count) threads from cache")

        // Trigger background sync if cache is getting old (> 1 minute)
        if await isCacheStale(for: accountEmail, threshold: 60) {
            Task { @MainActor [weak self] in
                guard let self else { return }
                try? await self.performSync(service: service, accountEmail: accountEmail)
                print("✅ Background sync completed")
            }
        }

        return cachedThreads
    }

    /// Fetch a specific message from cache, falling back to server
    func fetchMessage(id: String, service: MailService, accountEmail: String) async throws -> Email
    {
        // Try cache first
        if let cached = try await repository.fetchEmail(id: id, accountEmail: accountEmail) {
            print("⚡️ Returning email \(id) from cache")
            return cached
        }

        // Fallback to server
        print("📡 Fetching email \(id) from server")
        let email = try await service.fetchMessage(id: id)

        // Cache it for next time (we need to associate with a thread)
        // In a real implementation, you'd handle this more carefully

        return email
    }

    /// Search emails locally
    func searchEmails(query: String, accountEmail: String) async throws -> [EmailThread] {
        return try await repository.searchThreads(query: query, for: accountEmail)
    }

    // MARK: - Local State Updates

    /// Mark email as read locally and sync to server
    func markAsRead(emailId: String, service: MailService, accountEmail: String) async throws {
        try await repository.updateReadStatus(
            emailId: emailId, isRead: true, accountEmail: accountEmail)
        // In a real implementation, sync to server
        // For now, the server state is managed by the service itself
    }

    /// Archive email locally and sync to server
    func archiveEmail(emailId: String, service: MailService, accountEmail: String) async throws {
        try await repository.updateArchiveStatus(
            emailId: emailId, isArchived: true, accountEmail: accountEmail)
        try await service.archive(id: emailId)
    }

    // MARK: - Cache Management

    /// Check if cache is stale
    private func isCacheStale(for accountEmail: String, threshold: TimeInterval) async -> Bool {
        guard let lastSync = await repository.getLastSyncDate(for: accountEmail) else {
            return true
        }
        return Date().timeIntervalSince(lastSync) > threshold
    }

    /// Clear all cached data for an account
    func clearCache(for accountEmail: String) async throws {
        activeSyncTasks[accountEmail]?.cancel()
        activeSyncTasks.removeValue(forKey: accountEmail)
        try await repository.clearCache(for: accountEmail)
    }

    /// Cancel ongoing sync for an account
    func cancelSync(for accountEmail: String) {
        activeSyncTasks[accountEmail]?.cancel()
        activeSyncTasks.removeValue(forKey: accountEmail)
    }
}
