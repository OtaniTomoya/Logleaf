import Foundation
import GRDB

public struct Checkpoint: Codable, Identifiable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "checkpoints"

    public var id: String
    public var startAt: Date
    public var endAt: Date
    public var title: String?
    public var summary: String?
    public var confidence: Double?
    public var sourceObservationCount: Int
    public var createdAt: Date

    public init(id: String = UUID().uuidString, startAt: Date, endAt: Date,
         title: String? = nil, summary: String? = nil,
         confidence: Double? = nil, sourceObservationCount: Int = 0,
         createdAt: Date = Date()) {
        self.id = id
        self.startAt = startAt
        self.endAt = endAt
        self.title = title
        self.summary = summary
        self.confidence = confidence
        self.sourceObservationCount = sourceObservationCount
        self.createdAt = createdAt
    }
}

public struct CheckpointTag: Codable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "checkpoint_tags"

    public var checkpointId: String
    public var tagId: String
    public var score: Double
    public var source: ObservationTag.TagSource

    public init(checkpointId: String, tagId: String, score: Double, source: ObservationTag.TagSource) {
        self.checkpointId = checkpointId
        self.tagId = tagId
        self.score = score
        self.source = source
    }
}
