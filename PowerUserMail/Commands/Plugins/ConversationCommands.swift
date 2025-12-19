//
//  ConversationCommands.swift
//  PowerUserMail
//
//  Context-aware commands for the currently selected conversation
//

import Foundation

struct ArchiveConversationCommand: CommandPlugin {
    let id = "archive-conversation"
    let title = "Archive"
    let subtitle = "Move to archive"
    let keywords = ["archive", "hide", "remove", "move", "folder"]
    let iconSystemName = "archivebox"
    let iconColor: CommandIconColor = .gray
    let shortcut = "⌘E"
    
    var isContextual: Bool { true }
    
    func execute() {
        NotificationCenter.default.post(name: Notification.Name("ArchiveCurrentConversation"), object: nil)
    }
}

struct PinConversationCommand: CommandPlugin {
    let id = "pin-conversation"
    let title = "Pin Conversation"
    let subtitle = "Keep at top of inbox"
    let keywords = ["pin", "stick", "top", "favorite", "star"]
    let iconSystemName = "pin"
    let iconColor: CommandIconColor = .red
    let shortcut = "⌘P"
    
    var isContextual: Bool { true }
    
    func execute() {
        NotificationCenter.default.post(name: Notification.Name("PinCurrentConversation"), object: nil)
    }
}

struct UnpinConversationCommand: CommandPlugin {
    let id = "unpin-conversation"
    let title = "Unpin Conversation"
    let subtitle = "Remove from pinned"
    let keywords = ["unpin", "unstick", "remove pin"]
    let iconSystemName = "pin.slash"
    let iconColor: CommandIconColor = .gray
    let shortcut = "⌘⇧P"
    
    var isContextual: Bool { true }
    
    func execute() {
        NotificationCenter.default.post(name: Notification.Name("UnpinCurrentConversation"), object: nil)
    }
}

struct MarkUnreadCommand: CommandPlugin {
    let id = "mark-unread"
    let title = "Mark as Unread"
    let subtitle = "Show unread badge"
    let keywords = ["unread", "mark", "new", "unseen", "badge"]
    let iconSystemName = "envelope.badge"
    let iconColor: CommandIconColor = .orange
    let shortcut = "⌘U"
    
    var isContextual: Bool { true }
    
    func execute() {
        NotificationCenter.default.post(name: Notification.Name("MarkCurrentUnread"), object: nil)
    }
}

struct MarkReadCommand: CommandPlugin {
    let id = "mark-read"
    let title = "Mark as Read"
    let subtitle = "Clear unread badge"
    let keywords = ["read", "mark", "seen", "clear"]
    let iconSystemName = "envelope.open"
    let iconColor: CommandIconColor = .green
    let shortcut = "⌘⇧U"
    
    var isContextual: Bool { true }
    
    func execute() {
        NotificationCenter.default.post(name: Notification.Name("MarkCurrentRead"), object: nil)
    }
}
