import Foundation
import Combine

/// Manages local state for conversations (pinned, muted, read)
final class ConversationStateStore: ObservableObject {
    static let shared = ConversationStateStore()
    
    @Published private(set) var pinnedConversationIDs: Set<String> = []
    @Published private(set) var mutedConversationIDs: Set<String> = []
    @Published private(set) var readConversationIDs: Set<String> = []
    @Published private(set) var archivedConversationIDs: Set<String> = []
    
    private let pinnedKey = "pinnedConversations"
    private let mutedKey = "mutedConversations"
    private let readKey = "readConversations"
    private let archivedKey = "archivedConversations"
    
    private init() {
        loadFromDefaults()
    }
    
    // MARK: - Pinned
    
    func isPinned(conversationId: String) -> Bool {
        pinnedConversationIDs.contains(conversationId)
    }
    
    func togglePinned(conversationId: String) {
        if pinnedConversationIDs.contains(conversationId) {
            pinnedConversationIDs.remove(conversationId)
        } else {
            pinnedConversationIDs.insert(conversationId)
        }
        saveToDefaults()
    }
    
    func pin(conversationId: String) {
        pinnedConversationIDs.insert(conversationId)
        saveToDefaults()
    }
    
    func unpin(conversationId: String) {
        pinnedConversationIDs.remove(conversationId)
        saveToDefaults()
    }
    
    // MARK: - Muted
    
    func isMuted(conversationId: String) -> Bool {
        mutedConversationIDs.contains(conversationId)
    }
    
    func toggleMuted(conversationId: String) {
        if mutedConversationIDs.contains(conversationId) {
            mutedConversationIDs.remove(conversationId)
        } else {
            mutedConversationIDs.insert(conversationId)
        }
        saveToDefaults()
    }
    
    func mute(conversationId: String) {
        mutedConversationIDs.insert(conversationId)
        saveToDefaults()
    }
    
    func unmute(conversationId: String) {
        mutedConversationIDs.remove(conversationId)
        saveToDefaults()
    }
    
    // MARK: - Read State
    
    func isRead(conversationId: String) -> Bool {
        readConversationIDs.contains(conversationId)
    }
    
    func markAsRead(conversationId: String) {
        readConversationIDs.insert(conversationId)
        saveToDefaults()
    }
    
    func markAllAsRead(conversationIds: [String]) {
        for id in conversationIds {
            readConversationIDs.insert(id)
        }
        saveToDefaults()
    }
    
    func markAsUnread(conversationId: String) {
        readConversationIDs.remove(conversationId)
        saveToDefaults()
    }
    
    func toggleRead(conversationId: String) {
        if readConversationIDs.contains(conversationId) {
            readConversationIDs.remove(conversationId)
        } else {
            readConversationIDs.insert(conversationId)
        }
        saveToDefaults()
    }

    // MARK: - Archived

    func isArchived(conversationId: String) -> Bool {
        archivedConversationIDs.contains(conversationId)
    }

    func archive(conversationId: String) {
        archivedConversationIDs.insert(conversationId)
        saveToDefaults()
    }

    func unarchive(conversationId: String) {
        archivedConversationIDs.remove(conversationId)
        saveToDefaults()
    }

    func toggleArchived(conversationId: String) {
        if archivedConversationIDs.contains(conversationId) {
            archivedConversationIDs.remove(conversationId)
        } else {
            archivedConversationIDs.insert(conversationId)
        }
        saveToDefaults()
    }
    
    // MARK: - Persistence
    
    private func loadFromDefaults() {
        if let pinned = UserDefaults.standard.array(forKey: pinnedKey) as? [String] {
            pinnedConversationIDs = Set(pinned)
        }
        if let muted = UserDefaults.standard.array(forKey: mutedKey) as? [String] {
            mutedConversationIDs = Set(muted)
        }
        if let read = UserDefaults.standard.array(forKey: readKey) as? [String] {
            readConversationIDs = Set(read)
        }
        if let archived = UserDefaults.standard.array(forKey: archivedKey) as? [String] {
            archivedConversationIDs = Set(archived)
        }
    }
    
    private func saveToDefaults() {
        UserDefaults.standard.set(Array(pinnedConversationIDs), forKey: pinnedKey)
        UserDefaults.standard.set(Array(mutedConversationIDs), forKey: mutedKey)
        UserDefaults.standard.set(Array(readConversationIDs), forKey: readKey)
        UserDefaults.standard.set(Array(archivedConversationIDs), forKey: archivedKey)
    }
}

