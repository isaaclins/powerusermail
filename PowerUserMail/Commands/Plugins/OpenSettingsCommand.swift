//
//  OpenSettingsCommand.swift
//  PowerUserMail
//
//  Command to open the app Settings window.
//

import AppKit
import Foundation

struct OpenSettingsCommand: CommandPlugin {
    let id = "open-settings"
    let title = "Settings"
    let subtitle = "Open preferences"
    let keywords = ["__settings", "settings", "preferences", "prefs", "config", "options"]
    let iconSystemName = "gearshape"
    let iconColor: CommandIconColor = .gray
    let shortcut = ""

    func execute() {
        NotificationCenter.default.post(name: Notification.Name("OpenSettings"), object: nil)
    }
}
