import Foundation
import GRDB

public struct SettingEntry: Codable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "settings"

    public var key: String
    public var valueJson: String
    public var updatedAt: Date

    public init(key: String, valueJson: String, updatedAt: Date = Date()) {
        self.key = key
        self.valueJson = valueJson
        self.updatedAt = updatedAt
    }
}

public struct AppSettings {
    public var captureIntervalSeconds: Int = 60
    public var checkpointIntervalMinutes: Int = 5
    public var ollamaHost: String = "http://localhost:11434"
    public var ollamaModel: String = "gemma4:e4b"
    public var retentionDays: Int = 30
    public var autoDeleteEnabled: Bool = true
    public var logLevel: LogLevel = .info

    public enum LogLevel: String, Codable {
        case debug
        case info
        case warning
        case error
    }

    public init() {}
}

public struct FrontmostContext {
    public var appName: String?
    public var bundleId: String?
    public var windowTitle: String?

    public init(appName: String? = nil, bundleId: String? = nil, windowTitle: String? = nil) {
        self.appName = appName
        self.bundleId = bundleId
        self.windowTitle = windowTitle
    }
}

public struct CapturedFrame {
    public var imageURL: URL
    public var capturedAt: Date
    public var displayID: String
    public var width: Int
    public var height: Int
    public var frontmostApp: String?
    public var frontmostBundleId: String?
    public var frontmostWindowTitle: String?

    public init(imageURL: URL, capturedAt: Date, displayID: String, width: Int, height: Int,
                frontmostApp: String? = nil, frontmostBundleId: String? = nil, frontmostWindowTitle: String? = nil) {
        self.imageURL = imageURL
        self.capturedAt = capturedAt
        self.displayID = displayID
        self.width = width
        self.height = height
        self.frontmostApp = frontmostApp
        self.frontmostBundleId = frontmostBundleId
        self.frontmostWindowTitle = frontmostWindowTitle
    }
}

public struct InferenceInput {
    public var imageURL: URL
    public var frontmostApp: String?
    public var frontmostWindowTitle: String?
    public var allowedTags: [Tag]
    public var locale: String = "ja"
    public var promptVersion: String = "v1"

    public init(imageURL: URL, frontmostApp: String? = nil, frontmostWindowTitle: String? = nil,
                allowedTags: [Tag],
                locale: String = "ja", promptVersion: String = "v1") {
        self.imageURL = imageURL
        self.frontmostApp = frontmostApp
        self.frontmostWindowTitle = frontmostWindowTitle
        self.allowedTags = allowedTags
        self.locale = locale
        self.promptVersion = promptVersion
    }
}

public struct InferenceResult: Codable {
    public var activitySummary: String
    public var predictedTags: [String]
    public var reason: String
    public var sensitivityFlag: String
    public var rawJson: String

    enum CodingKeys: String, CodingKey {
        case activitySummary = "activity_summary"
        case predictedTags = "predicted_tags"
        case reason
        case sensitivityFlag = "sensitivity_flag"
        case rawJson
    }

    public init(activitySummary: String, predictedTags: [String],
                reason: String, sensitivityFlag: String, rawJson: String) {
        self.activitySummary = activitySummary
        self.predictedTags = predictedTags
        self.reason = reason
        self.sensitivityFlag = sensitivityFlag
        self.rawJson = rawJson
    }
}
