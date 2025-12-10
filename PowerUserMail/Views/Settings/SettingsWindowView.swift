import SwiftUI
import AppKit

private enum SettingsCategory: String, CaseIterable, Identifiable {
    case accounts = "Accounts"
    case notifications = "Notifications"
    case appearance = "Appearance"
    case mailHandling = "Mail Handling"
    case inboxBehavior = "Inbox Behavior"
    case composer = "Composer"
    case shortcuts = "Shortcuts & Commands"
    case privacy = "Privacy & Security"
    case updates = "Updates & Diagnostics"
    case support = "Support & Feedback"
    case advanced = "Advanced"

    var id: String { rawValue }
}

struct SettingsWindowView: View {
    @EnvironmentObject var settingsStore: SettingsStore
    @EnvironmentObject var accountViewModel: AccountViewModel
    @EnvironmentObject var inboxViewModel: InboxViewModel

    @State private var selection: SettingsCategory = .accounts

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(SettingsCategory.allCases) { category in
                    Label(category.rawValue, systemImage: icon(for: category))
                        .tag(category)
                }
            }
            .listStyle(.sidebar)
            .frame(minWidth: 220)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    switch selection {
                    case .accounts:
                        AccountsSettingsPane()
                    case .notifications:
                        NotificationsSettingsPane()
                    case .appearance:
                        AppearanceSettingsPane()
                    case .mailHandling:
                        MailHandlingSettingsPane()
                    case .inboxBehavior:
                        InboxBehaviorSettingsPane()
                    case .composer:
                        ComposerSettingsPane()
                    case .shortcuts:
                        ShortcutsSettingsPane()
                    case .privacy:
                        PrivacySettingsPane()
                    case .updates:
                        UpdatesDiagnosticsPane()
                    case .support:
                        SupportFeedbackPane()
                    case .advanced:
                        AdvancedSettingsPane()
                    }
                }
                .padding(24)
                .frame(maxWidth: 720, alignment: .leading)
            }
        }
        .navigationTitle(selection.rawValue)
        .frame(minWidth: 940, minHeight: 640)
    }

    private func icon(for category: SettingsCategory) -> String {
        switch category {
        case .accounts: return "person.2.crop.square.stack"
        case .notifications: return "bell.badge"
        case .appearance: return "paintbrush"
        case .mailHandling: return "tray.full"
        case .inboxBehavior: return "arrow.triangle.2.circlepath"
        case .composer: return "square.and.pencil"
        case .shortcuts: return "command"
        case .privacy: return "lock.shield"
        case .updates: return "gearshape.2"
        case .support: return "questionmark.circle"
        case .advanced: return "wrench.and.screwdriver"
        }
    }
}

// MARK: - Panes

private struct AccountsSettingsPane: View {
    @EnvironmentObject var accountViewModel: AccountViewModel
    @EnvironmentObject var inboxViewModel: InboxViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header(title: "Accounts", subtitle: "Manage connected accounts, authentication, and data isolation.")

            ForEach(accountViewModel.accounts) { account in
                HStack(alignment: .center, spacing: 12) {
                    AsyncImage(url: account.effectiveProfilePictureURL) { phase in
                        if let image = phase.image {
                            image.resizable()
                        } else {
                            Image(systemName: "person.crop.circle")
                                .resizable()
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 32, height: 32)

                    VStack(alignment: .leading) {
                        Text(account.emailAddress)
                            .font(.headline)
                        Text(account.provider.displayName)
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }

                    Spacer()

                    Button("Re-authenticate") {
                        Task { await accountViewModel.authenticate(provider: account.provider) }
                    }

                    Button("Refresh Tokens") {
                        Task { await accountViewModel.authenticate(provider: account.provider) }
                    }

                    Button("Reset Data") {
                        if accountViewModel.selectedAccount?.id == account.id {
                            inboxViewModel.clearAllData()
                            NotificationManager.shared.resetForNewAccount()
                        }
                    }
                    .tint(.red)

                    Button(role: .destructive) {
                        accountViewModel.removeAccount(account)
                    } label: {
                        Label("Remove", systemImage: "trash")
                    }
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
            }

            HStack(spacing: 12) {
                ForEach(MailProvider.allCases.filter { $0.usesOAuth }) { provider in
                    Button {
                        Task { await accountViewModel.authenticate(provider: provider) }
                    } label: {
                        Label("Add \(provider.displayName)", systemImage: "plus.circle")
                    }
                }

                Button {
                    Task { await accountViewModel.authenticate(provider: .imap) }
                } label: {
                    Label("Custom IMAP", systemImage: "server.rack")
                }
            }
        }
    }
}

private struct NotificationsSettingsPane: View {
    @EnvironmentObject var settingsStore: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header(title: "Notifications", subtitle: "Manage alerts, sounds, badges, and quiet hours.")

            Toggle("Enable notifications", isOn: settingsStore.binding(\.notificationsEnabled))
            Toggle("Play sound", isOn: settingsStore.binding(\.notificationSoundEnabled))

            Picker("Badge", selection: settingsStore.binding(\.badgeMode)) {
                ForEach(BadgeMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            HStack(spacing: 12) {
                Button("Request permission") {
                    Task { await settingsStore.requestNotificationPermission() }
                }
                Button("Open macOS Notification Settings") {
                    settingsStore.openSystemNotificationSettings()
                }
            }

            Divider()

            Toggle("Quiet hours", isOn: settingsStore.binding(\.quietHours.enabled))

            HStack(spacing: 16) {
                Stepper("Start: \(settingsStore.payload.quietHours.startHour):00", value: settingsStore.binding(\.quietHours.startHour), in: 0...23)
                Stepper("End: \(settingsStore.payload.quietHours.endHour):00", value: settingsStore.binding(\.quietHours.endHour), in: 0...23)
            }

            Divider()

            Button("Send example notification") {
                settingsStore.sendTestNotification()
            }
            Button("Clear badge") {
                settingsStore.clearBadge()
            }
        }
    }
}

private struct AppearanceSettingsPane: View {
    @EnvironmentObject var settingsStore: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header(title: "Appearance", subtitle: "Choose theme.")

            Picker("Theme", selection: settingsStore.binding(\.theme)) {
                ForEach(AppTheme.allCases) { theme in
                    Text(theme.displayName).tag(theme)
                }
            }
            .pickerStyle(.segmented)
        }
    }
}

private struct MailHandlingSettingsPane: View {
    @EnvironmentObject var settingsStore: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header(title: "Mail Handling", subtitle: "Categories, rules, and mark-as-read delay.")

            Picker("Mark as read", selection: settingsStore.binding(\.markAsReadDelay)) {
                ForEach(MarkAsReadDelay.allCases) { delay in
                    Text(delay.displayName).tag(delay)
                }
            }

            Button("Create Category") { addCategory() }
            Button("Edit Category") { } // Placeholder for future editor
            Button("Delete Category") { deleteLastCategory() }
            Button("Reorder Categories") { } // Placeholder

            if !settingsStore.payload.categories.isEmpty {
                VStack(alignment: .leading) {
                    Text("Categories")
                        .font(.headline)
                    ForEach(settingsStore.payload.categories) { category in
                        Text("• \(category.name)")
                    }
                }
            }
        }
    }

    private func addCategory() {
        let nextPosition = settingsStore.payload.categories.count
        settingsStore.payload.categories.append(
            MailCategory(name: "New Category \(nextPosition + 1)", position: nextPosition)
        )
    }

    private func deleteLastCategory() {
        _ = settingsStore.payload.categories.popLast()
    }
}

private struct InboxBehaviorSettingsPane: View {
    @EnvironmentObject var settingsStore: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header(title: "Inbox Behavior", subtitle: "Polling, push diagnostics, and refresh behavior.")

            Picker("Polling frequency", selection: settingsStore.binding(\.pollingMode)) {
                ForEach(PollingMode.allCases) { mode in
                    Text(mode.description).tag(mode)
                }
            }
            .onChange(of: settingsStore.payload.pollingMode) { newValue in
                NotificationCenter.default.post(
                    name: Notification.Name("SettingsPollingModeChanged"),
                    object: nil,
                    userInfo: ["mode": newValue.rawValue]
                )
            }

            Toggle("Auto-refresh on wake/foreground", isOn: settingsStore.binding(\.autoRefreshOnWake))

            VStack(alignment: .leading, spacing: 4) {
                Text("Push vs Polling Status")
                    .font(.headline)
                Text("Push unavailable; using polling.")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
    }
}

private struct ComposerSettingsPane: View {
    @EnvironmentObject var settingsStore: SettingsStore
    @EnvironmentObject var accountViewModel: AccountViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header(title: "Composer", subtitle: "Defaults, signatures, smart features, and safeguards.")

            Toggle("Smart autocomplete names", isOn: settingsStore.binding(\.smartAutocomplete))
            Toggle("Grammar & spell check", isOn: settingsStore.binding(\.grammarCheck))
            Toggle("Enable Undo Send", isOn: settingsStore.binding(\.undoSendEnabled))
            Toggle("Warn on missing attachment keywords", isOn: settingsStore.binding(\.attachmentWarning))

            HStack {
                TextField("Font", text: settingsStore.binding(\.defaultFontName))
                    .frame(width: 200)
                Stepper("Size \(Int(settingsStore.payload.defaultFontSize))", value: settingsStore.binding(\.defaultFontSize), in: 10...24, step: 1)
            }

            if !accountViewModel.accounts.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Signatures (per account)")
                        .font(.headline)
                    ForEach(accountViewModel.accounts) { account in
                        TextField(
                            "\(account.emailAddress) signature",
                            text: Binding(
                                get: { settingsStore.payload.perAccountSignature[account.emailAddress] ?? "" },
                                set: { settingsStore.payload.perAccountSignature[account.emailAddress] = $0 }
                            )
                        )
                    }
                }
            }
        }
    }
}

private struct ShortcutsSettingsPane: View {
    @EnvironmentObject var settingsStore: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header(title: "Shortcuts & Commands", subtitle: "View and customize shortcuts, export/import.")

            Toggle("Enable Command Palette", isOn: settingsStore.binding(\.commandPaletteEnabled))

            if !CommandRegistry.shared.commands.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Commands")
                        .font(.headline)
                    ForEach(CommandRegistry.shared.commands) { action in
                        HStack {
                            Text(action.title)
                            Spacer()
                            TextField("Shortcut", text: Binding(
                                get: { settingsStore.payload.shortcutOverrides[action.title] ?? action.shortcut },
                                set: { settingsStore.payload.shortcutOverrides[action.title] = $0 }
                            ))
                            .frame(width: 120)
                            .onChange(of: settingsStore.payload.shortcutOverrides) { overrides in
                                CommandRegistry.shared.applyShortcutOverrides(overrides)
                            }
                        }
                    }
                }
            }

            HStack(spacing: 12) {
                Button("Export shortcuts (JSON)") {
                    exportShortcuts()
                }
                Button("Import shortcuts (JSON)") {
                    importShortcuts()
                }
            }
        }
    }

    private func exportShortcuts() {
        let overrides = settingsStore.payload.shortcutOverrides
        guard let data = try? JSONEncoder().encode(overrides) else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "shortcuts.json"
        panel.begin { result in
            if result == .OK, let url = panel.url {
                try? data.write(to: url)
            }
        }
    }

    private func importShortcuts() {
        let panel = NSOpenPanel()
        panel.allowedFileTypes = ["json"]
        panel.begin { result in
            if result == .OK, let url = panel.url,
               let data = try? Data(contentsOf: url),
               let overrides = try? JSONDecoder().decode([String: String].self, from: data) {
                settingsStore.payload.shortcutOverrides = overrides
                CommandRegistry.shared.applyShortcutOverrides(overrides)
            }
        }
    }
}

private struct PrivacySettingsPane: View {
    @EnvironmentObject var settingsStore: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header(title: "Privacy & Security", subtitle: "Cache, attachments, and remote images.")

            Stepper("Cache limit: \(settingsStore.payload.cacheSizeLimitMB) MB",
                    value: settingsStore.binding(\.cacheSizeLimitMB), in: 128...2048, step: 128)

            Picker("Attachment downloads", selection: settingsStore.binding(\.attachmentDownloadPolicy)) {
                ForEach(AttachmentDownloadPolicy.allCases) { policy in
                    Text(policy.displayName).tag(policy)
                }
            }

            Picker("Remote images", selection: settingsStore.binding(\.remoteImagesPolicy)) {
                ForEach(RemoteImagesPolicy.allCases) { policy in
                    Text(policy.displayName).tag(policy)
                }
            }

            Button("Clear cache now") {
                settingsStore.clearLocalCache()
            }
        }
    }
}

private struct UpdatesDiagnosticsPane: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header(title: "Updates & Diagnostics", subtitle: "Version info and health checks.")

            HStack {
                Text("App version")
                Spacer()
                Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")
            }

            HStack {
                Text("Build")
                Spacer()
                Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—")
            }

            Button("Check for updates") {
                // Placeholder
            }

            Button("View logs") { openLogsFolder() }
            Button("Save/export logs") { exportLogs() }
            Button("Send example notification") {
                NotificationManager.shared.checkForNewMessages(
                    conversations: [],
                    myEmail: ""
                )
            }
        }
    }

    private func openLogsFolder() {
        let fm = FileManager.default
        if let logs = fm.urls(for: .libraryDirectory, in: .userDomainMask).first?.appendingPathComponent("Logs") {
            NSWorkspace.shared.open(logs)
        }
    }

    private func exportLogs() {
        // Placeholder - logs not yet centralized
    }
}

private struct SupportFeedbackPane: View {
    private let docsURL = URL(string: "https://isaaclins.com/powerusermail/docs")

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header(title: "Support & Feedback", subtitle: "Links and feedback tools.")

            Button("Contact support") {
                if let url = URL(string: "mailto:support@powerusermail.app") {
                    NSWorkspace.shared.open(url)
                }
            }

            Button("Send feedback with logs") {
                if let url = URL(string: "mailto:feedback@powerusermail.app") {
                    NSWorkspace.shared.open(url)
                }
            }

            if let docsURL {
                Link("FAQ / Documentation", destination: docsURL)
            }
        }
    }
}

private struct AdvancedSettingsPane: View {
    @EnvironmentObject var settingsStore: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header(title: "Advanced", subtitle: "Feature flags and reset helpers.")

            Toggle("Developer mode", isOn: settingsStore.binding(\.developerMode))

            VStack(alignment: .leading, spacing: 8) {
                Text("Feature Flags")
                    .font(.headline)
                ForEach(settingsStore.payload.featureFlags) { flag in
                    Toggle(flag.key, isOn: Binding(
                        get: { flag.enabled },
                        set: { newValue in
                            if let idx = settingsStore.payload.featureFlags.firstIndex(where: { $0.id == flag.id }) {
                                settingsStore.payload.featureFlags[idx].enabled = newValue
                            }
                        }
                    ))
                    .help(flag.description)
                }
                Button("Add Feature Flag") {
                    settingsStore.payload.featureFlags.append(
                        FeatureFlag(key: "new-flag", enabled: false, description: "Development flag")
                    )
                }
            }

            Divider()

            Button("Reset app state (local data, preferences)", role: .destructive) {
                settingsStore.resetAppState()
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("TCC reset helper for notifications")
                    .font(.headline)
                Text("Run `tccutil reset Notifications com.your.bundle-id` in Terminal.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Helpers

private func header(title: String, subtitle: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
        Text(title).font(.title3).bold()
        Text(subtitle).foregroundStyle(.secondary)
    }
}

