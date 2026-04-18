import Foundation
import GRDB

public final class DailyFeedbackRepository {
    private let databaseManager: DatabaseManager

    public init(databaseManager: DatabaseManager) {
        self.databaseManager = databaseManager
    }

    public func save(_ feedback: DailyFeedback) throws {
        try databaseManager.writer.write { db in
            try feedback.save(db)
        }
    }

    public func fetchForDate(_ date: Date) throws -> DailyFeedback? {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        return try databaseManager.reader.read { db in
            try DailyFeedback
                .filter(Column("date") >= start && Column("date") < end)
                .order(Column("updatedAt").desc, Column("createdAt").desc)
                .fetchOne(db)
        }
    }

    public func update(_ feedback: DailyFeedback) throws {
        try databaseManager.writer.write { db in
            var updated = feedback
            updated.updatedAt = Date()
            try updated.update(db)
        }
    }

    public func delete(id: String) throws {
        try databaseManager.writer.write { db in
            _ = try DailyFeedback.deleteOne(db, key: id)
        }
    }
}
