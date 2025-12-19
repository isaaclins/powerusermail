//
//  NewEmailCommand.swift
//  PowerUserMail
//
//  Plugin command to compose a new email.
//

import Foundation

struct NewEmailCommand: CommandPlugin {
    let id = "new-email"
    let title = "New Email"
    let subtitle = "Compose a new message"
    let keywords = ["new", "email", "compose", "create", "write", "draft", "message", "send", "ne", "nml", "msg"]
    let iconSystemName = "envelope"
    let iconColor: CommandIconColor = .blue
    let shortcut = "⌘N"
    
    func execute() {
        NotificationCenter.default.post(name: Notification.Name("OpenCompose"), object: nil)
    }
}
