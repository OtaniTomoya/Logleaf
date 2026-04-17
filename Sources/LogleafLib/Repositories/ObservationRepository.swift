import Foundation
import GRDB

public final class ObservationRepository {
    private let databaseManager: DatabaseManager

    public init(databaseManager: DatabaseManager) {
        self.databaseManager = databaseManager
    }

    public func save(_ observation: Observation) throws {
        try databaseManager.writer.write { db in
            try observation.save(db)
        }
    }

    public func fetch(id: String) throws -> Observation? {
        try databaseManager.reader.read { db in
            try Observation.fetchOne(db, key: id)
        }
    }

    public func fetchByDateRange(start: Date, end: Date) throws -> [Observation] {
        try databaseManager.reader.read { db in
            try Observation
                .filter(Observation.Columns.capturedAt >= start && Observation.Columns.capturedAt < end)
                .order(Observation.Columns.capturedAt.asc)
                .fetchAll(db)
        }
    }

    public func fetchForDate(_ date: Date) throws -> [Observation] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        return try fetchByDateRange(start: start, end: end)
    }

    public func update(_ observation: Observation) throws {
        try databaseManager.writer.write { db in
            try observation.update(db)
        }
    }

    public func delete(id: String) throws {
        try databaseManager.writer.write { db in
            _ = try Observation.deleteOne(db, key: id)
        }
    }

    public func saveTags(_ tags: [ObservationTag]) throws {
        try databaseManager.writer.write { db in
            for tag in tags {
                try tag.save(db)
            }
        }
    }

    public func fetchTags(observationId: String) throws -> [ObservationTag] {
        try databaseManager.reader.read { db in
            try ObservationTag
                .filter(Column("observationId") == observationId)
                .fetchAll(db)
        }
    }

    public func deleteTagsForObservation(_ observationId: String, source: ObservationTag.TagSource) throws {
        try databaseManager.writer.write { db in
            try db.execute(
                sql: "DELETE FROM observation_tags WHERE observationId = ? AND source = ?",
                arguments: [observationId, source.rawValue]
            )
        }
    }

    public func updateInferenceResult(observationId: String, result: InferenceResult) throws {
        try databaseManager.writer.write { db in
            if var obs = try Observation.fetchOne(db, key: observationId) {
                obs.rawVlmOutputJson = result.rawJson
                obs.aiSummary = result.activitySummary
                obs.aiReason = result.reason
                obs.aiConfidence = result.confidence
                obs.sensitivityFlag = Observation.SensitivityFlag(rawValue: result.sensitivityFlag)
                try obs.update(db)
            }
        }
    }

    public func clearImageReference(observationId: String) throws {
        try databaseManager.writer.write { db in
            if var obs = try Observation.fetchOne(db, key: observationId) {
                obs.imagePath = nil
                obs.imageSha256 = nil
                try obs.update(db)
            }
        }
    }

    public func countByDate(_ date: Date) throws -> Int {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        return try databaseManager.reader.read { db in
            try Observation
                .filter(Observation.Columns.capturedAt >= start && Observation.Columns.capturedAt < end)
                .fetchCount(db)
        }
    }

    public func deleteOlderThan(_ date: Date) throws -> Int {
        try databaseManager.writer.write { db in
            try Observation
                .filter(Observation.Columns.capturedAt < date)
                .deleteAll(db)
        }
    }
}
