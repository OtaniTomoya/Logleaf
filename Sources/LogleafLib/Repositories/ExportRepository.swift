import Foundation
import GRDB

public final class ExportRepository {
    private let databaseManager: DatabaseManager

    public init(databaseManager: DatabaseManager) {
        self.databaseManager = databaseManager
    }

    public func save(_ record: ExportRecord) throws {
        try databaseManager.writer.write { db in
            try record.save(db)
        }
    }

    public func fetchAll() throws -> [ExportRecord] {
        try databaseManager.reader.read { db in
            try ExportRecord.order(Column("requestedAt").desc).fetchAll(db)
        }
    }
}
