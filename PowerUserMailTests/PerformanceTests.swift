//
//  PerformanceTests.swift
//  PowerUserMailTests
//
//  Comprehensive performance tests for sub-50ms rule enforcement.
//  Target: Every user interaction under 50ms.
//

import XCTest

@testable import PowerUserMail

// Enables faster iterations when FAST_TESTS=1 is set in the environment.
private let isFastTestsEnabled = ProcessInfo.processInfo.environment["FAST_TESTS"] == "1"

/// Performance test suite measuring all user interactions against the 50ms target
final class PerformanceTests: XCTestCase {

    // MARK: - Properties

    private var results: [TestResult] = []
    private let targetMs: Double = 50.0

    struct TestResult {
        let name: String
        let category: String
        let durationMs: Double
        let passed: Bool
    }

    // MARK: - Setup/Teardown

    override func setUp() {
        super.setUp()
        results = []
    }

    override func tearDown() {
        // Print summary for this test class
        printTestSummary()
        super.tearDown()
    }

    // MARK: - Helper Methods

    private func measureOperation(
        name: String,
        category: String,
        iterations: Int = 10,
        operation: () -> Void
    ) -> Double {
        let actualIterations = isFastTestsEnabled ? max(1, iterations / 3) : iterations
        var totalTime: Double = 0

        for _ in 0..<actualIterations {
            let start = CFAbsoluteTimeGetCurrent()
            operation()
            let duration = (CFAbsoluteTimeGetCurrent() - start) * 1000
            totalTime += duration
        }

        let avgMs = totalTime / Double(actualIterations)
        let passed = avgMs <= targetMs

        results.append(
            TestResult(
                name: name,
                category: category,
                durationMs: avgMs,
                passed: passed
            ))

        return avgMs
    }

    private func printTestSummary() {
        guard !results.isEmpty else { return }

        print("\n" + String(repeating: "=", count: 60))
        print("PERFORMANCE TEST RESULTS")
        print(String(repeating: "=", count: 60))

        for result in results.sorted(by: { $0.durationMs > $1.durationMs }) {
            let status = result.passed ? "✅" : "❌"
            print(
                "\(status) [\(result.category)] \(result.name): \(String(format: "%.2f", result.durationMs))ms"
            )
        }

        let passed = results.filter { $0.passed }.count
        let total = results.count
        let passRate = Double(passed) / Double(total) * 100

        print(String(repeating: "-", count: 60))
        print("Pass rate: \(passed)/\(total) (\(String(format: "%.1f", passRate))%)")
        print(String(repeating: "=", count: 60) + "\n")
    }

    // MARK: - Data Structure Tests

    func testEmailCreation() {
        let duration = measureOperation(name: "Create Email", category: "Data") {
            let _ = Email(
                id: "1",
                threadId: "t1",
                subject: "Test Subject",
                from: "test@example.com",
                to: ["user@example.com"],
                preview: "Test preview",
                body: "Test body",
                receivedAt: Date()
            )
        }
        XCTAssertLessThanOrEqual(duration, targetMs, "Email creation should be under \(targetMs)ms")
    }

    func testConversationCreation() {
        let duration = measureOperation(name: "Create Conversation", category: "Data") {
            let email = Email(
                id: "1",
                threadId: "t1",
                subject: "Test",
                from: "test@example.com",
                to: ["user@example.com"],
                preview: "Preview",
                body: "Test body",
                receivedAt: Date()
            )
            let _ = Conversation(
                id: "c1",
                person: "Test User",
                messages: [email]
            )
        }
        XCTAssertLessThanOrEqual(
            duration, targetMs, "Conversation creation should be under \(targetMs)ms")
    }

    // MARK: - Command Registry Tests

    @MainActor
    func testCommandRegistryLookup() {
        // First ensure commands are loaded
        CommandLoader.loadAll()

        let duration = measureOperation(
            name: "Command Registry Lookup", category: "Command Palette"
        ) {
            let _ = CommandRegistry.shared.getCommands(hasSelectedConversation: false)
        }
        XCTAssertLessThanOrEqual(duration, targetMs, "Command lookup should be under \(targetMs)ms")
    }

    @MainActor
    func testCommandFiltering() {
        CommandLoader.loadAll()

        let duration = measureOperation(name: "Command Filtering", category: "Command Palette") {
            let _ = CommandRegistry.shared.filterCommands(searchText: "mark")
        }
        XCTAssertLessThanOrEqual(
            duration, targetMs, "Command filtering should be under \(targetMs)ms")
    }

    @MainActor
    func testFuzzySearchCommands() {
        CommandLoader.loadAll()
        let commands = CommandRegistry.shared.getCommands()

        let searchTerms = ["new", "mark", "quit", "switch", "archive", "pin", "show", "toggle"]

        for term in searchTerms {
            let duration = measureOperation(
                name: "Fuzzy Search '\(term)'", category: "Search", iterations: 20
            ) {
                let _ = commands.filter { action in
                    action.title.lowercased().contains(term)
                        || action.keywords.contains { $0.lowercased().contains(term) }
                }
            }
            XCTAssertLessThanOrEqual(
                duration, targetMs, "Fuzzy search for '\(term)' should be under \(targetMs)ms")
        }
    }

    // MARK: - State Management Tests

    @MainActor
    func testConversationStateRead() {
        let store = ConversationStateStore.shared

        let duration = measureOperation(name: "Read Conversation State", category: "State") {
            let _ = store.isRead(conversationId: "test-123")
        }
        XCTAssertLessThanOrEqual(duration, targetMs, "State read should be under \(targetMs)ms")
    }

    @MainActor
    func testConversationStateWrite() {
        let store = ConversationStateStore.shared

        let duration = measureOperation(name: "Write Conversation State", category: "State") {
            store.markAsRead(conversationId: "test-\(UUID().uuidString)")
        }
        XCTAssertLessThanOrEqual(duration, targetMs, "State write should be under \(targetMs)ms")
    }

    @MainActor
    func testPinConversation() {
        let store = ConversationStateStore.shared

        let duration = measureOperation(name: "Pin Conversation", category: "State") {
            store.togglePinned(conversationId: "test-\(UUID().uuidString)")
        }
        XCTAssertLessThanOrEqual(duration, targetMs, "Pin toggle should be under \(targetMs)ms")
    }

    @MainActor
    func testMuteConversation() {
        let store = ConversationStateStore.shared

        let duration = measureOperation(name: "Mute Conversation", category: "State") {
            store.toggleMuted(conversationId: "test-\(UUID().uuidString)")
        }
        XCTAssertLessThanOrEqual(duration, targetMs, "Mute toggle should be under \(targetMs)ms")
    }

    // MARK: - Collection Operations Tests

    func testFilterConversations() {
        // Create test data
        let conversations = (0..<100).map { i in
            Conversation(
                id: "conv-\(i)",
                person: "User \(i)",
                messages: [
                    Email(
                        id: "msg-\(i)",
                        threadId: "thread-\(i)",
                        subject: "Subject \(i)",
                        from: "user\(i)@example.com",
                        to: ["me@example.com"],
                        preview: "Preview \(i)",
                        body: "Body \(i)",
                        receivedAt: Date().addingTimeInterval(Double(-i * 3600)),
                        isRead: i % 2 == 0
                    )
                ]
            )
        }

        let duration = measureOperation(name: "Filter 100 Conversations", category: "Email List") {
            let _ = conversations.filter { $0.messages.first?.isRead == false }
        }
        XCTAssertLessThanOrEqual(
            duration, targetMs, "Filtering 100 conversations should be under \(targetMs)ms")
    }

    func testSortConversations() {
        let conversations = (0..<100).map { i in
            Conversation(
                id: "conv-\(i)",
                person: "User \(i)",
                messages: [
                    Email(
                        id: "msg-\(i)",
                        threadId: "thread-\(i)",
                        subject: "Subject \(i)",
                        from: "user\(i)@example.com",
                        to: ["me@example.com"],
                        preview: "Preview \(i)",
                        body: "Body \(i)",
                        receivedAt: Date().addingTimeInterval(Double.random(in: -86400...0))
                    )
                ]
            )
        }

        let duration = measureOperation(name: "Sort 100 Conversations", category: "Email List") {
            let _ = conversations.sorted {
                ($0.messages.first?.receivedAt ?? Date())
                    > ($1.messages.first?.receivedAt ?? Date())
            }
        }
        XCTAssertLessThanOrEqual(
            duration, targetMs, "Sorting 100 conversations should be under \(targetMs)ms")
    }

    func testSearchConversations() {
        let conversations = (0..<100).map { i in
            Conversation(
                id: "conv-\(i)",
                person: "User \(i) <user\(i)@example.com>",
                messages: [
                    Email(
                        id: "msg-\(i)",
                        threadId: "thread-\(i)",
                        subject: "Important meeting about project \(i)",
                        from: "user\(i)@example.com",
                        to: ["me@example.com"],
                        preview: "Preview",
                        body: "This is the body of email \(i) with some searchable content.",
                        receivedAt: Date()
                    )
                ]
            )
        }

        let duration = measureOperation(name: "Search 100 Conversations", category: "Search") {
            let searchTerm = "project"
            let _ = conversations.filter { conv in
                conv.person.lowercased().contains(searchTerm)
                    || conv.messages.contains { $0.subject.lowercased().contains(searchTerm) }
            }
        }
        XCTAssertLessThanOrEqual(
            duration, targetMs, "Searching 100 conversations should be under \(targetMs)ms")
    }

    // MARK: - String Operations Tests

    func testEmailParsing() {
        let emails = [
            "John Doe <john@example.com>",
            "jane@example.com",
            "\"Bob Smith\" <bob.smith@company.org>",
            "support@company.com",
            "Test User <test.user+tag@subdomain.example.co.uk>",
        ]

        let duration = measureOperation(
            name: "Parse Email Addresses", category: "Data", iterations: 100
        ) {
            for email in emails {
                // Extract name and email
                if let start = email.firstIndex(of: "<"), let end = email.firstIndex(of: ">") {
                    let _ = String(email[..<start]).trimmingCharacters(in: .whitespaces)
                    let _ = String(email[email.index(after: start)..<end])
                } else {
                    let _ = email
                }
            }
        }
        XCTAssertLessThanOrEqual(duration, targetMs, "Email parsing should be under \(targetMs)ms")
    }

    func testInitialsGeneration() {
        let names = [
            "John Doe",
            "Jane Smith",
            "Bob",
            "Alice Johnson-Williams",
            "user@example.com",
        ]

        let duration = measureOperation(name: "Generate Initials", category: "UI", iterations: 100)
        {
            for name in names {
                let words = name.split(separator: " ").prefix(2)
                let _ = words.compactMap { $0.first.map(String.init) }.joined()
            }
        }
        XCTAssertLessThanOrEqual(
            duration, targetMs, "Initials generation should be under \(targetMs)ms")
    }

    // MARK: - Date Formatting Tests

    func testDateFormatting() {
        let dates = [
            Date(),
            Date().addingTimeInterval(-3600),  // 1 hour ago
            Date().addingTimeInterval(-86400),  // 1 day ago
            Date().addingTimeInterval(-604800),  // 1 week ago
            Date().addingTimeInterval(-2_592_000),  // 30 days ago
        ]

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated

        let duration = measureOperation(
            name: "Format Relative Dates", category: "UI", iterations: 100
        ) {
            for date in dates {
                let _ = formatter.localizedString(for: date, relativeTo: Date())
            }
        }
        XCTAssertLessThanOrEqual(
            duration, targetMs, "Date formatting should be under \(targetMs)ms")
    }

    // MARK: - Performance Monitor Tests

    @MainActor
    func testPerformanceMonitorOverhead() {
        let monitor = PerformanceMonitor.shared

        let duration = measureOperation(name: "Performance Monitor Overhead", category: "System") {
            monitor.measure("test", category: .uiInteraction) {
                // Empty operation to measure overhead
            }
        }
        // Monitor overhead should be minimal
        XCTAssertLessThanOrEqual(duration, 5.0, "Performance monitor overhead should be under 5ms")
    }

    @MainActor
    func testReportGeneration() {
        let monitor = PerformanceMonitor.shared
        monitor.clearMetrics()

        // Add some test metrics
        let metricCount = isFastTestsEnabled ? 20 : 100
        for i in 0..<metricCount {
            monitor.addTestMetric(
                name: "Test \(i)",
                category: PerformanceCategory.allCases[i % PerformanceCategory.allCases.count],
                durationMs: Double.random(in: 1...100)
            )
        }

        let duration = measureOperation(name: "Generate Report (100 metrics)", category: "System") {
            let report = monitor.generateReport()
            let _ = report.toMarkdown()
        }
        XCTAssertLessThanOrEqual(duration, 100, "Report generation should be under 100ms")

        monitor.clearMetrics()
    }
}

// MARK: - Large Scale Performance Tests

final class LargeScalePerformanceTests: XCTestCase {

    func testFilter1000Conversations() {
        let total = isFastTestsEnabled ? 200 : 1000
        let conversations = (0..<total).map { i in
            Conversation(
                id: "conv-\(i)",
                person: "User \(i)",
                messages: [
                    Email(
                        id: "msg-\(i)",
                        threadId: "thread-\(i)",
                        subject: "Subject \(i)",
                        from: "user\(i)@example.com",
                        to: ["me@example.com"],
                        preview: "Preview",
                        body: String(repeating: "Content ", count: 100),
                        receivedAt: Date().addingTimeInterval(Double(-i * 60)),
                        isRead: i % 3 == 0
                    )
                ]
            )
        }

        measure {
            let _ = conversations.filter { !($0.messages.first?.isRead ?? true) }
        }
    }

    func testSort1000Conversations() {
        let total = isFastTestsEnabled ? 200 : 1000
        let conversations = (0..<total).map { i in
            Conversation(
                id: "conv-\(i)",
                person: "User \(i)",
                messages: [
                    Email(
                        id: "msg-\(i)",
                        threadId: "thread-\(i)",
                        subject: "Subject \(i)",
                        from: "user\(i)@example.com",
                        to: ["me@example.com"],
                        preview: "Preview",
                        body: "Body",
                        receivedAt: Date().addingTimeInterval(Double.random(in: -86400 * 30...0))
                    )
                ]
            )
        }

        measure {
            let _ = conversations.sorted {
                ($0.messages.first?.receivedAt ?? Date())
                    > ($1.messages.first?.receivedAt ?? Date())
            }
        }
    }

    @MainActor
    func testCommandSearch100Times() {
        CommandLoader.loadAll()
        let searchTerms = [
            "new", "mark", "quit", "switch", "archive", "pin", "show", "all", "read", "email",
        ]
        let iterations = isFastTestsEnabled ? 3 : 10
        measure {
            for _ in 0..<iterations {
                for term in searchTerms {
                    let _ = CommandRegistry.shared.filterCommands(searchText: term)
                }
            }
        }
    }
}
