//
//  ToggleSidebarCommand.swift
//  PowerUserMail
//
//  Plugin command to toggle the sidebar.
//

import Foundation

struct ToggleSidebarCommand: CommandPlugin {
    let id = "toggle-sidebar"
    let title = "Toggle Sidebar"
    let keywords = ["toggle", "sidebar", "panel", "hide", "show", "collapse", "expand", "menu", "navigation", "ts"]
    let iconSystemName = "sidebar.left"
    
    func execute() {
        NotificationCenter.default.post(name: Notification.Name("ToggleSidebar"), object: nil)
    }
}

