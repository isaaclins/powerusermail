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
    @FocusState private var isFocused: Bool
    
    enum SearchSection {
        case commands, people
    }

    // Computed property that filters based on current searchText
    private var filteredResults: [CommandAction] {
        filterActions(query: searchText, actions: actions)
    }
    
    // Filter conversations/people based on search
    private var filteredPeople: [Conversation] {
        guard !searchText.isEmpty else { return [] }
        let query = searchText.lowercased()
        return conversations.filter { conversation in
            conversation.person.lowercased().contains(query) ||
            conversation.messages.contains { msg in
                msg.from.lowercased().contains(query) ||
                msg.to.joined(separator: " ").lowercased().contains(query)
            }
        }.prefix(5).map { $0 } // Limit to 5 results
    }
    
    // Pure function for filtering - no side effects
    private func filterActions(query: String, actions: [CommandAction]) -> [CommandAction] {
        if query.isEmpty { 
            print("\n> got: \"\" (empty)")
            print("> showing all \(actions.count) commands")
            return actions 
        }
        
        let queryLower = query.lowercased()
        print("\n> got: \"\(queryLower)\"")
        print("> searching through \(actions.count) commands...")
        
        // Score each action using fuzzy matching
        let scored = actions.compactMap { action -> (action: CommandAction, score: Int)? in
            let titleLower = action.title.lowercased()
            
            // Try different matching strategies and take the best score
            var bestScore = 0
            var matchReason = ""
            
            // 1. Exact substring match (highest priority)
            if titleLower.contains(queryLower) {
                let score = 1000 + (100 - titleLower.count)
                bestScore = max(bestScore, score)
                matchReason = "exact substring in title"
            }
            
            // 2. Word prefix matching - "mar" matches "Mark All as Read"
            let titleWords = titleLower.split(separator: " ").map(String.init)
            let queryWords = queryLower.split(separator: " ").map(String.init)
            
            var wordPrefixScore = 0
            var allQueryWordsMatch = true
            for qWord in queryWords {
                var matched = false
                for tWord in titleWords {
                    if tWord.hasPrefix(qWord) {
                        wordPrefixScore += 50 + (10 - qWord.count)
                        matched = true
                        break
                    }
                }
                if !matched {
                    allQueryWordsMatch = false
                }
            }
            if allQueryWordsMatch && !queryWords.isEmpty && wordPrefixScore > bestScore {
                bestScore = wordPrefixScore
                matchReason = "word prefix match"
            }
            
            // 3. Fuzzy match - characters appear in order (like Raycast)
            let fuzzyScore = fuzzyMatch(query: queryLower, target: titleLower)
            if fuzzyScore > bestScore {
                bestScore = fuzzyScore
                matchReason = "fuzzy match in title"
            }
            
            // 4. Keyword matching (lower priority)
            for keyword in action.keywords {
                let keywordLower = keyword.lowercased()
                if keywordLower.hasPrefix(queryLower) && 30 > bestScore {
                    bestScore = 30
                    matchReason = "keyword prefix: \(keyword)"
                } else if keywordLower.contains(queryLower) && 20 > bestScore {
                    bestScore = 20
                    matchReason = "keyword contains: \(keyword)"
                } else if fuzzyMatch(query: queryLower, target: keywordLower) > 0 && 10 > bestScore {
                    bestScore = 10
                    matchReason = "keyword fuzzy: \(keyword)"
                }
            }
            
            if bestScore > 0 {
                print("  - \"\(action.title)\" score=\(bestScore) (\(matchReason))")
            }
            
            return bestScore > 0 ? (action, bestScore) : nil
        }
        
        // Sort by score (highest first)
        let results = scored
            .sorted { $0.score > $1.score }
            .map { $0.action }
        
        print("> possible recommendations:")
        for action in results {
            print("  - \"\(action.title)\"")
        }
        print("")
        
        return results
    }
    
    /// Fuzzy match - characters must appear in order, consecutive matches score higher
    /// "nml" matches "New eMaiL", "mar" matches "MARk all as read"
    private func fuzzyMatch(query: String, target: String) -> Int {
        guard !query.isEmpty else { return 0 }
        
        var queryIndex = query.startIndex
        var targetIndex = target.startIndex
        var score = 0
        var consecutiveMatches = 0
        var lastMatchWasConsecutive = false
        
        while queryIndex < query.endIndex && targetIndex < target.endIndex {
            let queryChar = query[queryIndex]
            let targetChar = target[targetIndex]
            
            if queryChar == targetChar {
                // Character matched
                score += 10
                
                // Bonus for consecutive matches
                if lastMatchWasConsecutive {
                    consecutiveMatches += 1
                    score += consecutiveMatches * 5
                } else {
                    consecutiveMatches = 1
                }
                lastMatchWasConsecutive = true
                
                // Bonus for matching at start of word
                if targetIndex == target.startIndex || target[target.index(before: targetIndex)] == " " {
                    score += 15
                }
                
                queryIndex = query.index(after: queryIndex)
            } else {
                lastMatchWasConsecutive = false
            }
            
            targetIndex = target.index(after: targetIndex)
        }
        
        // All query characters must be found
        if queryIndex < query.endIndex {
            return 0
        }
        
        // Bonus for shorter targets (tighter match)
        score += max(0, 50 - target.count)
        
        return score
    }

    private var totalItemCount: Int {
        filteredResults.count + filteredPeople.count
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Search Bar
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.title3)
                    .foregroundStyle(.secondary)

                TextField("Type a command or contact...", text: $searchText)
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
                        // Commands Section
                        if !filteredResults.isEmpty {
                            SectionHeader(title: "Commands")
                            
                            ForEach(Array(filteredResults.enumerated()), id: \.element.id) {
                                index, action in
                                CommandRow(action: action, isSelected: selectedSection == .commands && index == selectedIndex)
                                    .id("cmd-\(index)")
                                    .onTapGesture {
                                        onSelect(action)
                                        isPresented = false
                                    }
                                    .onHover { hovering in
                                        if hovering { 
                                            selectedSection = .commands
                                            selectedIndex = index 
                                        }
                                    }
                            }
                        }
                        
                        // People Section
                        if !filteredPeople.isEmpty {
                            SectionHeader(title: "People")
                            
                            ForEach(Array(filteredPeople.enumerated()), id: \.element.id) {
                                index, conversation in
                                PersonRow(conversation: conversation, isSelected: selectedSection == .people && index == selectedIndex)
                                    .id("person-\(index)")
                                    .onTapGesture {
                                        onSelectConversation(conversation)
                                        isPresented = false
                                    }
                                    .onHover { hovering in
                                        if hovering { 
                                            selectedSection = .people
                                            selectedIndex = index 
                                        }
                                    }
                            }
                        }
                        
                        // No results
                        if filteredResults.isEmpty && filteredPeople.isEmpty && !searchText.isEmpty {
                            ContentUnavailableView(
                                "No Results Found", systemImage: "magnifyingglass"
                            )
                            .padding(.vertical, 40)
                        }
                        
                        // Empty state
                        if searchText.isEmpty && filteredResults.isEmpty {
                            ContentUnavailableView(
                                "No Commands Found", systemImage: "command.slash"
                            )
                            .padding(.vertical, 40)
                        }
                    }
                    .id(searchText) // Force re-render when search changes
                }
                .frame(maxHeight: 350)
                .onChange(of: selectedIndex) { _, newIndex in
                    withAnimation {
                        let scrollId = selectedSection == .commands ? "cmd-\(newIndex)" : "person-\(newIndex)"
                        proxy.scrollTo(scrollId, anchor: .center)
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
            selectedSection = .commands
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isFocused = true
            }
        }
        .onChange(of: searchText) { _, _ in
            selectedIndex = 0
            selectedSection = filteredResults.isEmpty && !filteredPeople.isEmpty ? .people : .commands
        }
    }

    private func moveSelection(_ direction: Int) {
        let commandCount = filteredResults.count
        let peopleCount = filteredPeople.count
        
        if direction > 0 {
            // Moving down
            if selectedSection == .commands {
                if selectedIndex < commandCount - 1 {
                    selectedIndex += 1
                } else if peopleCount > 0 {
                    selectedSection = .people
                    selectedIndex = 0
                }
            } else {
                if selectedIndex < peopleCount - 1 {
                    selectedIndex += 1
                } else if commandCount > 0 {
                    selectedSection = .commands
                    selectedIndex = 0
                }
            }
        } else {
            // Moving up
            if selectedSection == .commands {
                if selectedIndex > 0 {
                    selectedIndex -= 1
                } else if peopleCount > 0 {
                    selectedSection = .people
                    selectedIndex = peopleCount - 1
                }
            } else {
                if selectedIndex > 0 {
                    selectedIndex -= 1
                } else if commandCount > 0 {
                    selectedSection = .commands
                    selectedIndex = commandCount - 1
                }
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
            guard !filteredPeople.isEmpty else { return }
            let conversation = filteredPeople[selectedIndex]
            isPresented = false
            onSelectConversation(conversation)
        }
    }
}

struct SectionHeader: View {
    let title: String
    
    var body: some View {
        HStack {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.5))
    }
}

struct PersonRow: View {
    let conversation: Conversation
    let isSelected: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            // Avatar
            ZStack {
                Circle()
                    .fill(avatarGradient)
                    .frame(width: 28, height: 28)
                
                Text(initials)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(conversation.person)
                    .font(.body)
                    .foregroundStyle(isSelected ? .white : .primary)
                
                if let lastMessage = conversation.latestMessage {
                    Text(lastMessage.subject)
                        .font(.caption)
                        .foregroundStyle(isSelected ? .white.opacity(0.7) : .secondary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            Text("Contact")
                .font(.caption)
                .foregroundStyle(isSelected ? .white.opacity(0.6) : Color.secondary.opacity(0.6))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(isSelected ? Color.accentColor : Color.clear)
        .contentShape(Rectangle())
    }
    
    private var initials: String {
        let words = conversation.person.split(separator: " ").prefix(2)
        return words.compactMap { $0.first.map(String.init) }.joined()
    }
    
    private var avatarGradient: LinearGradient {
        let colors = [
            [Color.blue, Color.purple],
            [Color.orange, Color.red],
            [Color.green, Color.teal],
            [Color.pink, Color.purple],
            [Color.indigo, Color.blue]
        ]
        let index = abs(conversation.person.hashValue) % colors.count
        return LinearGradient(colors: colors[index], startPoint: .topLeading, endPoint: .bottomTrailing)
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
        conversations: [],
        onSelect: { _ in },
        onSelectConversation: { _ in }
    )
    .padding()
}
