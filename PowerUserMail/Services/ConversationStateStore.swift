import Foundation
import Combine

/// Manages local state for conversations (pinned, muted)
final class ConversationStateStore: ObservableObject {
    static let shared = ConversationStateStore()
    
    @Published private(set) var pinnedConversationIDs: Set<String> = []
    @Published private(set) var mutedConversationIDs: Set<String> = []
    
    private let pinnedKey = "pinnedConversations"
    private let mutedKey = "mutedConversations"
    
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
    
    // MARK: - Persistence
    
    private func loadFromDefaults() {
        if let pinned = UserDefaults.standard.array(forKey: pinnedKey) as? [String] {
            pinnedConversationIDs = Set(pinned)
        }
        if let muted = UserDefaults.standard.array(forKey: mutedKey) as? [String] {
            mutedConversationIDs = Set(muted)
        }
    }
    
    private func saveToDefaults() {
        UserDefaults.standard.set(Array(pinnedConversationIDs), forKey: pinnedKey)
        UserDefaults.standard.set(Array(mutedConversationIDs), forKey: mutedKey)
    }
}

