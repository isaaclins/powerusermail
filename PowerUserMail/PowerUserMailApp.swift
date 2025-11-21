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
            }
        }
    }
}
