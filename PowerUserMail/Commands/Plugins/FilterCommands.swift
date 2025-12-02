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
    let keywords = ["show", "unread", "filter", "new", "unseen", "inbox", "su"]
    let iconSystemName = "envelope.badge"
    
    func execute() {
        NotificationCenter.default.post(name: Notification.Name("InboxFilter1"), object: nil)
    }
}

struct ShowArchivedCommand: CommandPlugin {
    let id = "show-archived"
    let title = "Show Archived"
    let keywords = ["show", "archived", "archive", "filter", "old", "done", "sa"]
    let iconSystemName = "archivebox"
    
    func execute() {
        NotificationCenter.default.post(name: Notification.Name("InboxFilter2"), object: nil)
    }
}

struct ShowPinnedCommand: CommandPlugin {
    let id = "show-pinned"
    let title = "Show Pinned"
    let keywords = ["show", "pinned", "pin", "filter", "favorite", "starred", "important", "sp"]
    let iconSystemName = "pin"
    
    func execute() {
        NotificationCenter.default.post(name: Notification.Name("InboxFilter3"), object: nil)
    }
}

struct ShowAllCommand: CommandPlugin {
    let id = "show-all"
    let title = "Show All Messages"
    let keywords = ["show", "all", "messages", "filter", "everything", "inbox", "clear", "reset", "sam"]
    let iconSystemName = "tray"
    
    func execute() {
        NotificationCenter.default.post(name: Notification.Name("InboxFilterAll"), object: nil)
    }
}

