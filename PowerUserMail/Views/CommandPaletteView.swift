import Foundation
import SwiftUI

struct CommandPaletteView: View {
    @Binding var isPresented: Bool
    @Binding var searchText: String
    let actions: [CommandAction]
    let conversations: [Conversation]
    let onSelect: (CommandAction) -> Void
    let onSelectConversation: (Conversation) -> Void

    @State private var selectedIndex: Int = 0
    @State private var selectedSection: SearchSection = .commands
    @State private var shouldScrollToSelection: Bool = false
    @FocusState private var isFocused: Bool
    
    enum SearchSection {
        case commands, recent
    }

    private var filteredResults: [CommandAction] {
        filterActions(query: searchText, actions: actions)
    }
    
    private var recentPeople: [Conversation] {
        // Show recent conversations when search is empty, or filter when searching
        if searchText.isEmpty {
            return Array(conversations.prefix(5))
        }
        
        let query = searchText.lowercased()
        let matching = conversations.filter { conversation in
            conversation.person.lowercased().contains(query) ||
            conversation.messages.contains { msg in
                msg.from.lowercased().contains(query)
            }
        }
        
        var seenEmails = Set<String>()
        var unique: [Conversation] = []
        
        for conversation in matching {
            let normalizedEmail = extractEmail(from: conversation.person).lowercased()
            if !seenEmails.contains(normalizedEmail) {
                seenEmails.insert(normalizedEmail)
                unique.append(conversation)
            }
        }
        
        return Array(unique.prefix(5))
    }
    
    private func extractEmail(from string: String) -> String {
        if let start = string.firstIndex(of: "<"),
           let end = string.firstIndex(of: ">"),
           start < end {
            return String(string[string.index(after: start)..<end])
        }
        return string.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func filterActions(query: String, actions: [CommandAction]) -> [CommandAction] {
        if query.isEmpty { return actions }
        
        let queryLower = query.lowercased()
        
        let scored = actions.compactMap { action -> (action: CommandAction, score: Int)? in
            let titleLower = action.title.lowercased()
            var bestScore = 0
            
            if titleLower.contains(queryLower) {
                bestScore = max(bestScore, 1000 + (100 - titleLower.count))
            }
            
            let titleWords = titleLower.split(separator: " ").map(String.init)
            let queryWords = queryLower.split(separator: " ").map(String.init)
            
            var wordPrefixScore = 0
            var allMatch = true
            for qWord in queryWords {
                var matched = false
                for tWord in titleWords {
                    if tWord.hasPrefix(qWord) {
                        wordPrefixScore += 50 + (10 - qWord.count)
                        matched = true
                        break
                    }
                }
                if !matched { allMatch = false }
            }
            if allMatch && !queryWords.isEmpty && wordPrefixScore > bestScore {
                bestScore = wordPrefixScore
            }
            
            let fuzzyScore = fuzzyMatch(query: queryLower, target: titleLower)
            if fuzzyScore > bestScore { bestScore = fuzzyScore }
            
            for keyword in action.keywords {
                let kw = keyword.lowercased()
                if kw.hasPrefix(queryLower) && 30 > bestScore { bestScore = 30 }
                else if kw.contains(queryLower) && 20 > bestScore { bestScore = 20 }
            }
            
            return bestScore > 0 ? (action, bestScore) : nil
        }
        
        return scored.sorted { $0.score > $1.score }.map { $0.action }
    }
    
    private func fuzzyMatch(query: String, target: String) -> Int {
        guard !query.isEmpty else { return 0 }
        
        var queryIndex = query.startIndex
        var targetIndex = target.startIndex
        var score = 0
        var consecutive = 0
        var lastWasConsecutive = false
        
        while queryIndex < query.endIndex && targetIndex < target.endIndex {
            if query[queryIndex] == target[targetIndex] {
                score += 10
                if lastWasConsecutive {
                    consecutive += 1
                    score += consecutive * 5
                } else {
                    consecutive = 1
                }
                lastWasConsecutive = true
                if targetIndex == target.startIndex || target[target.index(before: targetIndex)] == " " {
                    score += 15
                }
                queryIndex = query.index(after: queryIndex)
            } else {
                lastWasConsecutive = false
            }
            targetIndex = target.index(after: targetIndex)
        }
        
        return queryIndex < query.endIndex ? 0 : score + max(0, 50 - target.count)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search Bar (demo style)
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary)

                TextField("Search emails, commands, contacts...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16))
                    .foregroundColor(.primary)
                    .focused($isFocused)
                    .onSubmit { executeSelected() }
                    .onKeyPress(.downArrow) { moveSelection(1); return .handled }
                    .onKeyPress(.upArrow) { moveSelection(-1); return .handled }
                    .onKeyPress(.return) { executeSelected(); return .handled }
                    .onKeyPress(.escape) { isPresented = false; return .handled }
                
                Spacer()
                
                Text("esc to close")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

            Divider()
                .background(Color.secondary.opacity(0.3))

            // Results
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                        // ACTIONS Section
                        if !filteredResults.isEmpty {
                            Section {
                                ForEach(Array(filteredResults.enumerated()), id: \.offset) { index, action in
                                    CommandRowDemo(
                                        action: action, 
                                        isSelected: selectedSection == .commands && index == selectedIndex
                                    )
                                    .id("cmd-\(searchText)-\(index)")
                                    .onTapGesture {
                                        onSelect(action)
                                        isPresented = false
                                    }
                                    .onHover { if $0 { selectedSection = .commands; selectedIndex = index } }
                                }
                            } header: {
                                SectionHeaderDemo(title: searchText.isEmpty ? "ACTIONS" : "COMMANDS")
                            }
                        }
                        
                        // RECENT Section
                        if !recentPeople.isEmpty {
                            Section {
                                ForEach(Array(recentPeople.enumerated()), id: \.offset) { index, conversation in
                                    RecentRowDemo(
                                        conversation: conversation, 
                                        isSelected: selectedSection == .recent && index == selectedIndex
                                    )
                                    .id("recent-\(searchText)-\(index)")
                                    .onTapGesture {
                                        onSelectConversation(conversation)
                                        isPresented = false
                                    }
                                    .onHover { if $0 { selectedSection = .recent; selectedIndex = index } }
                                }
                            } header: {
                                SectionHeaderDemo(title: "RECENT")
                            }
                        }
                        
                        if filteredResults.isEmpty && recentPeople.isEmpty && !searchText.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 32))
                                    .foregroundStyle(.secondary)
                                Text("No results found")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                        }
                    }
                }
                .frame(maxHeight: 400)
                .onChange(of: selectedIndex) { _, newIndex in
                    if shouldScrollToSelection {
                        withAnimation(.easeOut(duration: 0.15)) {
                            let scrollId = selectedSection == .commands ? "cmd-\(newIndex)" : "recent-\(newIndex)"
                            proxy.scrollTo(scrollId, anchor: .center)
                        }
                        shouldScrollToSelection = false
                    }
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.purple.opacity(0.5), lineWidth: 2)
        )
        .shadow(color: .black.opacity(0.4), radius: 30, x: 0, y: 15)
        .frame(width: 500)
        .onAppear {
            selectedIndex = 0
            selectedSection = .commands
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { isFocused = true }
        }
        .onChange(of: searchText) { _, _ in
            selectedIndex = 0
            selectedSection = filteredResults.isEmpty && !recentPeople.isEmpty ? .recent : .commands
        }
    }

    private func moveSelection(_ direction: Int) {
        let cmdCount = filteredResults.count
        let recentCount = recentPeople.count
        
        // Enable auto-scroll for keyboard navigation
        shouldScrollToSelection = true
        
        if direction > 0 {
            if selectedSection == .commands {
                if selectedIndex < cmdCount - 1 { selectedIndex += 1 }
                else if recentCount > 0 { selectedSection = .recent; selectedIndex = 0 }
            } else {
                if selectedIndex < recentCount - 1 { selectedIndex += 1 }
                else if cmdCount > 0 { selectedSection = .commands; selectedIndex = 0 }
            }
        } else {
            if selectedSection == .commands {
                if selectedIndex > 0 { selectedIndex -= 1 }
                else if recentCount > 0 { selectedSection = .recent; selectedIndex = recentCount - 1 }
            } else {
                if selectedIndex > 0 { selectedIndex -= 1 }
                else if cmdCount > 0 { selectedSection = .commands; selectedIndex = cmdCount - 1 }
            }
        }
    }

    private func executeSelected() {
        if selectedSection == .commands {
            guard !filteredResults.isEmpty else { return }
            let action = filteredResults[selectedIndex]
            guard action.isEnabled else { return }
            isPresented = false
            onSelect(action)
        } else {
            guard !recentPeople.isEmpty else { return }
            isPresented = false
            onSelectConversation(recentPeople[selectedIndex])
        }
    }
}

// MARK: - Demo Style Section Header
struct SectionHeaderDemo: View {
    let title: String
    
    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(1)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - Demo Style Command Row
struct CommandRowDemo: View {
    let action: CommandAction
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 14) {
            // Icon with colored background
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(action.iconColor.color.opacity(isSelected ? 1 : 0.8))
                    .frame(width: 36, height: 36)
                
                Image(systemName: action.iconSystemName)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(action.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.primary)
                
                if !action.subtitle.isEmpty {
                    Text(action.subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            if !action.shortcut.isEmpty {
                Text(action.shortcut)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}

// MARK: - Demo Style Recent Row
struct RecentRowDemo: View {
    let conversation: Conversation
    let isSelected: Bool
    
    private var displayName: String {
        let person = conversation.person
        if let nameEnd = person.firstIndex(of: "<") {
            let name = String(person[..<nameEnd]).trimmingCharacters(in: .whitespaces)
            if !name.isEmpty { return name }
        }
        if let atIndex = person.firstIndex(of: "@") {
            return String(person[..<atIndex])
        }
        return person
    }
    
    private var email: String {
        let person = conversation.person
        if let start = person.firstIndex(of: "<"), let end = person.firstIndex(of: ">") {
            return String(person[person.index(after: start)..<end])
        }
        if person.contains("@") { return person }
        return ""
    }
    
    var body: some View {
        HStack(spacing: 14) {
            SenderProfilePicture(email: conversation.person, size: 36)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                
                if !email.isEmpty {
                    Text(email)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}

#Preview {
    CommandPaletteView(
        isPresented: .constant(true),
        searchText: .constant(""),
        actions: [
            CommandAction(title: "New Email", subtitle: "Compose a new message", iconSystemName: "envelope", iconColor: .blue, shortcut: "⌘N") {},
            CommandAction(title: "Mark All as Read", subtitle: "Clear all unread badges", iconSystemName: "checkmark", iconColor: .green, shortcut: "⌘⇧R") {},
        ],
        conversations: [],
        onSelect: { _ in },
        onSelectConversation: { _ in }
    )
    .padding(40)
    .background(Color.black.opacity(0.5))
}
