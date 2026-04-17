import Foundation
import GRDB

public struct CaptureJob: Codable, Identifiable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "capture_jobs"

    public var id: String
    public var scheduledAt: Date
    public var executedAt: Date?
    public var status: Status
    public var skipReason: String?
    public var errorMessage: String?

    public enum Status: String, Codable {
        case queued
        case running
        case succeeded
        case skipped
        case failed
    }

    public enum Columns {
        static let id = Column(CodingKeys.id)
        static let status = Column(CodingKeys.status)
        static let scheduledAt = Column(CodingKeys.scheduledAt)
    }

    public init(id: String = UUID().uuidString, scheduledAt: Date = Date(),
         executedAt: Date? = nil, status: Status = .queued,
         skipReason: String? = nil, errorMessage: String? = nil) {
        self.id = id
        self.scheduledAt = scheduledAt
        self.executedAt = executedAt
        self.status = status
        self.skipReason = skipReason
        self.errorMessage = errorMessage
    }
}
