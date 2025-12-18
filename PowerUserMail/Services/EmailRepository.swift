//
//  EmailRepository.swift
//  PowerUserMail
//
//  Core Data repository for caching emails locally
//

import CoreData
import Foundation

/// Repository for managing cached emails in Core Data
final class EmailRepository {
    static let shared = EmailRepository()

    private let persistenceController: PersistenceController
    private var context: NSManagedObjectContext {
        persistenceController.container.viewContext
    }

    init(persistenceController: PersistenceController = .shared) {
        self.persistenceController = persistenceController
    }

    // MARK: - Thread Operations

    /// Save or update a thread and its messages
    func saveThread(_ thread: EmailThread, for accountEmail: String) throws {
        let fetchRequest: NSFetchRequest<ThreadEntity> = ThreadEntity.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", thread.id)

        let threadEntity: ThreadEntity
        if let existing = try context.fetch(fetchRequest).first {
            threadEntity = existing
        } else {
            threadEntity = ThreadEntity(context: context)
            threadEntity.id = thread.id
        }

        // Update thread properties
        threadEntity.subject = thread.subject
        threadEntity.participants = thread.participants
        threadEntity.isMuted = thread.isMuted

        // Save messages
        for message in thread.messages {
            try saveEmail(message, to: threadEntity, accountEmail: accountEmail)
        }

        try context.save()
    }

    /// Save or update an individual email
    private func saveEmail(_ email: Email, to thread: ThreadEntity, accountEmail: String) throws {
        let fetchRequest: NSFetchRequest<EmailEntity> = EmailEntity.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", email.id)

        let emailEntity: EmailEntity
        if let existing = try context.fetch(fetchRequest).first {
            emailEntity = existing
        } else {
            emailEntity = EmailEntity(context: context)
            emailEntity.id = email.id
        }

        // Update email properties
        emailEntity.threadId = email.threadId
        emailEntity.subject = email.subject
        emailEntity.from = email.from
        emailEntity.to = email.to
        emailEntity.cc = email.cc
        emailEntity.bcc = email.bcc
        emailEntity.preview = email.preview
        emailEntity.body = email.body
        emailEntity.receivedAt = email.receivedAt
        emailEntity.isRead = email.isRead
        emailEntity.isArchived = email.isArchived
        emailEntity.thread = thread

        // Save attachments
        for attachment in email.attachments {
            try saveAttachment(attachment, to: emailEntity)
        }
    }

    /// Save or update an attachment
    private func saveAttachment(_ attachment: EmailAttachment, to email: EmailEntity) throws {
        let fetchRequest: NSFetchRequest<AttachmentEntity> = AttachmentEntity.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", attachment.id.uuidString)

        let attachmentEntity: AttachmentEntity
        if let existing = try context.fetch(fetchRequest).first {
            attachmentEntity = existing
        } else {
            attachmentEntity = AttachmentEntity(context: context)
            attachmentEntity.id = attachment.id.uuidString
        }

        attachmentEntity.fileName = attachment.fileName
        attachmentEntity.mimeType = attachment.mimeType
        attachmentEntity.sizeInBytes = Int64(attachment.sizeInBytes)
        attachmentEntity.email = email
        // base64Data will be set separately when downloaded
    }

    /// Save attachment data in base64 format
    func saveAttachmentData(_ base64Data: String, for attachmentId: UUID) throws {
        let fetchRequest: NSFetchRequest<AttachmentEntity> = AttachmentEntity.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", attachmentId.uuidString)

        guard let attachment = try context.fetch(fetchRequest).first else {
            throw EmailRepositoryError.attachmentNotFound
        }

        attachment.base64Data = base64Data
        try context.save()
    }

    // MARK: - Fetch Operations

    /// Fetch all threads for an account
    func fetchThreads(for accountEmail: String) throws -> [EmailThread] {
        let fetchRequest: NSFetchRequest<ThreadEntity> = ThreadEntity.fetchRequest()
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "id", ascending: true)]

        let threadEntities = try context.fetch(fetchRequest)
        return threadEntities.compactMap { convertToThread($0) }
    }

    /// Fetch threads matching a search query
    func searchThreads(query: String, for accountEmail: String) throws -> [EmailThread] {
        let fetchRequest: NSFetchRequest<ThreadEntity> = ThreadEntity.fetchRequest()

        // Search in subject or participant emails
        let subjectPredicate = NSPredicate(format: "subject CONTAINS[cd] %@", query)
        let participantsPredicate = NSPredicate(format: "ANY participants CONTAINS[cd] %@", query)

        fetchRequest.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: [
            subjectPredicate, participantsPredicate,
        ])

        let threadEntities = try context.fetch(fetchRequest)
        return threadEntities.compactMap { convertToThread($0) }
    }

    /// Fetch threads received after a specific date
    func fetchThreads(after date: Date, for accountEmail: String) throws -> [EmailThread] {
        let fetchRequest: NSFetchRequest<ThreadEntity> = ThreadEntity.fetchRequest()

        // Find threads that have at least one message after the date
        let emailFetch: NSFetchRequest<EmailEntity> = EmailEntity.fetchRequest()
        emailFetch.predicate = NSPredicate(format: "receivedAt > %@", date as NSDate)

        let recentEmails = try context.fetch(emailFetch)
        let threadIds = Set(recentEmails.compactMap { $0.thread?.id })

        fetchRequest.predicate = NSPredicate(format: "id IN %@", threadIds)

        let threadEntities = try context.fetch(fetchRequest)
        return threadEntities.compactMap { convertToThread($0) }
    }

    /// Fetch a specific email by ID
    func fetchEmail(id: String) throws -> Email? {
        let fetchRequest: NSFetchRequest<EmailEntity> = EmailEntity.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", id)

        guard let emailEntity = try context.fetch(fetchRequest).first else {
            return nil
        }

        return convertToEmail(emailEntity)
    }

    // MARK: - Update Operations

    /// Mark email as read/unread
    func updateReadStatus(emailId: String, isRead: Bool) throws {
        let fetchRequest: NSFetchRequest<EmailEntity> = EmailEntity.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", emailId)

        guard let email = try context.fetch(fetchRequest).first else {
            throw EmailRepositoryError.emailNotFound
        }

        email.isRead = isRead
        try context.save()
    }

    /// Mark email as archived/unarchived
    func updateArchiveStatus(emailId: String, isArchived: Bool) throws {
        let fetchRequest: NSFetchRequest<EmailEntity> = EmailEntity.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", emailId)

        guard let email = try context.fetch(fetchRequest).first else {
            throw EmailRepositoryError.emailNotFound
        }

        email.isArchived = isArchived
        try context.save()
    }

    // MARK: - Sync State Management

    /// Get last sync date for an account
    func getLastSyncDate(for accountEmail: String) -> Date? {
        let fetchRequest: NSFetchRequest<SyncStateEntity> = SyncStateEntity.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "accountEmail == %@", accountEmail)

        guard let syncState = try? context.fetch(fetchRequest).first else {
            return nil
        }

        return syncState.lastSyncDate
    }

    /// Update last sync date for an account
    func updateLastSyncDate(_ date: Date, for accountEmail: String) throws {
        let fetchRequest: NSFetchRequest<SyncStateEntity> = SyncStateEntity.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "accountEmail == %@", accountEmail)

        let syncState: SyncStateEntity
        if let existing = try context.fetch(fetchRequest).first {
            syncState = existing
        } else {
            syncState = SyncStateEntity(context: context)
            syncState.accountEmail = accountEmail
        }

        syncState.lastSyncDate = date
        try context.save()
    }

    // MARK: - Delete Operations

    /// Delete all cached data for an account
    func clearCache(for accountEmail: String) throws {
        // Delete all threads (cascade will delete emails and attachments)
        let threadRequest: NSFetchRequest<NSFetchRequestResult> = ThreadEntity.fetchRequest()
        let deleteThreads = NSBatchDeleteRequest(fetchRequest: threadRequest)
        try context.execute(deleteThreads)

        // Delete sync state
        let syncRequest: NSFetchRequest<NSFetchRequestResult> = SyncStateEntity.fetchRequest()
        syncRequest.predicate = NSPredicate(format: "accountEmail == %@", accountEmail)
        let deleteSync = NSBatchDeleteRequest(fetchRequest: syncRequest)
        try context.execute(deleteSync)

        try context.save()
    }

    // MARK: - Conversion Helpers

    private func convertToThread(_ entity: ThreadEntity) -> EmailThread? {
        guard let id = entity.id,
            let subject = entity.subject,
            let participants = entity.participants as? [String]
        else {
            return nil
        }

        let messages =
            (entity.messages as? Set<EmailEntity>)?
            .compactMap { convertToEmail($0) }
            .sorted { $0.receivedAt < $1.receivedAt } ?? []

        return EmailThread(
            id: id,
            subject: subject,
            messages: messages,
            participants: participants,
            isMuted: entity.isMuted
        )
    }

    private func convertToEmail(_ entity: EmailEntity) -> Email? {
        guard let id = entity.id,
            let threadId = entity.threadId,
            let subject = entity.subject,
            let from = entity.from,
            let to = entity.to as? [String],
            let receivedAt = entity.receivedAt
        else {
            return nil
        }

        let cc = entity.cc as? [String] ?? []
        let bcc = entity.bcc as? [String] ?? []
        let preview = entity.preview ?? ""
        let body = entity.body ?? ""

        let attachments =
            (entity.attachments as? Set<AttachmentEntity>)?
            .compactMap { convertToAttachment($0) } ?? []

        return Email(
            id: id,
            threadId: threadId,
            subject: subject,
            from: from,
            to: to,
            cc: cc,
            bcc: bcc,
            preview: preview,
            body: body,
            receivedAt: receivedAt,
            isRead: entity.isRead,
            isArchived: entity.isArchived,
            attachments: attachments
        )
    }

    private func convertToAttachment(_ entity: AttachmentEntity) -> EmailAttachment? {
        guard let id = entity.id,
            let fileName = entity.fileName,
            let mimeType = entity.mimeType,
            let uuid = UUID(uuidString: id)
        else {
            return nil
        }

        return EmailAttachment(
            id: uuid,
            fileName: fileName,
            mimeType: mimeType,
            sizeInBytes: Int(entity.sizeInBytes)
        )
    }

    /// Get attachment base64 data
    func getAttachmentData(for attachmentId: UUID) throws -> String? {
        let fetchRequest: NSFetchRequest<AttachmentEntity> = AttachmentEntity.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", attachmentId.uuidString)

        guard let attachment = try context.fetch(fetchRequest).first else {
            return nil
        }

        return attachment.base64Data
    }
}

// MARK: - Errors

enum EmailRepositoryError: Error, LocalizedError {
    case emailNotFound
    case threadNotFound
    case attachmentNotFound
    case saveFailed(Error)

    var errorDescription: String? {
        switch self {
        case .emailNotFound:
            return "Email not found in cache"
        case .threadNotFound:
            return "Thread not found in cache"
        case .attachmentNotFound:
            return "Attachment not found in cache"
        case .saveFailed(let error):
            return "Failed to save to cache: \(error.localizedDescription)"
        }
    }
}
