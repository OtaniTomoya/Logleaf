import Foundation
import GRDB

public struct WorkSession: Codable, Identifiable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "work_sessions"

    public var id: String
    public var startAt: Date
    public var endAt: Date
    public var aiTitle: String?
    public var finalTitle: String?
    public var aiSummary: String?
    public var finalNote: String?
    public var status: Status
    public var representativeImagePath: String?
    public var createdAt: Date
    public var updatedAt: Date

    public enum Status: String, Codable {
        case draft
        case confirmed
        case edited
        case deleted
    }

    public enum Columns {
        public static let id = Column(CodingKeys.id)
        public static let startAt = Column(CodingKeys.startAt)
        public static let endAt = Column(CodingKeys.endAt)
        public static let status = Column(CodingKeys.status)
    }

    public var displayTitle: String {
        finalTitle ?? aiTitle ?? "未分類"
    }

    public var durationMinutes: Int {
        Int(endAt.timeIntervalSince(startAt) / 60)
    }

    public init(id: String = UUID().uuidString, startAt: Date, endAt: Date,
         aiTitle: String? = nil, finalTitle: String? = nil,
         aiSummary: String? = nil, finalNote: String? = nil,
         status: Status = .confirmed,
         representativeImagePath: String? = nil,
         createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.startAt = startAt
        self.endAt = endAt
        self.aiTitle = aiTitle
        self.finalTitle = finalTitle
        self.aiSummary = aiSummary
        self.finalNote = finalNote
        self.status = status
        self.representativeImagePath = representativeImagePath
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct WorkSessionTag: Codable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "work_session_tags"

    public var workSessionId: String
    public var tagId: String
    public var source: ObservationTag.TagSource

    public init(workSessionId: String, tagId: String, source: ObservationTag.TagSource) {
        self.workSessionId = workSessionId
        self.tagId = tagId
        self.source = source
    }
}

public struct SessionObservation: Codable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "session_observations"

    public var workSessionId: String
    public var observationId: String

    public init(workSessionId: String, observationId: String) {
        self.workSessionId = workSessionId
        self.observationId = observationId
    }
}
