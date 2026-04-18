import Foundation
import GRDB

public struct DailyFeedback: Codable, Identifiable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "daily_feedbacks"

    public var id: String
    public var date: Date
    public var aiFeedback: String
    public var editedFeedback: String?
    public var createdAt: Date
    public var updatedAt: Date

    public var displayFeedback: String {
        editedFeedback ?? aiFeedback
    }

    public init(id: String = UUID().uuidString, date: Date,
                aiFeedback: String, editedFeedback: String? = nil,
                createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.date = date
        self.aiFeedback = aiFeedback
        self.editedFeedback = editedFeedback
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
