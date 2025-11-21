import SwiftUI

struct CommandPaletteView: View {
    @Binding var isPresented: Bool
    @Binding var searchText: String
    let actions: [CommandAction]
    let onSelect: (CommandAction) -> Void

    var filteredActions: [CommandAction] {
        guard !searchText.isEmpty else { return actions }
        return actions.filter { action in
            action.title.localizedCaseInsensitiveContains(searchText) ||
            action.keywords.contains(where: { $0.localizedCaseInsensitiveContains(searchText) })
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            TextField("Search commands", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(.top, 12)
            List(filteredActions) { action in
                Button {
                    guard action.isEnabled else { return }
                    isPresented = false
                    onSelect(action)
                } label: {
                    HStack {
                        Image(systemName: action.iconSystemName)
                        Text(action.title)
                        Spacer()
                        if !action.isEnabled {
                            Text("Disabled")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .disabled(!action.isEnabled)
            }
            .listStyle(.plain)
            .frame(maxHeight: 300)
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(radius: 20)
        .padding()
        .onExitCommand {
            isPresented = false
        }
    }
}

#Preview {
    CommandPaletteView(
        isPresented: .constant(true),
        searchText: .constant(""),
        actions: [
            CommandAction(title: "New Email") {},
            CommandAction(title: "Archive") {}
        ],
        onSelect: { _ in }
    )
    .frame(width: 400)
}
