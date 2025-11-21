//
//  ContentView.swift
//  PowerUserMail
//
//  Created by Isaac Lins on 21.11.2025.
//

import CoreData
import SwiftUI

struct ContentView: View {
    @StateObject private var accountViewModel = AccountViewModel()
    @State private var selectedThread: EmailThread?
    @State private var isShowingCompose = false
    @State private var isShowingCommandPalette = false
    @State private var commandSearch = ""
    @State private var commandActions: [CommandAction] = []

    var body: some View {
        Group {
            if let account = accountViewModel.selectedAccount,
                let service = accountViewModel.service(for: account.provider)
            {
                mainSplitView(service: service)
            } else {
                onboardingView
            }
        }
        .overlay(alignment: .center) {
            if isShowingCommandPalette {
                CommandPaletteView(
                    isPresented: $isShowingCommandPalette,
                    searchText: $commandSearch,
                    actions: commandActions,
                    onSelect: { action in
                        commandSearch = ""
                        action.perform()
                    }
                )
                .frame(maxWidth: 500)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .sheet(isPresented: $isShowingCompose) {
            if let account = accountViewModel.selectedAccount,
                let service = accountViewModel.service(for: account.provider)
            {
                ComposeView(viewModel: ComposeViewModel(service: service))
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(for: Notification.Name("ToggleCommandPalette"))
        ) { _ in
            toggleCommandPalette()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("OpenCompose"))) {
            _ in
            openCompose()
        }
        .onAppear(perform: configureCommands)
    }

    private var onboardingView: some View {
        SettingsView(accountViewModel: accountViewModel)
    }

    private func mainSplitView(service: MailService) -> some View {
        NavigationSplitView {
            InboxView(service: service, selectedThread: $selectedThread)
                .navigationTitle("Inbox")
                .toolbar {
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button(action: openCompose) {
                            Label("New Email", systemImage: "square.and.pencil")
                        }
                        Button(action: toggleCommandPalette) {
                            Label("Command Palette", systemImage: "command")
                        }
                    }
                }
        } detail: {
            if let thread = selectedThread,
                let email = thread.lastMessage
            {
                EmailDetailView(email: email)
            } else {
                ContentUnavailableView("No Message Selected", systemImage: "tray")
            }
        }
    }

    private func openCompose() {
        isShowingCompose = true
    }

    private func toggleCommandPalette() {
        if commandActions.isEmpty { configureCommands() }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            isShowingCommandPalette.toggle()
        }
    }

    private func configureCommands() {
        commandActions = [
            CommandAction(
                title: "New Email", keywords: ["compose", "create"],
                iconSystemName: "square.and.pencil"
            ) {
                openCompose()
            },
            CommandAction(
                title: "Show Accounts", keywords: ["settings", "accounts"],
                iconSystemName: "person.crop.circle"
            ) {
                accountViewModel.selectedAccount = nil
            },
        ]
    }
}

#Preview {
    ContentView().environment(
        \.managedObjectContext, PersistenceController.preview.container.viewContext)
}
