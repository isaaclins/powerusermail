//
//  CommandRegistry.swift
//  PowerUserMail
//
//  A modular command system that allows plugins to register commands.
//  To add a new command, create a file in the Commands/Plugins folder
//  that conforms to CommandPlugin and call CommandRegistry.shared.register()
//

import Foundation
import Combine

/// Protocol for command plugins - implement this to add new commands
protocol CommandPlugin {
    /// Unique identifier for the plugin
    var id: String { get }
    
    /// Display title in the command palette
    var title: String { get }
    
    /// Keywords for search matching (e.g., ["mark", "read", "all"])
    var keywords: [String] { get }
    
    /// SF Symbol name for the icon
    var iconSystemName: String { get }
    
    /// Whether the command is currently available
    var isEnabled: Bool { get }
    
    /// Execute the command
    func execute()
}

/// Extension with default values
extension CommandPlugin {
    var isEnabled: Bool { true }
    var keywords: [String] { [] }
    var iconSystemName: String { "command" }
}

/// Central registry for all commands
@MainActor
final class CommandRegistry: ObservableObject {
    static let shared = CommandRegistry()
    
    @Published private(set) var commands: [CommandAction] = []
    private var plugins: [String: CommandPlugin] = [:]
    
    private init() {
        // Register built-in commands on init
        registerBuiltInCommands()
    }
    
    /// Register a command plugin
    func register(_ plugin: CommandPlugin) {
        plugins[plugin.id] = plugin
        rebuildCommands()
    }
    
    /// Register multiple plugins at once
    func register(_ plugins: [CommandPlugin]) {
        print("\n[CommandRegistry] Registering \(plugins.count) plugins...")
        for plugin in plugins {
            self.plugins[plugin.id] = plugin
            print("  - \(plugin.id): \"\(plugin.title)\" keywords=\(plugin.keywords)")
        }
        rebuildCommands()
        print("[CommandRegistry] Total commands: \(commands.count)\n")
    }
    
    /// Unregister a plugin by ID
    func unregister(id: String) {
        plugins.removeValue(forKey: id)
        rebuildCommands()
    }
    
    /// Register a simple command action (for backwards compatibility)
    func registerAction(
        id: String,
        title: String,
        keywords: [String] = [],
        iconSystemName: String = "command",
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) {
        let command = CommandAction(
            id: UUID(),
            title: title,
            keywords: keywords,
            iconSystemName: iconSystemName,
            isEnabled: isEnabled,
            perform: action
        )
        commands.append(command)
    }
    
    /// Get all commands for the command palette
    func getCommands() -> [CommandAction] {
        print("\n🔍 getCommands() called - returning \(commands.count) commands:")
        for cmd in commands {
            print("  📌 \"\(cmd.title)\" keywords=\(cmd.keywords)")
        }
        return commands
    }
    
    /// Filter commands by search text
    func filterCommands(searchText: String) -> [CommandAction] {
        if searchText.isEmpty { return commands }
        
        let search = searchText.lowercased()
        return commands.filter { action in
            // Check title
            if action.title.lowercased().contains(search) {
                return true
            }
            // Check keywords
            for keyword in action.keywords {
                if keyword.lowercased().contains(search) {
                    return true
                }
            }
            return false
        }
    }
    
    /// Rebuild commands array from plugins
    private func rebuildCommands() {
        var newCommands: [CommandAction] = []
        
        for plugin in plugins.values {
            let action = CommandAction(
                id: UUID(),
                title: plugin.title,
                keywords: plugin.keywords,
                iconSystemName: plugin.iconSystemName,
                isEnabled: plugin.isEnabled,
                perform: plugin.execute
            )
            newCommands.append(action)
        }
        
        // Sort by title for consistent ordering
        newCommands.sort { $0.title < $1.title }
        commands = newCommands
    }
    
    /// Register built-in commands
    private func registerBuiltInCommands() {
        // These will be overwritten by ContentView's dynamic commands
        // This is just for standalone testing
    }
    
    /// Refresh all plugin states (call when context changes)
    func refresh() {
        rebuildCommands()
    }
}

