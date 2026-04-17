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
        case export_
        case settings

        public var rawValue: String {
            switch self {
            case .capture: return "capture"
            case .inference: return "inference"
            case .export_: return "export"
            case .settings: return "settings"
            }
        }

        public init?(rawValue: String) {
            switch rawValue {
            case "capture": self = .capture
            case "inference": self = .inference
            case "export": self = .export_
            case "settings": self = .settings
            default: return nil
            }
        }
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
