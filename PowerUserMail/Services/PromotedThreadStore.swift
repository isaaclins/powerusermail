import Foundation

class PromotedThreadStore {
    static let shared = PromotedThreadStore()
    private let key = "promoted_threads"
    
    var promotedThreadIDs: Set<String> {
        get {
            let list = UserDefaults.standard.stringArray(forKey: key) ?? []
            return Set(list)
        }
        set {
            UserDefaults.standard.set(Array(newValue), forKey: key)
        }
    }
    
    func promote(threadId: String) {
        var current = promotedThreadIDs
        current.insert(threadId)
        promotedThreadIDs = current
        // Post notification to reload inbox
        NotificationCenter.default.post(name: Notification.Name("ReloadInbox"), object: nil)
    }
    
    func demote(threadId: String) {
        var current = promotedThreadIDs
        current.remove(threadId)
        promotedThreadIDs = current
        NotificationCenter.default.post(name: Notification.Name("ReloadInbox"), object: nil)
    }
    
    func isPromoted(threadId: String) -> Bool {
        promotedThreadIDs.contains(threadId)
    }
}
