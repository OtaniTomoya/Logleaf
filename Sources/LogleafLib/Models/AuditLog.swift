import Foundation
import GRDB

public struct AuditLog: Codable, Identifiable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "audit_logs"

    public var id: String
    public var eventType: EventType
    public var message: String
    public var payloadJson: String?
    public var createdAt: Date

    public enum EventType: String, Codable {
        case capture
        case inference
        case settings
    }

    public init(id: String = UUID().uuidString, eventType: EventType,
         message: String, payloadJson: String? = nil, createdAt: Date = Date()) {
        self.id = id
        self.eventType = eventType
        self.message = message
        self.payloadJson = payloadJson
        self.createdAt = createdAt
    }
}
