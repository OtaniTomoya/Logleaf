import Foundation
import GRDB

public final class ExclusionRuleRepository {
    private let databaseManager: DatabaseManager

    public init(databaseManager: DatabaseManager) {
        self.databaseManager = databaseManager
    }

    public func fetchAll() throws -> [ExclusionRule] {
        try databaseManager.reader.read { db in
            try ExclusionRule.fetchAll(db)
        }
    }

    public func fetchActive() throws -> [ExclusionRule] {
        try databaseManager.reader.read { db in
            try ExclusionRule.filter(ExclusionRule.Columns.isActive == true).fetchAll(db)
        }
    }

    public func save(_ rule: ExclusionRule) throws {
        try databaseManager.writer.write { db in
            try rule.save(db)
        }
    }

    public func delete(id: String) throws {
        try databaseManager.writer.write { db in
            _ = try ExclusionRule.deleteOne(db, key: id)
        }
    }
}
