//
//  PowerUserMailApp.swift
//  PowerUserMail
//
//  Created by Isaac Lins on 21.11.2025.
//

import CoreData
import SwiftUI
import UserNotifications

#if os(macOS)
    import AppKit
#endif

// App Delegate for handling notifications
class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Set notification delegate
        UNUserNotificationCenter.current().delegate = self

        // Clear cache if needed for migration
        migrateDataStoreIfNeeded()

        // Initialize notification manager
        Task { @MainActor in
            await NotificationManager.shared.refreshAuthorizationStatus()

            if NotificationManager.shared.authorizationStatus == .notDetermined {
                await NotificationManager.shared.requestAuthorization()
            }
        }
    }

    private func migrateDataStoreIfNeeded() {
        let defaults = UserDefaults.standard
        let migrationKey = "CoreDataMigrationVersion"
        let currentVersion = 2  // Increment when schema changes

        let savedVersion = defaults.integer(forKey: migrationKey)

        if savedVersion < currentVersion {
            print("🔄 Migrating Core Data store from version \(savedVersion) to \(currentVersion)")

            // Clear the old store
            let coordinator = PersistenceController.shared.container.persistentStoreCoordinator
            if let storeURL = coordinator.persistentStores.first?.url {
                do {
                    try coordinator.destroyPersistentStore(
                        at: storeURL, ofType: NSSQLiteStoreType, options: nil)
                    try coordinator.addPersistentStore(
                        ofType: NSSQLiteStoreType, configurationName: nil, at: storeURL,
                        options: nil)
                    print("✅ Core Data migration complete")
                } catch {
                    print("❌ Migration failed: \(error)")
                }
            }

            defaults.set(currentVersion, forKey: migrationKey)
        }
    }

    // Handle notification when app is in foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler:
            @escaping (UNNotificationPresentationOptions) -> Void
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

#if os(macOS)
    @MainActor
    final class SettingsWindowController {
        static let shared = SettingsWindowController()
        private var window: NSWindow?

        func show(
            settingsStore: SettingsStore,
            accountViewModel: AccountViewModel,
            inboxViewModel: InboxViewModel
        ) {
            if window == nil {
                let rootView = SettingsWindowView()
                    .environmentObject(settingsStore)
                    .environmentObject(accountViewModel)
                    .environmentObject(inboxViewModel)

                let hostingController = NSHostingController(rootView: rootView)
                let window = NSWindow(contentViewController: hostingController)
                window.title = "Settings"
                window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
                window.setContentSize(NSSize(width: 900, height: 600))
                window.center()
                self.window = window
            }

            NSApp.activate(ignoringOtherApps: true)
            window?.makeKeyAndOrderFront(nil)
        }
    }
#endif

@main
struct PowerUserMailApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @ObservedObject private var commandRegistry = CommandRegistry.shared
    @StateObject private var accountViewModel = AccountViewModel()
    @StateObject private var inboxViewModel = InboxViewModel()
    @StateObject private var settingsStore = SettingsStore()
    let persistenceController = PersistenceController.shared

    init() {
        // Ensure plugins (and their shortcuts) are loaded before building the menu
        CommandLoader.loadAll()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environmentObject(accountViewModel)
                .environmentObject(inboxViewModel)
                .environmentObject(settingsStore)
                .onReceive(
                    NotificationCenter.default.publisher(for: Notification.Name("OpenSettings"))
                ) { _ in
                    #if os(macOS)
                        let opened = NSApp.sendAction(
                            Selector(("showSettingsWindow:")), to: nil, from: nil)
                        if !opened {
                            SettingsWindowController.shared.show(
                                settingsStore: settingsStore,
                                accountViewModel: accountViewModel,
                                inboxViewModel: inboxViewModel
                            )
                        }
                    #endif
                }
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

        Settings {
            SettingsWindowView()
                .environmentObject(settingsStore)
                .environmentObject(accountViewModel)
                .environmentObject(inboxViewModel)
        }
    }

    /// Build a list of actions that have valid shortcuts defined in plugins/registry.
    private var shortcutActions: [CommandAction] {
        commandRegistry.commands.filter { !$0.shortcut.isEmpty }
    }

    /// Parse a human-readable shortcut string (e.g., "⌘⇧R") into SwiftUI key equivalents.
    private func parseShortcut(_ string: String) -> (key: KeyEquivalent, modifiers: EventModifiers)?
    {
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
