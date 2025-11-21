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
                ForEach(MailProvider.allCases) { provider in
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
            }

            if !accountViewModel.accounts.isEmpty {
                VStack(spacing: 12) {
                    Text("Connected Accounts")
                        .font(.headline)

                    ForEach(accountViewModel.accounts) { account in
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text(account.emailAddress)
                        }
                        .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 20)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
