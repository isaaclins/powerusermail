import SwiftUI

struct InboxView: View {
    @StateObject private var viewModel: InboxViewModel
    @Binding var selectedThread: EmailThread?

    init(service: MailService, selectedThread: Binding<EmailThread?>) {
        _viewModel = StateObject(wrappedValue: InboxViewModel(service: service))
        _selectedThread = selectedThread
    }

    var body: some View {
        List(selection: $selectedThread) {
            ForEach(viewModel.threads) { thread in
                Button {
                    viewModel.select(thread: thread)
                    selectedThread = thread
                } label: {
                    VStack(alignment: .leading) {
                        HStack {
                            Text(thread.subject)
                                .font(.headline)
                            Spacer()
                            if let last = thread.lastMessage {
                                Text(last.receivedAt, style: .time)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if let last = thread.lastMessage {
                            Text(last.preview)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .task { await viewModel.loadInbox() }
        .overlay {
            if viewModel.isLoading {
                ProgressView("Loading inbox…")
            } else if let error = viewModel.errorMessage {
                VStack(spacing: 8) {
                    Text(error)
                        .multilineTextAlignment(.center)
                    Button("Retry") {
                        Task { await viewModel.loadInbox() }
                    }
                }
                .padding()
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(radius: 10)
            } else if viewModel.threads.isEmpty {
                ContentUnavailableView("No Messages", systemImage: "tray")
            }
        }
    }
}
