import Foundation
import GRDB

public final class CheckpointRepository {
    private let databaseManager: DatabaseManager

    public init(databaseManager: DatabaseManager) {
        self.databaseManager = databaseManager
    }

    public func save(_ checkpoint: Checkpoint) throws {
        try databaseManager.writer.write { db in
            try checkpoint.save(db)
        }
    }

    public func fetchByDateRange(start: Date, end: Date) throws -> [Checkpoint] {
        try databaseManager.reader.read { db in
            try Checkpoint
                .filter(Column("startAt") >= start && Column("endAt") <= end)
                .order(Column("startAt").asc)
                .fetchAll(db)
        }
    }

    public func saveTags(_ tags: [CheckpointTag]) throws {
        try databaseManager.writer.write { db in
            for tag in tags {
                try tag.save(db)
            }
        }
    }

    public func deleteByDateRange(start: Date, end: Date) throws {
        try databaseManager.writer.write { db in
            try Checkpoint
                .filter(Column("startAt") >= start && Column("endAt") <= end)
                .deleteAll(db)
        }
    }
}
