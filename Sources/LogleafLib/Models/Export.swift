import Foundation
import GRDB

public struct ExportRecord: Codable, Identifiable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "exports"

    public var id: String
    public var format: ExportFormat
    public var targetPath: String
    public var requestedAt: Date
    public var filterJson: String?

    public enum ExportFormat: String, Codable {
        case csv
        case markdown
        case json
    }

    public init(id: String = UUID().uuidString, format: ExportFormat,
         targetPath: String, requestedAt: Date = Date(), filterJson: String? = nil) {
        self.id = id
        self.format = format
        self.targetPath = targetPath
        self.requestedAt = requestedAt
        self.filterJson = filterJson
    }
}

public struct ExportFilter: Codable {
    public var startDate: Date?
    public var endDate: Date?
    public var tagIds: [String]?
    public var includeUnclassified: Bool
    public var includeScreenshots: Bool

    public init(startDate: Date? = nil, endDate: Date? = nil, tagIds: [String]? = nil,
         includeUnclassified: Bool = true, includeScreenshots: Bool = false) {
        self.startDate = startDate
        self.endDate = endDate
        self.tagIds = tagIds
        self.includeUnclassified = includeUnclassified
        self.includeScreenshots = includeScreenshots
    }
}
