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
    let keywords = ["new", "email", "compose", "create", "write", "draft", "message", "send", "ne", "nml"]
    let iconSystemName = "square.and.pencil"
    
    func execute() {
        NotificationCenter.default.post(name: Notification.Name("OpenCompose"), object: nil)
    }
}

