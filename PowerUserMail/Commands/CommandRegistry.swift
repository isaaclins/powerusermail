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
    
    /// Subtitle/description shown below the title
    var subtitle: String { get }
    
    /// Keywords for search matching (e.g., ["mark", "read", "all"])
    var keywords: [String] { get }
    
    /// SF Symbol name for the icon
    var iconSystemName: String { get }
    
    /// Icon background color
    var iconColor: CommandIconColor { get }
    
    /// Keyboard shortcut display (e.g., "⌘N")
    var shortcut: String { get }

    /// Whether to show in the command palette (still available for shortcuts if false)
    var showInPalette: Bool { get }
    
    /// Whether the command is currently available
    var isEnabled: Bool { get }
    
    /// Whether this command requires a conversation to be selected
    var isContextual: Bool { get }
    
    /// Execute the command
    func execute()
}

/// Extension with default values
extension CommandPlugin {
    var subtitle: String { "" }
    var isEnabled: Bool { true }
    var keywords: [String] { [] }
    var iconSystemName: String { "command" }
    var iconColor: CommandIconColor { .purple }
    var shortcut: String { "" }
    var isContextual: Bool { false }
    var showInPalette: Bool { true }
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
        showInPalette: Bool = true,
        action: @escaping () -> Void
    ) {
        let command = CommandAction(
            id: UUID(),
            title: title,
            keywords: keywords,
            iconSystemName: iconSystemName,
            isEnabled: isEnabled,
            showInPalette: showInPalette,
            perform: action
        )
        commands.append(command)
    }
    
    /// Get all commands for the command palette
    func getCommands(hasSelectedConversation: Bool = false) -> [CommandAction] {
        let visible = commands.filter { $0.showInPalette }
        let filtered = hasSelectedConversation ? visible : visible.filter { !$0.isContextual }
        print("\n🔍 getCommands(hasSelectedConversation: \(hasSelectedConversation)) - returning \(filtered.count) commands:")
        for cmd in filtered {
            print("  📌 \"\(cmd.title)\" keywords=\(cmd.keywords)")
        }
        return filtered
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
                subtitle: plugin.subtitle,
                keywords: plugin.keywords,
                iconSystemName: plugin.iconSystemName,
                iconColor: plugin.iconColor,
                shortcut: plugin.shortcut,
                isEnabled: plugin.isEnabled,
                isContextual: plugin.isContextual,
                showInPalette: plugin.showInPalette,
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

