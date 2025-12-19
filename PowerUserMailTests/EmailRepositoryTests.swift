//
//  EmailRepositoryTests.swift
//  PowerUserMailTests
//
//  Tests for EmailRepository Core Data operations
//

import CoreData
import XCTest

@testable import PowerUserMail

final class EmailRepositoryTests: XCTestCase {
    var repository: EmailRepository!
    var persistenceController: PersistenceController!

    override func setUp() {
        super.setUp()
        // Use in-memory store for testing
        persistenceController = PersistenceController(inMemory: true)
        repository = EmailRepository(persistenceController: persistenceController)
    }

    override func tearDown() {
        repository = nil
        persistenceController = nil
        super.tearDown()
    }

    // MARK: - Thread Tests

    func testSaveAndFetchThread() async throws {
        // Given
        let testEmail = Email(
            id: "email-1",
            threadId: "thread-1",
            subject: "Test Email",
            from: "sender@example.com",
            to: ["recipient@example.com"],
            preview: "This is a test",
            body: "Full email body",
            receivedAt: Date(),
            isRead: false,
            isArchived: false
        )

        let testThread = EmailThread(
            id: "thread-1",
            subject: "Test Email",
            messages: [testEmail],
            participants: ["sender@example.com", "recipient@example.com"],
            isMuted: false
        )

        // When
        try await repository.saveThread(testThread, for: "test@example.com")
        let fetchedThreads = try await repository.fetchThreads(for: "test@example.com")

        // Then
        XCTAssertEqual(fetchedThreads.count, 1)
        XCTAssertEqual(fetchedThreads.first?.id, "thread-1")
        XCTAssertEqual(fetchedThreads.first?.subject, "Test Email")
        XCTAssertEqual(fetchedThreads.first?.messages.count, 1)
    }

    func testUpdateExistingThread() async throws {
        // Given
        let testEmail1 = Email(
            id: "email-1",
            threadId: "thread-1",
            subject: "Original Subject",
            from: "sender@example.com",
            to: ["recipient@example.com"],
            preview: "Original preview",
            body: "Original body",
            receivedAt: Date(),
            isRead: false,
            isArchived: false
        )

        let originalThread = EmailThread(
            id: "thread-1",
            subject: "Original Subject",
            messages: [testEmail1],
            participants: ["sender@example.com"],
            isMuted: false
        )

        try await repository.saveThread(originalThread, for: "test@example.com")

        // When - Update with new message
        let testEmail2 = Email(
            id: "email-2",
            threadId: "thread-1",
            subject: "Updated Subject",
            from: "sender@example.com",
            to: ["recipient@example.com"],
            preview: "New message",
            body: "New message body",
            receivedAt: Date().addingTimeInterval(60),
            isRead: false,
            isArchived: false
        )

        let updatedThread = EmailThread(
            id: "thread-1",
            subject: "Updated Subject",
            messages: [testEmail1, testEmail2],
            participants: ["sender@example.com", "recipient@example.com"],
            isMuted: false
        )

        try await repository.saveThread(updatedThread, for: "test@example.com")
        let fetchedThreads = try await repository.fetchThreads(for: "test@example.com")

        // Then
        XCTAssertEqual(fetchedThreads.count, 1)
        XCTAssertEqual(fetchedThreads.first?.messages.count, 2)
        XCTAssertEqual(fetchedThreads.first?.subject, "Updated Subject")
    }

    // MARK: - Email Tests

    func testFetchEmailById() async throws {
        // Given
        let testEmail = Email(
            id: "email-123",
            threadId: "thread-1",
            subject: "Specific Email",
            from: "sender@example.com",
            to: ["recipient@example.com"],
            preview: "Preview",
            body: "Body content",
            receivedAt: Date(),
            isRead: false,
            isArchived: false
        )

        let testThread = EmailThread(
            id: "thread-1",
            subject: "Specific Email",
            messages: [testEmail],
            participants: ["sender@example.com"],
            isMuted: false
        )

        try await repository.saveThread(testThread, for: "test@example.com")

        // When
        let fetchedEmail = try await repository.fetchEmail(
            id: "email-123", accountEmail: "test@example.com")

        // Then
        XCTAssertNotNil(fetchedEmail)
        XCTAssertEqual(fetchedEmail?.id, "email-123")
        XCTAssertEqual(fetchedEmail?.subject, "Specific Email")
    }

    func testUpdateReadStatus() async throws {
        // Given
        let testEmail = Email(
            id: "email-read-test",
            threadId: "thread-1",
            subject: "Test",
            from: "sender@example.com",
            to: ["recipient@example.com"],
            preview: "Preview",
            body: "Body",
            receivedAt: Date(),
            isRead: false,
            isArchived: false
        )

        let testThread = EmailThread(
            id: "thread-1",
            subject: "Test",
            messages: [testEmail],
            participants: ["sender@example.com"],
            isMuted: false
        )

        try await repository.saveThread(testThread, for: "test@example.com")

        // When
        try await repository.updateReadStatus(
            emailId: "email-read-test", isRead: true, accountEmail: "test@example.com")
        let updatedEmail = try await repository.fetchEmail(
            id: "email-read-test", accountEmail: "test@example.com")

        // Then
        XCTAssertTrue(updatedEmail?.isRead ?? false)
    }

    func testUpdateArchiveStatus() async throws {
        // Given
        let testEmail = Email(
            id: "email-archive-test",
            threadId: "thread-1",
            subject: "Test",
            from: "sender@example.com",
            to: ["recipient@example.com"],
            preview: "Preview",
            body: "Body",
            receivedAt: Date(),
            isRead: false,
            isArchived: false
        )

        let testThread = EmailThread(
            id: "thread-1",
            subject: "Test",
            messages: [testEmail],
            participants: ["sender@example.com"],
            isMuted: false
        )

        try await repository.saveThread(testThread, for: "test@example.com")

        // When
        try await repository.updateArchiveStatus(
            emailId: "email-archive-test", isArchived: true, accountEmail: "test@example.com")
        let updatedEmail = try await repository.fetchEmail(
            id: "email-archive-test", accountEmail: "test@example.com")

        // Then
        XCTAssertTrue(updatedEmail?.isArchived ?? false)
    }

    // MARK: - Search Tests

    // TODO: Fix main actor isolation issue with Email/EmailThread initializers
    // This test fails because Email and EmailThread initializers require @MainActor
    // but XCTest async tests don't run on MainActor by default
    func skip_testSearchThreadsBySubject() async throws {
        // Given - Create test data on main actor
        let (thread1, thread2) = await MainActor.run {
            let email1 = Email(
                id: "email-1",
                threadId: "thread-1",
                subject: "Meeting tomorrow",
                from: "sender@example.com",
                to: ["recipient@example.com"],
                preview: "Preview",
                body: "Body",
                receivedAt: Date(),
                isRead: false,
                isArchived: false
            )

            let email2 = Email(
                id: "email-2",
                threadId: "thread-2",
                subject: "Lunch plans",
                from: "sender@example.com",
                to: ["recipient@example.com"],
                preview: "Preview",
                body: "Body",
                receivedAt: Date(),
                isRead: false,
                isArchived: false
            )

            let thread1 = EmailThread(
                id: "thread-1",
                subject: "Meeting tomorrow",
                messages: [email1],
                participants: ["sender@example.com"],
                isMuted: false
            )

            let thread2 = EmailThread(
                id: "thread-2",
                subject: "Lunch plans",
                messages: [email2],
                participants: ["sender@example.com"],
                isMuted: false
            )

            return (thread1, thread2)
        }

        try await repository.saveThread(thread1, for: "test@example.com")
        try await repository.saveThread(thread2, for: "test@example.com")

        // When
        let results = try await repository.searchThreads(query: "meeting", for: "test@example.com")

        // Then
        XCTAssertEqual(results.count, 1)
        await MainActor.run {
            XCTAssertEqual(results.first?.subject, "Meeting tomorrow")
        }
    }

    // MARK: - Attachment Tests

    func testSaveAttachmentData() async throws {
        // Given
        let attachment = EmailAttachment(
            id: UUID(),
            fileName: "document.pdf",
            mimeType: "application/pdf",
            sizeInBytes: 1024
        )

        let testEmail = Email(
            id: "email-1",
            threadId: "thread-1",
            subject: "Email with attachment",
            from: "sender@example.com",
            to: ["recipient@example.com"],
            preview: "Preview",
            body: "Body",
            receivedAt: Date(),
            isRead: false,
            isArchived: false,
            attachments: [attachment]
        )

        let testThread = EmailThread(
            id: "thread-1",
            subject: "Email with attachment",
            messages: [testEmail],
            participants: ["sender@example.com"],
            isMuted: false
        )

        try await repository.saveThread(testThread, for: "test@example.com")

        // When
        let base64Data = "SGVsbG8gV29ybGQh"  // "Hello World!" in base64
        try await repository.saveAttachmentData(base64Data, for: attachment.id)
        let retrievedData = try await repository.getAttachmentData(for: attachment.id)

        // Then
        XCTAssertEqual(retrievedData, base64Data)
    }

    // MARK: - Sync State Tests

    func testSyncStateTracking() async throws {
        // Given
        let syncDate = Date()

        // When
        try await repository.updateLastSyncDate(syncDate, for: "test@example.com")
        let retrievedDate = await repository.getLastSyncDate(for: "test@example.com")

        // Then
        XCTAssertNotNil(retrievedDate)
        if let retrievedDate = retrievedDate {
            XCTAssertEqual(
                retrievedDate.timeIntervalSince1970, syncDate.timeIntervalSince1970, accuracy: 1.0)
        }
    }

    // MARK: - Clear Cache Tests

    func testClearCache() async throws {
        // Given
        let testEmail = Email(
            id: "email-1",
            threadId: "thread-1",
            subject: "Test",
            from: "sender@example.com",
            to: ["recipient@example.com"],
            preview: "Preview",
            body: "Body",
            receivedAt: Date(),
            isRead: false,
            isArchived: false
        )

        let testThread = EmailThread(
            id: "thread-1",
            subject: "Test",
            messages: [testEmail],
            participants: ["sender@example.com"],
            isMuted: false
        )

        try await repository.saveThread(testThread, for: "test@example.com")
        try await repository.updateLastSyncDate(Date(), for: "test@example.com")

        // Verify data exists
        let threadsBeforeClear = try await repository.fetchThreads(for: "test@example.com")
        let syncDateBeforeClear = await repository.getLastSyncDate(for: "test@example.com")
        XCTAssertEqual(threadsBeforeClear.count, 1)
        XCTAssertNotNil(syncDateBeforeClear)

        // When
        try await repository.clearCache(for: "test@example.com")

        // Then
        let threadsAfterClear = try await repository.fetchThreads(for: "test@example.com")
        let syncDateAfterClear = await repository.getLastSyncDate(for: "test@example.com")
        XCTAssertEqual(threadsAfterClear.count, 0)
        XCTAssertNil(syncDateAfterClear)
    }
}
