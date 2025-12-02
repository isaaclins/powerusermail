//
//  PowerUserMailApp.swift
//  PowerUserMail
//
//  Created by Isaac Lins on 21.11.2025.
//

import CoreData
import SwiftUI

@main
struct PowerUserMailApp: App {
    let persistenceController = PersistenceController.shared

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

                Button("New Email") {
                    NotificationCenter.default.post(
                        name: Notification.Name("OpenCompose"), object: nil)
                }
                .keyboardShortcut("n", modifiers: [.command])
                
                Button("Toggle Sidebar") {
                    NotificationCenter.default.post(
                        name: Notification.Name("ToggleSidebar"), object: nil)
                }
                .keyboardShortcut("s", modifiers: [.command])
                
                Divider()
                
                Button("Show Unread") {
                    NotificationCenter.default.post(
                        name: Notification.Name("InboxFilter1"), object: nil)
                }
                .keyboardShortcut("1", modifiers: [.command])
                
                Button("Show Archived") {
                    NotificationCenter.default.post(
                        name: Notification.Name("InboxFilter2"), object: nil)
                }
                .keyboardShortcut("2", modifiers: [.command])
                
                Button("Show Pinned") {
                    NotificationCenter.default.post(
                        name: Notification.Name("InboxFilter3"), object: nil)
                }
                .keyboardShortcut("3", modifiers: [.command])
            }
        }
    }
}
