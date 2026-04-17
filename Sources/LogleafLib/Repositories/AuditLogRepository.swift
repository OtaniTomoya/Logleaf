import Foundation
import GRDB

public final class AuditLogRepository {
    private let databaseManager: DatabaseManager

    public init(databaseManager: DatabaseManager) {
        self.databaseManager = databaseManager
    }

    public func save(_ log: AuditLog) throws {
        try databaseManager.writer.write { db in
            try log.save(db)
        }
    }

    public func log(eventType: AuditLog.EventType, message: String, payload: [String: Any]? = nil) {
        do {
            var payloadJson: String?
            if let payload {
                let data = try JSONSerialization.data(withJSONObject: payload)
                payloadJson = String(data: data, encoding: .utf8)
            }
            let entry = AuditLog(eventType: eventType, message: message, payloadJson: payloadJson)
            try save(entry)
        } catch {
            AppLogger.error("Failed to write audit log: \(error)")
        }
    }

    public func fetchRecent(limit: Int = 100) throws -> [AuditLog] {
        try databaseManager.reader.read { db in
            try AuditLog
                .order(Column("createdAt").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }
}
