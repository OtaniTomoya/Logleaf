import Foundation
import GRDB

public struct ExclusionRule: Codable, Identifiable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "exclusion_rules"

    public var id: String
    public var ruleType: RuleType
    public var value: String
    public var isActive: Bool
    public var createdAt: Date
    public var updatedAt: Date

    public enum RuleType: String, Codable, CaseIterable {
        case app
        case windowTitle = "window_title"
        case timeRange = "time_range"
        case manual
    }

    public enum Columns {
        static let id = Column(CodingKeys.id)
        static let ruleType = Column(CodingKeys.ruleType)
        static let value = Column(CodingKeys.value)
        static let isActive = Column(CodingKeys.isActive)
    }

    public init(id: String = UUID().uuidString, ruleType: RuleType, value: String,
         isActive: Bool = true, createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.ruleType = ruleType
        self.value = value
        self.isActive = isActive
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
