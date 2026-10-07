//
//  test.MarkAllAsUnread.swift
//  PowerUserMail
//
//  Command to mark all conversations as unread.
//

import Foundation

struct TestMarkAllAsUnreadCommand: CommandPlugin {
    let id = "test-mark-all-unread"
    let title = "Mark All as Unread"
    let subtitle = "Set all conversations to unread"
    let keywords = ["mark", "unread", "all"]
    let iconSystemName = "envelope.badge"
    let iconColor: CommandIconColor = .orange
    let shortcut = ""
    let showInPalette = true

    func execute() {
        NotificationCenter.default.post(
            name: Notification.Name("MarkAllAsUnread"),
            object: nil)
    }
}




