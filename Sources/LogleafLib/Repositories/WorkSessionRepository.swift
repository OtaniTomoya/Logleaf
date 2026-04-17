import Foundation
import GRDB

public final class WorkSessionRepository {
    private let databaseManager: DatabaseManager

    public init(databaseManager: DatabaseManager) {
        self.databaseManager = databaseManager
    }

    public func save(_ session: WorkSession) throws {
        try databaseManager.writer.write { db in
            try session.save(db)
        }
    }

    public func fetch(id: String) throws -> WorkSession? {
        try databaseManager.reader.read { db in
            try WorkSession.fetchOne(db, key: id)
        }
    }

    public func fetchForDate(_ date: Date) throws -> [WorkSession] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        return try databaseManager.reader.read { db in
            try WorkSession
                .filter(WorkSession.Columns.startAt >= start && WorkSession.Columns.startAt < end)
                .filter(WorkSession.Columns.status != WorkSession.Status.deleted.rawValue)
                .order(WorkSession.Columns.startAt.asc)
                .fetchAll(db)
        }
    }

    public func fetchByDateRange(start: Date, end: Date) throws -> [WorkSession] {
        try databaseManager.reader.read { db in
            try WorkSession
                .filter(WorkSession.Columns.startAt >= start && WorkSession.Columns.endAt <= end)
                .filter(WorkSession.Columns.status != WorkSession.Status.deleted.rawValue)
                .order(WorkSession.Columns.startAt.asc)
                .fetchAll(db)
        }
    }

    public func update(_ session: WorkSession) throws {
        try databaseManager.writer.write { db in
            var updated = session
            updated.updatedAt = Date()
            try updated.update(db)
        }
    }

    public func delete(id: String) throws {
        try databaseManager.writer.write { db in
            if var session = try WorkSession.fetchOne(db, key: id) {
                session.status = .deleted
                session.updatedAt = Date()
                try session.update(db)
            }
        }
    }

    public func saveTags(_ tags: [WorkSessionTag]) throws {
        try databaseManager.writer.write { db in
            for tag in tags {
                try tag.save(db)
            }
        }
    }

    public func fetchTags(sessionId: String) throws -> [WorkSessionTag] {
        try databaseManager.reader.read { db in
            try WorkSessionTag
                .filter(Column("workSessionId") == sessionId)
                .fetchAll(db)
        }
    }

    public func deleteTagsForSession(_ sessionId: String, source: ObservationTag.TagSource) throws {
        try databaseManager.writer.write { db in
            try db.execute(
                sql: "DELETE FROM work_session_tags WHERE workSessionId = ? AND source = ?",
                arguments: [sessionId, source.rawValue]
            )
        }
    }

    public func saveSessionObservation(_ link: SessionObservation) throws {
        try databaseManager.writer.write { db in
            try link.save(db)
        }
    }

    public func fetchObservationIds(sessionId: String) throws -> [String] {
        try databaseManager.reader.read { db in
            try SessionObservation
                .filter(Column("workSessionId") == sessionId)
                .fetchAll(db)
                .map(\.observationId)
        }
    }

    public func deleteByDateRange(start: Date, end: Date) throws {
        _ = try databaseManager.writer.write { db in
            try WorkSession
                .filter(WorkSession.Columns.startAt >= start && WorkSession.Columns.endAt <= end)
                .deleteAll(db)
        }
    }

    public func hardDelete(ids: [String]) throws {
        guard !ids.isEmpty else { return }
        _ = try databaseManager.writer.write { db in
            try WorkSession
                .filter(ids.contains(WorkSession.Columns.id))
                .deleteAll(db)
        }
    }

    public func countUnconfirmed() throws -> Int {
        try databaseManager.reader.read { db in
            try WorkSession
                .filter(WorkSession.Columns.status == WorkSession.Status.draft.rawValue)
                .fetchCount(db)
        }
    }

    public func totalMinutesForDate(_ date: Date) throws -> Int {
        let sessions = try fetchForDate(date)
        return sessions.reduce(0) { $0 + $1.durationMinutes }
    }
}
