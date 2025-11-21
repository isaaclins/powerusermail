import SwiftUI

struct ComposeView: View {
    @ObservedObject var viewModel: ComposeViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section("Recipients") {
                    TextField("To", text: Binding(
                        get: { viewModel.draft.to.joined(separator: ", ") },
                        set: { viewModel.draft.to = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } }
                    ))
                    TextField("CC", text: Binding(
                        get: { viewModel.draft.cc.joined(separator: ", ") },
                        set: { viewModel.draft.cc = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } }
                    ))
                    TextField("BCC", text: Binding(
                        get: { viewModel.draft.bcc.joined(separator: ", ") },
                        set: { viewModel.draft.bcc = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } }
                    ))
                }

                Section("Subject") {
                    TextField("Subject", text: $viewModel.draft.subject)
                }

                Section("Body") {
                    TextEditor(text: $viewModel.draft.body)
                        .frame(minHeight: 200)
                }
            }
            .navigationTitle("New Email")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") {
                        Task { await viewModel.sendDraft(); dismiss() }
                    }
                    .disabled(viewModel.isSending)
                }
            }
            .alert("Error", isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { _ in viewModel.errorMessage = nil }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
    }
}
