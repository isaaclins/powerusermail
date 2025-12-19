//
//  SwitchAccountCommand.swift
//  PowerUserMail
//
//  Plugin command to switch accounts.
//

import Foundation

struct SwitchAccountCommand: CommandPlugin {
    let id = "switch-account"
    let title = "Switch Account"
    let subtitle = "Change email account"
    let keywords = ["switch", "account", "settings", "preferences", "change", "profile", "user", "sa"]
    let iconSystemName = "person.crop.circle"
    let iconColor: CommandIconColor = .blue
    let shortcut = ""
    
    func execute() {
        NotificationCenter.default.post(name: Notification.Name("ShowAccountSwitcher"), object: nil)
    }
}
