//
//  DemoMailboxTests.swift
//  PowerUserMailTests
//
//  The sample mailbox is what the website screenshots show, so keep it believable.
//

import XCTest

@testable import PowerUserMail

@MainActor
final class DemoMailboxTests: XCTestCase {
    func testMailboxHasConversationWithReplies() {
        let threads = DemoMailbox.threads(now: Date())
        XCTAssertGreaterThanOrEqual(threads.count, 8)

        let launch = threads.first { $0.id == "launch" }
        XCTAssertNotNil(launch)
        XCTAssertTrue(launch!.messages.contains { $0.from == DemoMailbox.meFull })
        XCTAssertTrue(launch!.messages.contains { !$0.isRead })
    }

    func testMessageIDsAreUnique() {
        let ids = DemoMailbox.threads(now: Date()).flatMap(\.messages).map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
    }

    func testNoPlaceholderCopy() throws {
        let regex = try NSRegularExpression(
            pattern: "\\b(demo|test|lorem|sample|example)\\b", options: .caseInsensitive)
        for email in DemoMailbox.threads(now: Date()).flatMap(\.messages) {
            for text in [email.subject, email.from, email.body] + email.to {
                let range = NSRange(text.startIndex..., in: text)
                XCTAssertNil(regex.firstMatch(in: text, range: range), text)
            }
        }
    }

    func testServiceServesMailboxWithoutNetwork() async throws {
        let service = DemoMailService()
        let threads = try await service.fetchInbox()
        XCTAssertFalse(threads.isEmpty)
        let first = try XCTUnwrap(threads.first?.messages.first)
        let fetched = try await service.fetchMessage(id: first.id)
        XCTAssertEqual(fetched.id, first.id)
    }
}
