import SwiftUI

struct ComposeView: View {
    @ObservedObject var viewModel: ComposeViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showCcBcc = false

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
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
                    Task { await viewModel.sendDraft(); dismiss() }
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
            .background(.ultraThinMaterial)
            
            Divider()
            
            // Fields
            ScrollView {
                VStack(spacing: 0) {
                    // To
                    HStack {
                        Text("To:")
                            .foregroundStyle(.secondary)
                            .frame(width: 50, alignment: .trailing)
                        TextField("", text: Binding(
                            get: { viewModel.draft.to.joined(separator: ", ") },
                            set: { viewModel.draft.to = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } }
                        ))
                        .textFieldStyle(.plain)
                        
                        Button(action: { withAnimation { showCcBcc.toggle() } }) {
                            Text(showCcBcc ? "Hide Cc/Bcc" : "Cc/Bcc")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding()
                    
                    if showCcBcc {
                        Divider()
                        HStack {
                            Text("Cc:")
                                .foregroundStyle(.secondary)
                                .frame(width: 50, alignment: .trailing)
                            TextField("", text: Binding(
                                get: { viewModel.draft.cc.joined(separator: ", ") },
                                set: { viewModel.draft.cc = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } }
                            ))
                            .textFieldStyle(.plain)
                        }
                        .padding()
                        
                        Divider()
                        
                        HStack {
                            Text("Bcc:")
                                .foregroundStyle(.secondary)
                                .frame(width: 50, alignment: .trailing)
                            TextField("", text: Binding(
                                get: { viewModel.draft.bcc.joined(separator: ", ") },
                                set: { viewModel.draft.bcc = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } }
                            ))
                            .textFieldStyle(.plain)
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
                            .textFieldStyle(.plain)
                            .font(.headline)
                    }
                    .padding()
                    
                    Divider()
                    
                    // Body
                    TextEditor(text: $viewModel.draft.body)
                        .font(.body)
                        .padding()
                        .frame(minHeight: 300)
                }
            }
        }
        .frame(minWidth: 600, minHeight: 500)
        .background(Color(nsColor: .windowBackgroundColor))
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

