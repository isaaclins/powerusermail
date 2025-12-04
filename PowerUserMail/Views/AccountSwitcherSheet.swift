//
//  AccountSwitcherSheet.swift
//  PowerUserMail
//
//  Created by Isaac Lins on 02.12.2025.
//

import SwiftUI

struct AccountSwitcherSheet: View {
    @ObservedObject var accountViewModel: AccountViewModel
    @Binding var isPresented: Bool
    
    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 8) {
                Text("Switch Account")
                    .font(.title.bold())
                
                Text("Select an account or connect a new one")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 20)
            
            // Connected accounts list
            if !accountViewModel.accounts.isEmpty {
                VStack(spacing: 8) {
                    Text("Connected Accounts")
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    VStack(spacing: 0) {
                        ForEach(accountViewModel.accounts) { account in
                            HStack(spacing: 12) {
                                // Main account button
                                Button {
                                    accountViewModel.selectedAccount = account
                                    isPresented = false
                                } label: {
                                    HStack(spacing: 12) {
                                        // Provider icon
                                        Group {
                                            switch account.provider {
                                            case .gmail:
                                                Image("GmailLogo")
                                                    .resizable()
                                                    .scaledToFit()
                                            case .outlook:
                                                Image("OutlookLogo")
                                                    .resizable()
                                                    .scaledToFit()
                                            case .imap:
                                                Image(systemName: "server.rack")
                                                    .resizable()
                                                    .scaledToFit()
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                        .frame(width: 24, height: 24)
                                        
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(account.displayName.isEmpty ? account.emailAddress : account.displayName)
                                                .font(.system(size: 14, weight: .medium))
                                                .foregroundStyle(.primary)
                                            
                                            if !account.displayName.isEmpty {
                                                Text(account.emailAddress)
                                                    .font(.system(size: 12))
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                        
                                        Spacer()
                                        
                                        // Selected indicator
                                        if accountViewModel.selectedAccount?.id == account.id {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(.green)
                                                .font(.system(size: 18))
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                                .focusable(false)
                                
                                // Remove account button
                                Button {
                                    accountViewModel.removeAccount(account)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                        .font(.system(size: 16))
                                }
                                .buttonStyle(.plain)
                                .focusable(false)
                                .help("Remove account")
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(accountViewModel.selectedAccount?.id == account.id 
                                          ? Color.accentColor.opacity(0.1) 
                                          : Color.clear)
                            )
                            
                            if account.id != accountViewModel.accounts.last?.id {
                                Divider()
                                    .padding(.leading, 52)
                            }
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.ultraThinMaterial)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(.quaternary, lineWidth: 1)
                    )
                }
            }
            
            // Add new account section
            VStack(spacing: 8) {
                Text("Add Account")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                HStack(spacing: 16) {
                    // Gmail button
                    Button {
                        Task {
                            await accountViewModel.authenticate(provider: .gmail)
                            if accountViewModel.selectedAccount != nil {
                                isPresented = false
                            }
                        }
                    } label: {
                        VStack(spacing: 12) {
                            Image("GmailLogo")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 40, height: 40)
                            
                            Text("Gmail")
                                .font(.system(size: 13, weight: .medium))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(.ultraThinMaterial)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(.quaternary, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(accountViewModel.isAuthenticating)
                    
                    // Outlook button
                    Button {
                        Task {
                            await accountViewModel.authenticate(provider: .outlook)
                            if accountViewModel.selectedAccount != nil {
                                isPresented = false
                            }
                        }
                    } label: {
                        VStack(spacing: 12) {
                            Image("OutlookLogo")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 40, height: 40)
                            
                            Text("Outlook")
                                .font(.system(size: 13, weight: .medium))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(.ultraThinMaterial)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(.quaternary, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(accountViewModel.isAuthenticating)
                    
                    // Custom IMAP button
                    Button {
                        Task {
                            await accountViewModel.authenticate(provider: .imap)
                        }
                    } label: {
                        VStack(spacing: 12) {
                            Image(systemName: "server.rack")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 36, height: 36)
                                .foregroundStyle(.secondary)
                            
                            Text("IMAP")
                                .font(.system(size: 13, weight: .medium))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(.ultraThinMaterial)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(.quaternary, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(accountViewModel.isAuthenticating)
                }
            }
            
            if accountViewModel.isAuthenticating {
                ProgressView("Connecting...")
                    .padding()
            }
            
            if let error = accountViewModel.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
            
            Spacer()
            
            // Close button
            Button("Done") {
                isPresented = false
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.bottom, 20)
        }
        .padding(.horizontal, 24)
        .frame(width: 420, height: 580)
        .sheet(isPresented: $accountViewModel.showIMAPConfigSheet) {
            IMAPConfigSheet(accountViewModel: accountViewModel)
        }
    }
}

#Preview {
    AccountSwitcherSheet(
        accountViewModel: AccountViewModel(),
        isPresented: .constant(true)
    )
}

