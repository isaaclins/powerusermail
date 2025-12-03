//
//  CommandLoader.swift
//  PowerUserMail
//
//  Loads and registers all command plugins.
//  To add a new command:
//  1. Create a new file in this Plugins folder
//  2. Make your struct conform to CommandPlugin
//  3. Add it to the `allPlugins` array below
//

import Foundation
import AppKit

/// All available command plugins
/// Add your custom plugins here to register them
@MainActor
struct CommandLoader {
    
    /// All plugins to be loaded
    /// Simply add your CommandPlugin conforming struct here
    static let allPlugins: [CommandPlugin] = [
        // Email actions
        NewEmailCommand(),
        MarkAllAsReadCommand(),
        
        // Account
        SwitchAccountCommand(),
        
        // Navigation
        ToggleSidebarCommand(),
        
        // Filters
        ShowAllCommand(),
        ShowUnreadCommand(),
        ShowArchivedCommand(),
        ShowPinnedCommand(),
        
        // Conversation actions (contextual - only shown when chat is selected)
        ArchiveConversationCommand(),
        PinConversationCommand(),
        UnpinConversationCommand(),
        MarkUnreadCommand(),
        MarkReadCommand(),
        
        // System
        CheckForUpdatesCommand(),
        QuitAppCommand(),
    ]
    
    /// Load all plugins into the registry
    static func loadAll() {
        print("🚀 CommandLoader.loadAll() called with \(allPlugins.count) plugins")
        CommandRegistry.shared.register(allPlugins)
    }
}

// MARK: - System Commands

struct QuitAppCommand: CommandPlugin {
    let id = "quit-app"
    let title = "Quit PowerUserMail"
    let subtitle = "Exit the application"
    let keywords = ["quit", "exit", "close", "shutdown", "bye", "powerusermail", "q"]
    let iconSystemName = "power"
    let iconColor: CommandIconColor = .red
    let shortcut = "⌘Q"
    
    func execute() {
        NSApplication.shared.terminate(nil)
    }
}

