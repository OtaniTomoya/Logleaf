import Foundation
import GRDB

public final class TagRepository {
    private let databaseManager: DatabaseManager

    public init(databaseManager: DatabaseManager) {
        self.databaseManager = databaseManager
    }

    public func fetchAll() throws -> [Tag] {
        try databaseManager.reader.read { db in
            try Tag.order(Tag.Columns.priority.asc).fetchAll(db)
        }
    }

    public func fetchActive() throws -> [Tag] {
        try databaseManager.reader.read { db in
            try Tag.filter(Tag.Columns.isActive == true)
                .order(Tag.Columns.priority.asc)
                .fetchAll(db)
        }
    }

    public func fetch(id: String) throws -> Tag? {
        try databaseManager.reader.read { db in
            try Tag.fetchOne(db, key: id)
        }
    }

    public func save(_ tag: Tag) throws {
        try databaseManager.writer.write { db in
            try tag.save(db)
        }
    }

    public func delete(id: String) throws {
        try databaseManager.writer.write { db in
            _ = try Tag.deleteOne(db, key: id)
        }
    }

    public func fetchAliases(tagId: String) throws -> [TagAlias] {
        try databaseManager.reader.read { db in
            try TagAlias.filter(Column("tagId") == tagId).fetchAll(db)
        }
    }

    public func saveAlias(_ alias: TagAlias) throws {
        try databaseManager.writer.write { db in
            try alias.save(db)
        }
    }

    public func deleteAlias(id: String) throws {
        try databaseManager.writer.write { db in
            _ = try TagAlias.deleteOne(db, key: id)
        }
    }

    public func mergeTags(sourceIds: [String], targetId: String) throws {
        try databaseManager.writer.write { db in
            // Update observation_tags
            for sourceId in sourceIds {
                try db.execute(
                    sql: """
                    UPDATE observation_tags SET tagId = ? WHERE tagId = ?
                    AND NOT EXISTS (
                        SELECT 1 FROM observation_tags ot2
                        WHERE ot2.observationId = observation_tags.observationId
                        AND ot2.tagId = ? AND ot2.source = observation_tags.source
                    )
                    """,
                    arguments: [targetId, sourceId, targetId]
                )
                try db.execute(
                    sql: "DELETE FROM observation_tags WHERE tagId = ?",
                    arguments: [sourceId]
                )
            }
            // Update work_session_tags
            for sourceId in sourceIds {
                try db.execute(
                    sql: """
                    UPDATE work_session_tags SET tagId = ? WHERE tagId = ?
                    AND NOT EXISTS (
                        SELECT 1 FROM work_session_tags wst2
                        WHERE wst2.workSessionId = work_session_tags.workSessionId
                        AND wst2.tagId = ? AND wst2.source = work_session_tags.source
                    )
                    """,
                    arguments: [targetId, sourceId, targetId]
                )
                try db.execute(
                    sql: "DELETE FROM work_session_tags WHERE tagId = ?",
                    arguments: [sourceId]
                )
            }
            // Delete source tags
            for sourceId in sourceIds {
                _ = try Tag.deleteOne(db, key: sourceId)
            }
        }
    }
}
