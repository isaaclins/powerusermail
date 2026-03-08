import SwiftUI

struct ComposeView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var accountViewModel: AccountViewModel
    @ObservedObject var viewModel: ComposeViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showCcBcc = false
    @State private var didApplySignature = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Text("New Message")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                Spacer()

                Button(action: {
                    Task {
                        await viewModel.sendDraft()
                        dismiss()
                    }
                }) {
                    HStack(spacing: 4) {
                        Text("Send")
                        Image(systemName: "paperplane")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isSending)
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            ScrollView {
                VStack(spacing: 0) {
                    HStack {
                        Text("To:")
                            .foregroundStyle(.secondary)
                            .frame(width: 50, alignment: .trailing)
                        TextField(
                            "",
                            text: Binding(
                                get: { viewModel.draft.to.joined(separator: ", ") },
                                set: {
                                    viewModel.draft.to = $0.split(separator: ",").map {
                                        $0.trimmingCharacters(in: .whitespaces)
                                    }
                                }
                            )
                        )
                        .textFieldStyle(.roundedBorder)

                        Button(action: { withAnimation { showCcBcc.toggle() } }) {
                            Text(showCcBcc ? "Hide Cc/Bcc" : "Cc/Bcc")
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding()

                    if showCcBcc {
                        Divider()
                        HStack {
                            Text("Cc:")
                                .foregroundStyle(.secondary)
                                .frame(width: 50, alignment: .trailing)
                            TextField(
                                "",
                                text: Binding(
                                    get: { viewModel.draft.cc.joined(separator: ", ") },
                                    set: {
                                        viewModel.draft.cc = $0.split(separator: ",").map {
                                            $0.trimmingCharacters(in: .whitespaces)
                                        }
                                    }
                                )
                            )
                            .textFieldStyle(.roundedBorder)
                        }
                        .padding()

                        Divider()

                        HStack {
                            Text("Bcc:")
                                .foregroundStyle(.secondary)
                                .frame(width: 50, alignment: .trailing)
                            TextField(
                                "",
                                text: Binding(
                                    get: { viewModel.draft.bcc.joined(separator: ", ") },
                                    set: {
                                        viewModel.draft.bcc = $0.split(separator: ",").map {
                                            $0.trimmingCharacters(in: .whitespaces)
                                        }
                                    }
                                )
                            )
                            .textFieldStyle(.roundedBorder)
                        }
                        .padding()
                    }

                    Divider()

                    // Subject
                    HStack {
                        Text("Subject:")
                            .foregroundStyle(.secondary)
                            .frame(width: 50, alignment: .trailing)
                        TextField("", text: $viewModel.draft.subject)
                            .textFieldStyle(.roundedBorder)
                            .font(.headline)
                    }
                    .padding()

                    Divider()

                    TextEditor(text: $viewModel.draft.body)
                        .font(
                            .custom(
                                settingsStore.payload.defaultFontName,
                                size: settingsStore.payload.defaultFontSize,
                                relativeTo: .body
                            )
                        )
                        .padding()
                        .frame(minHeight: 300)
                }
            }
            .background(Color(nsColor: .textBackgroundColor))
        }
        .frame(minWidth: 600, minHeight: 500)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            applySignatureIfNeeded()
        }
        .alert(
            "Error",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { _ in viewModel.errorMessage = nil }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    private func applySignatureIfNeeded() {
        guard !didApplySignature, viewModel.draft.body.isEmpty else { return }
        guard let email = accountViewModel.selectedAccount?.emailAddress else { return }
        guard let signature = settingsStore.payload.perAccountSignature[email], !signature.isEmpty else {
            return
        }

        viewModel.draft.body = "\n\n\(signature)"
        didApplySignature = true
    }
}
