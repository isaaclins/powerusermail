//
//  MarkAllAsReadCommand.swift
//  PowerUserMail
//
//  Plugin command to mark all conversations as read.
//

import Foundation

struct MarkAllAsReadCommand: CommandPlugin {
    let id = "mark-all-as-read"
    let title = "Mark All as Read"
    let subtitle = "Clear all unread badges"
    let keywords = ["mark", "all", "read", "unread", "clear", "inbox", "notifications", "seen", "mar", "maar"]
    let iconSystemName = "checkmark"
    let iconColor: CommandIconColor = .green
    let shortcut = "⌘⇧R"
    
    func execute() {
        NotificationCenter.default.post(name: Notification.Name("MarkAllAsRead"), object: nil)
    }
}
