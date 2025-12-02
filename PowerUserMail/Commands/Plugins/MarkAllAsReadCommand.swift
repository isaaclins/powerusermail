//
//  MarkAllAsReadCommand.swift
//  PowerUserMail
//
//  Plugin command to mark all conversations as read.
//  This is an example of how to create modular commands.
//

import Foundation

struct MarkAllAsReadCommand: CommandPlugin {
    let id = "mark-all-as-read"
    let title = "Mark All as Read"
    let keywords = ["mark", "all", "read", "unread", "clear", "inbox", "notifications", "seen", "mar", "maar"]
    let iconSystemName = "envelope.open"
    
    func execute() {
        NotificationCenter.default.post(name: Notification.Name("MarkAllAsRead"), object: nil)
    }
}

// Auto-register when the app loads
extension MarkAllAsReadCommand {
    static func register() {
        Task { @MainActor in
            CommandRegistry.shared.register(MarkAllAsReadCommand())
        }
    }
}

