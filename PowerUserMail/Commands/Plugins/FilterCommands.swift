//
//  FilterCommands.swift
//  PowerUserMail
//
//  Plugin commands for inbox filters.
//

import Foundation

struct ShowUnreadCommand: CommandPlugin {
    let id = "show-unread"
    let title = "Show Unread"
    let subtitle = "Filter to unread messages"
    let keywords = ["show", "unread", "filter", "new", "unseen", "inbox", "su"]
    let iconSystemName = "envelope.badge"
    let iconColor: CommandIconColor = .purple
    let shortcut = "⌘1"
    
    func execute() {
        NotificationCenter.default.post(name: Notification.Name("InboxFilter1"), object: nil)
    }
}

struct ShowAllCommand: CommandPlugin {
    let id = "show-all"
    let title = "Show All Messages"
    let subtitle = "Show entire inbox"
    let keywords = ["show", "all", "messages", "filter", "everything", "inbox", "clear", "reset", "sam"]
    let iconSystemName = "tray"
    let iconColor: CommandIconColor = .blue
    let shortcut = "⌘2"
    
    func execute() {
        NotificationCenter.default.post(name: Notification.Name("InboxFilter2"), object: nil)
    }
}

struct ShowArchivedCommand: CommandPlugin {
    let id = "show-archived"
    let title = "Show Archived"
    let subtitle = "View archived messages"
    let keywords = ["show", "archived", "archive", "filter", "old", "done", "sa"]
    let iconSystemName = "archivebox"
    let iconColor: CommandIconColor = .gray
    let shortcut = "⌘3"
    
    func execute() {
        NotificationCenter.default.post(name: Notification.Name("InboxFilter3"), object: nil)
    }
}

struct ShowPinnedCommand: CommandPlugin {
    let id = "show-pinned"
    let title = "Show Pinned"
    let subtitle = "View pinned conversations"
    let keywords = ["show", "pinned", "pin", "filter", "favorite", "starred", "important", "sp"]
    let iconSystemName = "pin.fill"
    let iconColor: CommandIconColor = .orange
    let shortcut = "⌘4"
    
    func execute() {
        NotificationCenter.default.post(name: Notification.Name("InboxFilter4"), object: nil)
    }
}
