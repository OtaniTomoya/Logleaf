import Foundation
import GRDB

public final class CaptureJobRepository {
    private let databaseManager: DatabaseManager

    public init(databaseManager: DatabaseManager) {
        self.databaseManager = databaseManager
    }

    public func save(_ job: CaptureJob) throws {
        try databaseManager.writer.write { db in
            try job.save(db)
        }
    }

    public func update(id: String, status: CaptureJob.Status, executedAt: Date? = nil,
                errorMessage: String? = nil, skipReason: String? = nil) throws {
        try databaseManager.writer.write { db in
            if var job = try CaptureJob.fetchOne(db, key: id) {
                job.status = status
                job.executedAt = executedAt
                job.errorMessage = errorMessage
                job.skipReason = skipReason
                try job.update(db)
            }
        }
    }

    public func fetchPending() throws -> [CaptureJob] {
        try databaseManager.reader.read { db in
            try CaptureJob
                .filter(CaptureJob.Columns.status == CaptureJob.Status.queued.rawValue)
                .order(CaptureJob.Columns.scheduledAt.asc)
                .fetchAll(db)
        }
    }
}
