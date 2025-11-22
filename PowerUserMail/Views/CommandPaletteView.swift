import Foundation
import SwiftUI

struct CommandPaletteView: View {
    @Binding var isPresented: Bool
    @Binding var searchText: String
    let actions: [CommandAction]
    let onSelect: (CommandAction) -> Void

    @State private var selectedIndex: Int = 0
    @FocusState private var isFocused: Bool

    var filteredActions: [CommandAction] {
        if searchText.isEmpty { return actions }
        return actions.filter { action in
            action.title.localizedCaseInsensitiveContains(searchText)
                || action.keywords.contains(where: {
                    $0.localizedCaseInsensitiveContains(searchText)
                })
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search Bar
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.title3)
                    .foregroundStyle(.secondary)

                TextField("Type a command...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .foregroundColor(.white)
                    .focused($isFocused)
                    .onSubmit {
                        executeSelected()
                    }
                    // Intercept arrow keys for navigation
                    .onKeyPress(.downArrow) {
                        moveSelection(1)
                        return .handled
                    }
                    .onKeyPress(.upArrow) {
                        moveSelection(-1)
                        return .handled
                    }
                    .onKeyPress(.return) {
                        executeSelected()
                        return .handled
                    }
                    .onKeyPress(.escape) {
                        isPresented = false
                        return .handled
                    }
            }
            .padding()
            .background(.ultraThinMaterial)

            Divider()

            // Results List
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if filteredActions.isEmpty {
                            ContentUnavailableView(
                                "No Commands Found", systemImage: "command.slash"
                            )
                            .padding(.vertical, 40)
                        } else {
                            ForEach(Array(filteredActions.enumerated()), id: \.element.id) {
                                index, action in
                                CommandRow(action: action, isSelected: index == selectedIndex)
                                    .id(index)
                                    .onTapGesture {
                                        onSelect(action)
                                        isPresented = false
                                    }
                                    .onHover { hovering in
                                        if hovering { selectedIndex = index }
                                    }
                            }
                        }
                    }
                }
                .frame(maxHeight: 300)
                .onChange(of: selectedIndex) { _, newIndex in
                    withAnimation {
                        proxy.scrollTo(newIndex, anchor: .center)
                    }
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
        .frame(width: 600)
        .environment(\.colorScheme, .dark)
        .onAppear {
            selectedIndex = 0
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isFocused = true
            }
        }
        .onChange(of: searchText) { _, _ in
            selectedIndex = 0
        }
    }

    private func moveSelection(_ direction: Int) {
        let count = filteredActions.count
        guard count > 0 else { return }
        selectedIndex = (selectedIndex + direction + count) % count
    }

    private func executeSelected() {
        guard !filteredActions.isEmpty else { return }
        let action = filteredActions[selectedIndex]
        guard action.isEnabled else { return }
        isPresented = false
        onSelect(action)
    }
}

struct CommandRow: View {
    let action: CommandAction
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: action.iconSystemName)
                .font(.body)
                .frame(width: 24)
                .foregroundStyle(isSelected ? .white : .secondary)

            Text(action.title)
                .font(.body)
                .foregroundStyle(isSelected ? .white : .primary)

            Spacer()

            if !action.isEnabled {
                Text("Disabled")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(isSelected ? Color.accentColor : Color.clear)
        .contentShape(Rectangle())
    }
}

#Preview {
    CommandPaletteView(
        isPresented: .constant(true),
        searchText: .constant(""),
        actions: [
            CommandAction(title: "New Email") {},
            CommandAction(title: "Archive") {},
        ],
        onSelect: { _ in }
    )
    .padding()
}
