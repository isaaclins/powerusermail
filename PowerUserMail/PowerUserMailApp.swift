//
//  PowerUserMailApp.swift
//  PowerUserMail
//
//  Created by Isaac Lins on 21.11.2025.
//

import CoreData
import SwiftUI
import UserNotifications

// App Delegate for handling notifications
class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Set notification delegate
        UNUserNotificationCenter.current().delegate = self
        
        // Initialize notification manager
        Task { @MainActor in
            await NotificationManager.shared.requestAuthorization()
        }
    }
    
    // Handle notification when app is in foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show notification even when app is active
        completionHandler([.banner, .sound, .badge])
    }
    
    // Handle notification tap
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        
        if let from = userInfo["from"] as? String {
            // Post notification to open this conversation
            NotificationCenter.default.post(
                name: Notification.Name("OpenConversation"),
                object: nil,
                userInfo: ["from": from]
            )
        }
        
        completionHandler()
    }
}

@main
struct PowerUserMailApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @ObservedObject private var commandRegistry = CommandRegistry.shared
    let persistenceController = PersistenceController.shared

    init() {
        // Ensure plugins (and their shortcuts) are loaded before building the menu
        CommandLoader.loadAll()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
        .commands {
            CommandMenu("Actions") {
                Button("Command Palette") {
                    NotificationCenter.default.post(
                        name: Notification.Name("ToggleCommandPalette"), object: nil)
                }
                .keyboardShortcut("k", modifiers: [.command])

                Divider()

                ForEach(shortcutActions) { action in
                    if let shortcut = parseShortcut(action.shortcut) {
                        Button(action.title) { action.perform() }
                            .keyboardShortcut(shortcut.key, modifiers: shortcut.modifiers)
                    }
                }
            }
        }
    }

    /// Build a list of actions that have valid shortcuts defined in plugins/registry.
    private var shortcutActions: [CommandAction] {
        commandRegistry.commands.filter { !$0.shortcut.isEmpty }
    }

    /// Parse a human-readable shortcut string (e.g., "⌘⇧R") into SwiftUI key equivalents.
    private func parseShortcut(_ string: String) -> (key: KeyEquivalent, modifiers: EventModifiers)? {
        var modifiers: EventModifiers = []
        var keyChar: Character?

        for ch in string {
            switch ch {
            case "⌘": modifiers.insert(.command)
            case "⇧": modifiers.insert(.shift)
            case "⌥": modifiers.insert(.option)
            case "⌃": modifiers.insert(.control)
            default:
                keyChar = ch
            }
        }

        guard let keyChar else { return nil }

        let key: KeyEquivalent
        switch keyChar {
        case "\\":
            key = KeyEquivalent("\\")
        default:
            key = KeyEquivalent(String(keyChar).lowercased().first ?? keyChar)
        }

        return (key: key, modifiers: modifiers)
    }
}
