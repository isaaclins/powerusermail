//
//  ConversationCommands.swift
//  PowerUserMail
//
//  Context-aware commands for the currently selected conversation
//

import Foundation

struct ArchiveConversationCommand: CommandPlugin {
    let id = "archive-conversation"
    let title = "Archive Conversation"
    let keywords = ["archive", "hide", "remove", "move", "folder"]
    let iconSystemName = "archivebox"
    
    var isContextual: Bool { true }
    
    func execute() {
        NotificationCenter.default.post(name: Notification.Name("ArchiveCurrentConversation"), object: nil)
    }
}

struct PinConversationCommand: CommandPlugin {
    let id = "pin-conversation"
    let title = "Pin Conversation"
    let keywords = ["pin", "stick", "top", "favorite", "star"]
    let iconSystemName = "pin"
    
    var isContextual: Bool { true }
    
    func execute() {
        NotificationCenter.default.post(name: Notification.Name("PinCurrentConversation"), object: nil)
    }
}

struct UnpinConversationCommand: CommandPlugin {
    let id = "unpin-conversation"
    let title = "Unpin Conversation"
    let keywords = ["unpin", "unstick", "remove pin"]
    let iconSystemName = "pin.slash"
    
    var isContextual: Bool { true }
    
    func execute() {
        NotificationCenter.default.post(name: Notification.Name("UnpinCurrentConversation"), object: nil)
    }
}

struct MarkUnreadCommand: CommandPlugin {
    let id = "mark-unread"
    let title = "Mark as Unread"
    let keywords = ["unread", "mark", "new", "unseen", "badge"]
    let iconSystemName = "envelope.badge"
    
    var isContextual: Bool { true }
    
    func execute() {
        NotificationCenter.default.post(name: Notification.Name("MarkCurrentUnread"), object: nil)
    }
}

struct MarkReadCommand: CommandPlugin {
    let id = "mark-read"
    let title = "Mark as Read"
    let keywords = ["read", "mark", "seen", "clear"]
    let iconSystemName = "envelope.open"
    
    var isContextual: Bool { true }
    
    func execute() {
        NotificationCenter.default.post(name: Notification.Name("MarkCurrentRead"), object: nil)
    }
}

