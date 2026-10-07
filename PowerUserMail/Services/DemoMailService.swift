//
//  DemoMailService.swift
//  PowerUserMail
//
//  Offline sample mailbox for screenshots and UI work.
//  Launch with PUM_DEMO=1 (see scripts/screenshots.sh). In this mode the app
//  never reads saved accounts, never touches the keychain or the network,
//  keeps its mail cache in memory and sends no notifications.
//

import AppKit
import Foundation

enum DemoMode {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["PUM_DEMO"] == "1"
    }

    /// Optional PUM_DEMO_THEME=light|dark to force an appearance for captures.
    static var theme: AppTheme? {
        ProcessInfo.processInfo.environment["PUM_DEMO_THEME"].flatMap(AppTheme.init(rawValue:))
    }

    static let account = Account(
        id: UUID(uuidString: "6F1D2C3B-4A59-4E8F-9D27-5C0B8E1A7F42")!,
        provider: .gmail,
        emailAddress: DemoMailbox.me,
        displayName: "Alex Morgan",
        accessToken: "",
        isAuthenticated: true
    )

    /// Size the window (PUM_DEMO_WINDOW=WIDTHxHEIGHT, default 1280x800) and set up the
    /// view to capture, so scripts/screenshots.sh never has to click or type:
    /// PUM_DEMO_FILTER=all|unread|archived, PUM_DEMO_OPEN=<sender name>, PUM_DEMO_PALETTE=1.
    static func prepareWindow() {
        let env = ProcessInfo.processInfo.environment
        let parts = (env["PUM_DEMO_WINDOW"] ?? "").split(separator: "x").compactMap { Double($0) }
        let size =
            parts.count == 2
            ? NSSize(width: parts[0], height: parts[1]) : NSSize(width: 1280, height: 800)

        func post(_ name: String, _ info: [String: String]? = nil) {
            NotificationCenter.default.post(name: Notification.Name(name), object: nil, userInfo: info)
        }

        for delay in [0.3, 1.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                NSApp.activate(ignoringOtherApps: true)
                for window in NSApp.windows where window.isVisible {
                    window.setContentSize(size)
                    window.center()
                    window.makeKeyAndOrderFront(nil)
                }
            }
        }

        // Give the inbox a moment to load before changing what is on screen
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            switch env["PUM_DEMO_FILTER"] {
            case "unread": post("InboxFilter1")
            case "all": post("InboxFilter2")
            case "archived": post("InboxFilter3")
            default: break
            }
            if let person = env["PUM_DEMO_OPEN"] {
                post("OpenConversation", ["from": person])
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if env["PUM_DEMO_PALETTE"] == "1" { post("ToggleCommandPalette") }
        }

        // PUM_DEMO_CAPTURE=<file.png>: the app draws its own window into a PNG and quits.
        // Needs a build without the sandbox (scripts/screenshots.sh does that).
        if let path = env["PUM_DEMO_CAPTURE"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
                if let frame = NSApp.windows.first(where: \.isVisible)?.contentView?.superview,
                    let rep = frame.bitmapImageRepForCachingDisplay(in: frame.bounds)
                {
                    frame.cacheDisplay(in: frame.bounds, to: rep)
                    try? rep.representation(using: .png, properties: [:])?
                        .write(to: URL(fileURLWithPath: path))
                }
                NSApp.terminate(nil)
            }
        }
    }
}

final class DemoMailService: MailService {
    let provider: MailProvider = .gmail
    private(set) var account: Account? = DemoMode.account
    var isAuthenticated: Bool { true }

    private var sent: [Email] = []

    func authenticate() async throws -> Account { DemoMode.account }

    func restoreAccount(_ account: Account) {}

    func fetchInbox() async throws -> [EmailThread] {
        DemoMailbox.threads(now: Date()) + sent.map {
            EmailThread(id: $0.threadId, subject: $0.subject, messages: [$0], participants: $0.to)
        }
    }

    func fetchInboxStream() -> AsyncThrowingStream<EmailThread, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    for thread in try await self.fetchInbox() {
                        continuation.yield(thread)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    func fetchMessage(id: String) async throws -> Email {
        let all = try await fetchInbox().flatMap(\.messages)
        guard let email = all.first(where: { $0.id == id }) else {
            throw MailServiceError.invalidResponse
        }
        return email
    }

    func send(message: DraftMessage) async throws {
        let id = UUID().uuidString
        sent.append(
            Email(
                id: id, threadId: "sent-\(id)", subject: message.subject,
                from: DemoMailbox.meFull, to: message.to, preview: message.body,
                body: message.body, receivedAt: Date(), isRead: true))
    }

    func archive(id: String) async throws {}
}

/// The sample inbox. Times are relative to launch so the list always reads "just now / 12 min ago".
enum DemoMailbox {
    static let me = "alex@fieldwork.studio"
    static let meFull = "Alex Morgan <alex@fieldwork.studio>"

    private static let lena = "Lena Hoffmann <lena@fieldwork.studio>"
    private static let jonas = "Jonas Weber <jonas@fieldwork.studio>"
    private static let github = "GitHub <notifications@github.com>"
    private static let calendar = "Google Calendar <calendar-notification@google.com>"
    private static let figma = "Figma <no-reply@figma.com>"
    private static let newsletter = "Off by One <hello@offbyone.news>"
    private static let apple = "Apple <no_reply@email.apple.com>"
    private static let stripe = "Stripe <notifications@stripe.com>"
    private static let mara = "Mara Okafor <mara@okafor.design>"
    private static let sbb = "SBB CFF FFS <noreply@sbb.ch>"

    static func threads(now: Date) -> [EmailThread] {
        func ago(_ minutes: Double) -> Date { now.addingTimeInterval(-minutes * 60) }

        func mail(
            _ id: String, thread: String, from: String, to: String = meFull, subject: String,
            _ body: String, at date: Date, read: Bool
        ) -> Email {
            let preview = body.split(separator: "\n").first.map(String.init) ?? body
            return Email(
                id: id, threadId: thread, subject: subject, from: from, to: [to],
                preview: preview, body: body, receivedAt: date, isRead: read)
        }

        let launch = "Launch checklist for Thursday"
        let messages: [Email] = [
            // A real back-and-forth with a colleague
            mail(
                "lena-1", thread: "launch", from: lena, subject: launch,
                "Hey Alex, the launch checklist is in the shared doc now.\nCould you take the release notes and the App Store screenshots? I'll do the blog post and the newsletter.",
                at: ago(26 * 60), read: true),
            mail(
                "alex-1", thread: "launch", from: meFull, to: lena, subject: "Re: \(launch)",
                "Sure, release notes are yours by tomorrow noon.\nDo we ship 2.4 as planned or wait for the sync fix?",
                at: ago(25 * 60 + 40), read: true),
            mail(
                "lena-2", thread: "launch", from: lena, subject: "Re: \(launch)",
                "Let's ship 2.4. The sync fix goes into 2.4.1 next week, Jonas already has it up for review.",
                at: ago(38), read: true),
            mail(
                "lena-3", thread: "launch", from: lena, subject: "Re: \(launch)",
                "Also: can we move the launch call to 15:00? Marketing has a conflict at 14:00.",
                at: ago(12), read: false),

            mail(
                "gh-1", thread: "gh-482", from: github,
                subject: "[fieldwork/atlas] Fix race condition in sync queue (#482)",
                "@jonasweber requested your review on #482: Fix race condition in sync queue.",
                at: ago(4), read: false),
            mail(
                "gh-0", thread: "gh-479", from: github,
                subject: "[fieldwork/atlas] Release 2.4.0-rc.2",
                "All 12 checks have passed on main. Ready to publish.",
                at: ago(3 * 60), read: true),

            mail(
                "jonas-1", thread: "sync-fix", from: jonas, subject: "Sync fix is ready for review",
                "PR #482 is up. The flaky CI run was a timing issue in the queue, not the network layer.\nWould love your eyes on it before we cut 2.4.1.",
                at: ago(9), read: false),

            mail(
                "cal-1", thread: "design-review", from: calendar,
                subject: "Invitation: Design review @ Thu 10:00 – 11:00 (CEST)",
                "Lena Hoffmann has invited you to Design review.\nThursday 10:00 – 11:00, Room Zug / Google Meet.\nYes · Maybe · No",
                at: ago(52), read: false),

            mail(
                "figma-1", thread: "figma-atlas", from: figma,
                subject: "Lena commented on Atlas 2.4 — App Store",
                "\"Love the new inbox shot. Can we try the dark one as the first slide?\"",
                at: ago(95), read: false),

            mail(
                "mara-1", thread: "coffee", from: mara, subject: "Coffee next week?",
                "Back in Zürich from Tuesday. Coffee at Kafi Dihei on Wednesday morning?",
                at: ago(4 * 60), read: true),

            mail(
                "stripe-1", thread: "payout", from: stripe,
                subject: "Your payout of CHF 4,180.00 is on the way",
                "Your payout of CHF 4,180.00 to the account ending in 0421 should arrive by Friday.",
                at: ago(7 * 60), read: true),

            mail(
                "news-1", thread: "obo-112", from: newsletter,
                subject: "Issue #112: The quiet comeback of native apps",
                "This week: why teams are leaving Electron, a 40-line command palette in SwiftUI, and the keyboard shortcuts nobody uses.",
                at: ago(20 * 60), read: true),

            mail(
                "sbb-1", thread: "ticket", from: sbb,
                subject: "Your ticket: Zürich HB → Bern",
                "Thursday, IC 1 08:02 from Zürich HB, arrival Bern 08:58. Your ticket is in the app.",
                at: ago(30 * 60), read: true),

            mail(
                "apple-1", thread: "receipt", from: apple, subject: "Your receipt from Apple",
                "iCloud+ with 200 GB storage, monthly. CHF 2.90",
                at: ago(2 * 24 * 60), read: true),
        ]

        return Dictionary(grouping: messages, by: \.threadId).map { id, msgs in
            let sorted = msgs.sorted { $0.receivedAt < $1.receivedAt }
            return EmailThread(
                id: id, subject: sorted.first?.subject ?? "", messages: sorted,
                participants: Array(Set(sorted.flatMap { [$0.from] + $0.to })))
        }
    }
}
