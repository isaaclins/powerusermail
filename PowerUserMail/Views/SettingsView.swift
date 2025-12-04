import SwiftUI

struct SettingsView: View {
    @ObservedObject var accountViewModel: AccountViewModel

    var body: some View {
        VStack(spacing: 40) {
            VStack(spacing: 16) {
                Text("Welcome to PowerUserMail")
                    .font(.system(size: 32, weight: .bold))

                Text("Connect an account to get started")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 24) {
                // OAuth providers (Gmail, Outlook)
                ForEach(MailProvider.allCases.filter { $0.usesOAuth }) { provider in
                    Button {
                        Task { await accountViewModel.authenticate(provider: provider) }
                    } label: {
                        VStack(spacing: 12) {
                            Image(provider.assetName)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 64, height: 64)

                            Text("Connect \(provider.displayName)")
                                .font(.headline)
                        }
                        .padding(24)
                        .frame(width: 180, height: 160)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(16)
                        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                }

                // Custom IMAP button
                Button {
                    Task { await accountViewModel.authenticate(provider: .imap) }
                } label: {
                    VStack(spacing: 12) {
                        Image(systemName: "server.rack")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 56, height: 56)
                            .foregroundStyle(.secondary)

                        Text("Custom IMAP")
                            .font(.headline)
                    }
                    .padding(24)
                    .frame(width: 180, height: 160)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(16)
                    .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .focusable(false)
            }

            if !accountViewModel.accounts.isEmpty {
                VStack(spacing: 12) {
                    Text("Connected Accounts")
                        .font(.headline)

                    ForEach(accountViewModel.accounts) { account in
                        Button {
                            accountViewModel.selectedAccount = account
                        } label: {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)

                                if account.provider == .imap {
                                    Image(systemName: "server.rack")
                                        .foregroundStyle(.secondary)
                                }

                                Text(account.emailAddress)
                                    .font(.body)

                                Text("(\(account.provider.displayName))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                Spacer()

                                Image(systemName: "arrow.right.circle")
                                    .foregroundStyle(.blue)
                            }
                            .padding()
                            .background(Color(nsColor: .controlBackgroundColor))
                            .cornerRadius(10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .focusable(false)
                    }
                }
                .padding(.top, 20)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $accountViewModel.showIMAPConfigSheet) {
            IMAPConfigSheet(accountViewModel: accountViewModel)
        }
        .alert(
            "Error",
            isPresented: Binding(
                get: { accountViewModel.errorMessage != nil },
                set: { _ in accountViewModel.errorMessage = nil }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(accountViewModel.errorMessage ?? "")
        }
    }
}

// MARK: - IMAP Configuration Sheet

struct IMAPConfigSheet: View {
    @ObservedObject var accountViewModel: AccountViewModel
    @State private var showAdvanced = false
    @State private var isTestingConnection = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button("Cancel") {
                    accountViewModel.showIMAPConfigSheet = false
                    accountViewModel.imapConfig = IMAPConfiguration()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Text("Add IMAP Account")
                    .font(.headline)

                Spacer()

                Button("Connect") {
                    Task { await accountViewModel.authenticateIMAP() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(accountViewModel.isAuthenticating || !isFormValid)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Basic Settings
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Account Settings")
                            .font(.headline)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Email Address")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            TextField(
                                "you@example.com", text: $accountViewModel.imapConfig.username
                            )
                            .textFieldStyle(.roundedBorder)
                            .textContentType(.emailAddress)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Password")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            SecureField(
                                "Password or App Password",
                                text: $accountViewModel.imapConfig.password
                            )
                            .textFieldStyle(.roundedBorder)
                        }
                    }

                    Divider()

                    // Server Settings
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Incoming Mail Server (IMAP)")
                            .font(.headline)

                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Server")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                TextField(
                                    "imap.example.com", text: $accountViewModel.imapConfig.imapHost
                                )
                                .textFieldStyle(.roundedBorder)
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                Text("Port")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                TextField(
                                    "993", value: $accountViewModel.imapConfig.imapPort,
                                    format: .number
                                )
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 80)
                            }
                        }

                        Toggle("Use SSL/TLS", isOn: $accountViewModel.imapConfig.useSSL)
                    }

                    Divider()

                    // SMTP Settings (collapsible)
                    DisclosureGroup("Outgoing Mail Server (SMTP)", isExpanded: $showAdvanced) {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Server")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    TextField(
                                        "smtp.example.com",
                                        text: $accountViewModel.imapConfig.smtpHost
                                    )
                                    .textFieldStyle(.roundedBorder)
                                }

                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Port")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    TextField(
                                        "587", value: $accountViewModel.imapConfig.smtpPort,
                                        format: .number
                                    )
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 80)
                                }
                            }

                            Toggle("Use STARTTLS", isOn: $accountViewModel.imapConfig.useTLS)

                            Text("Leave SMTP settings empty to auto-detect from IMAP server.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 8)
                    }
                    .font(.headline)

                    // Common presets
                    Divider()

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Quick Setup")
                            .font(.headline)

                        Text("Select a preset to auto-fill server settings:")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 12) {
                            PresetButton(title: "Fastmail") {
                                accountViewModel.imapConfig.imapHost = "imap.fastmail.com"
                                accountViewModel.imapConfig.imapPort = 993
                                accountViewModel.imapConfig.smtpHost = "smtp.fastmail.com"
                                accountViewModel.imapConfig.smtpPort = 587
                                accountViewModel.imapConfig.useSSL = true
                                accountViewModel.imapConfig.useTLS = true
                            }

                            PresetButton(title: "ProtonMail Bridge") {
                                accountViewModel.imapConfig.imapHost = "127.0.0.1"
                                accountViewModel.imapConfig.imapPort = 1143
                                accountViewModel.imapConfig.smtpHost = "127.0.0.1"
                                accountViewModel.imapConfig.smtpPort = 1025
                                accountViewModel.imapConfig.useSSL = false
                                accountViewModel.imapConfig.useTLS = false
                            }

                            PresetButton(title: "iCloud") {
                                accountViewModel.imapConfig.imapHost = "imap.mail.me.com"
                                accountViewModel.imapConfig.imapPort = 993
                                accountViewModel.imapConfig.smtpHost = "smtp.mail.me.com"
                                accountViewModel.imapConfig.smtpPort = 587
                                accountViewModel.imapConfig.useSSL = true
                                accountViewModel.imapConfig.useTLS = true
                            }

                            PresetButton(title: "Yahoo") {
                                accountViewModel.imapConfig.imapHost = "imap.mail.yahoo.com"
                                accountViewModel.imapConfig.imapPort = 993
                                accountViewModel.imapConfig.smtpHost = "smtp.mail.yahoo.com"
                                accountViewModel.imapConfig.smtpPort = 587
                                accountViewModel.imapConfig.useSSL = true
                                accountViewModel.imapConfig.useTLS = true
                            }
                        }
                    }

                    // Help text
                    VStack(alignment: .leading, spacing: 8) {
                        Divider()

                        Text("Tips")
                            .font(.headline)

                        VStack(alignment: .leading, spacing: 4) {
                            Label(
                                "For Gmail, use an App Password instead of your regular password",
                                systemImage: "key.fill")
                            Label(
                                "Some providers require enabling IMAP access in settings",
                                systemImage: "gear")
                            Label(
                                "Check with your email provider for correct server settings",
                                systemImage: "questionmark.circle")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
                .padding()
            }

            // Loading indicator
            if accountViewModel.isAuthenticating {
                VStack {
                    Divider()
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Connecting...")
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                }
            }
        }
        .frame(width: 500, height: 600)
    }

    private var isFormValid: Bool {
        !accountViewModel.imapConfig.username.isEmpty
            && !accountViewModel.imapConfig.password.isEmpty
            && !accountViewModel.imapConfig.imapHost.isEmpty
            && accountViewModel.imapConfig.imapPort > 0
    }
}

struct PresetButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.accentColor.opacity(0.1))
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}
