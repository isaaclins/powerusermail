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
                
                Button("Show All") {
                    NotificationCenter.default.post(
                        name: Notification.Name("InboxFilter2"), object: nil)
                }
                .keyboardShortcut("2", modifiers: [.command])
                
                Button("Show Archived") {
                    NotificationCenter.default.post(
                        name: Notification.Name("InboxFilter3"), object: nil)
                }
                .keyboardShortcut("3", modifiers: [.command])
                
                Button("Show Pinned") {
                    NotificationCenter.default.post(
                        name: Notification.Name("InboxFilter4"), object: nil)
                }
                .keyboardShortcut("4", modifiers: [.command])
            }
        }
    }
}
