import Foundation
import GRDB

public struct Tag: Codable, Identifiable, Equatable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "tags"

    public var id: String
    public var name: String
    public var colorHex: String?
    public var tagDescription: String?
    public var isActive: Bool
    public var createdAt: Date
    public var updatedAt: Date

    public enum Columns {
        public static let id = Column(CodingKeys.id)
        public static let name = Column(CodingKeys.name)
        public static let colorHex = Column(CodingKeys.colorHex)
        public static let tagDescription = Column(CodingKeys.tagDescription)
        public static let isActive = Column(CodingKeys.isActive)
        public static let createdAt = Column(CodingKeys.createdAt)
        public static let updatedAt = Column(CodingKeys.updatedAt)
    }

    enum CodingKeys: String, CodingKey {
        case id, name, colorHex
        case tagDescription = "description"
        case isActive, createdAt, updatedAt
    }

    public init(id: String = UUID().uuidString, name: String, colorHex: String? = nil,
         tagDescription: String? = nil, isActive: Bool = true,
         createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.tagDescription = tagDescription
        self.isActive = isActive
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct TagAlias: Codable, Identifiable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "tag_aliases"

    public var id: String
    public var tagId: String
    public var alias: String
    public var createdAt: Date

    public init(id: String = UUID().uuidString, tagId: String, alias: String, createdAt: Date = Date()) {
        self.id = id
        self.tagId = tagId
        self.alias = alias
        self.createdAt = createdAt
    }
}
