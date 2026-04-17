import Foundation
import GRDB

public final class DatabaseManager {
    private let dbPool: DatabasePool
    private let fileStorageService: FileStorageService

    public var reader: DatabaseReader { dbPool }
    public var writer: DatabaseWriter { dbPool }

    public init(fileStorageService: FileStorageService) {
        self.fileStorageService = fileStorageService
        let dbURL = fileStorageService.databaseURL
        do {
            try FileManager.default.createDirectory(
                at: dbURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            var config = Configuration()
            config.foreignKeysEnabled = true
            config.prepareDatabase { db in
                db.trace { AppLogger.debug("SQL: \($0)") }
            }
            dbPool = try DatabasePool(path: dbURL.path, configuration: config)
            try runMigrations()
            AppLogger.info("Database initialized at \(dbURL.path)")
        } catch {
            fatalError("Database initialization failed: \(error)")
        }
    }

    private func runMigrations() throws {
        var migrator = DatabaseMigrator()
        migrator.eraseDatabaseOnSchemaChange = false

        migrator.registerMigration("v1_create_tables") { db in
            try db.create(table: "settings", ifNotExists: true) { t in
                t.column("key", .text).primaryKey()
                t.column("valueJson", .text).notNull()
                t.column("updatedAt", .datetime).notNull()
            }

            try db.create(table: "tags", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull().unique()
                t.column("colorHex", .text)
                t.column("priority", .integer).notNull().defaults(to: 0)
                t.column("isActive", .boolean).notNull().defaults(to: true)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }

            try db.create(table: "tag_aliases", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("tagId", .text).notNull()
                    .references("tags", onDelete: .cascade)
                t.column("alias", .text).notNull()
                t.column("createdAt", .datetime).notNull()
            }

            try db.create(table: "exclusion_rules", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("ruleType", .text).notNull()
                t.column("value", .text).notNull()
                t.column("isActive", .boolean).notNull().defaults(to: true)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }

            try db.create(table: "capture_jobs", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("scheduledAt", .datetime).notNull()
                t.column("executedAt", .datetime)
                t.column("status", .text).notNull()
                t.column("skipReason", .text)
                t.column("errorMessage", .text)
            }

            try db.create(table: "observations", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("captureJobId", .text).notNull()
                    .references("capture_jobs", onDelete: .cascade)
                t.column("capturedAt", .datetime).notNull()
                t.column("imagePath", .text)
                t.column("imageSha256", .text)
                t.column("imageWidth", .integer)
                t.column("imageHeight", .integer)
                t.column("frontmostApp", .text)
                t.column("frontmostBundleId", .text)
                t.column("frontmostWindowTitle", .text)
                t.column("displayId", .text)
                t.column("captureState", .text).notNull()
                t.column("rawVlmOutputJson", .text)
                t.column("aiSummary", .text)
                t.column("aiReason", .text)
                t.column("aiConfidence", .double)
                t.column("sensitivityFlag", .text)
                t.column("isUserHidden", .boolean).notNull().defaults(to: false)
                t.column("createdAt", .datetime).notNull()
            }

            try db.create(table: "observation_tags", ifNotExists: true) { t in
                t.column("observationId", .text).notNull()
                    .references("observations", onDelete: .cascade)
                t.column("tagId", .text).notNull()
                    .references("tags", onDelete: .cascade)
                t.column("score", .double).notNull()
                t.column("source", .text).notNull()
                t.primaryKey(["observationId", "tagId", "source"])
            }

            try db.create(table: "checkpoints", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("startAt", .datetime).notNull()
                t.column("endAt", .datetime).notNull()
                t.column("title", .text)
                t.column("summary", .text)
                t.column("confidence", .double)
                t.column("sourceObservationCount", .integer).notNull().defaults(to: 0)
                t.column("createdAt", .datetime).notNull()
            }

            try db.create(table: "checkpoint_tags", ifNotExists: true) { t in
                t.column("checkpointId", .text).notNull()
                    .references("checkpoints", onDelete: .cascade)
                t.column("tagId", .text).notNull()
                    .references("tags", onDelete: .cascade)
                t.column("score", .double).notNull()
                t.column("source", .text).notNull()
                t.primaryKey(["checkpointId", "tagId", "source"])
            }

            try db.create(table: "work_sessions", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("startAt", .datetime).notNull()
                t.column("endAt", .datetime).notNull()
                t.column("aiTitle", .text)
                t.column("finalTitle", .text)
                t.column("aiSummary", .text)
                t.column("finalNote", .text)
                t.column("aiConfidence", .double)
                t.column("status", .text).notNull()
                t.column("representativeImagePath", .text)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }

            try db.create(table: "work_session_tags", ifNotExists: true) { t in
                t.column("workSessionId", .text).notNull()
                    .references("work_sessions", onDelete: .cascade)
                t.column("tagId", .text).notNull()
                    .references("tags", onDelete: .cascade)
                t.column("source", .text).notNull()
                t.primaryKey(["workSessionId", "tagId", "source"])
            }

            try db.create(table: "session_observations", ifNotExists: true) { t in
                t.column("workSessionId", .text).notNull()
                    .references("work_sessions", onDelete: .cascade)
                t.column("observationId", .text).notNull()
                    .references("observations", onDelete: .cascade)
                t.primaryKey(["workSessionId", "observationId"])
            }

            try db.create(table: "exports", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("format", .text).notNull()
                t.column("targetPath", .text).notNull()
                t.column("requestedAt", .datetime).notNull()
                t.column("filterJson", .text)
            }

            try db.create(table: "audit_logs", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("eventType", .text).notNull()
                t.column("message", .text).notNull()
                t.column("payloadJson", .text)
                t.column("createdAt", .datetime).notNull()
            }
        }

        migrator.registerMigration("v1_create_indexes") { db in
            try db.create(
                index: "idx_observations_captured_at",
                on: "observations",
                columns: ["capturedAt"],
                ifNotExists: true
            )
            try db.create(
                index: "idx_observations_bundle_captured",
                on: "observations",
                columns: ["frontmostBundleId", "capturedAt"],
                ifNotExists: true
            )
            try db.create(
                index: "idx_work_sessions_time",
                on: "work_sessions",
                columns: ["startAt", "endAt"],
                ifNotExists: true
            )
            try db.create(
                index: "idx_observation_tags_tag",
                on: "observation_tags",
                columns: ["tagId"],
                ifNotExists: true
            )
            try db.create(
                index: "idx_work_session_tags_tag",
                on: "work_session_tags",
                columns: ["tagId"],
                ifNotExists: true
            )
            try db.create(
                index: "idx_capture_jobs_status",
                on: "capture_jobs",
                columns: ["status", "scheduledAt"],
                ifNotExists: true
            )
        }

        try migrator.migrate(dbPool)
    }
}
