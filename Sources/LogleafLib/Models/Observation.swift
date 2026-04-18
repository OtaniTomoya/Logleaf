import Foundation
import GRDB

public struct Observation: Codable, Identifiable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "observations"

    public var id: String
    public var captureJobId: String
    public var capturedAt: Date
    public var imagePath: String?
    public var imageSha256: String?
    public var imageWidth: Int?
    public var imageHeight: Int?
    public var frontmostApp: String?
    public var frontmostBundleId: String?
    public var frontmostWindowTitle: String?
    public var displayId: String?
    public var captureState: CaptureState
    public var rawVlmOutputJson: String?
    public var aiSummary: String?
    public var aiReason: String?
    public var sensitivityFlag: SensitivityFlag?
    public var isUserHidden: Bool
    public var createdAt: Date

    public enum CaptureState: String, Codable {
        case captured
        case excluded
        case blackout
        case failure
    }

    public enum SensitivityFlag: String, Codable {
        case none
        case personal
        case secret
        case unknown
    }

    public enum Columns {
        public static let id = Column(CodingKeys.id)
        public static let capturedAt = Column(CodingKeys.capturedAt)
        public static let frontmostBundleId = Column(CodingKeys.frontmostBundleId)
        public static let captureState = Column(CodingKeys.captureState)
    }

    public init(id: String = UUID().uuidString, captureJobId: String,
         capturedAt: Date = Date(), imagePath: String? = nil,
         imageSha256: String? = nil, imageWidth: Int? = nil, imageHeight: Int? = nil,
         frontmostApp: String? = nil, frontmostBundleId: String? = nil,
         frontmostWindowTitle: String? = nil, displayId: String? = nil,
         captureState: CaptureState = .captured,
         rawVlmOutputJson: String? = nil, aiSummary: String? = nil,
         aiReason: String? = nil,
         sensitivityFlag: SensitivityFlag? = nil,
         isUserHidden: Bool = false, createdAt: Date = Date()) {
        self.id = id
        self.captureJobId = captureJobId
        self.capturedAt = capturedAt
        self.imagePath = imagePath
        self.imageSha256 = imageSha256
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.frontmostApp = frontmostApp
        self.frontmostBundleId = frontmostBundleId
        self.frontmostWindowTitle = frontmostWindowTitle
        self.displayId = displayId
        self.captureState = captureState
        self.rawVlmOutputJson = rawVlmOutputJson
        self.aiSummary = aiSummary
        self.aiReason = aiReason
        self.sensitivityFlag = sensitivityFlag
        self.isUserHidden = isUserHidden
        self.createdAt = createdAt
    }
}

public struct ObservationTag: Codable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "observation_tags"

    public var observationId: String
    public var tagId: String
    public var score: Double
    public var source: TagSource

    public enum TagSource: String, Codable {
        case ai
        case user
    }

    public init(observationId: String, tagId: String, score: Double, source: TagSource) {
        self.observationId = observationId
        self.tagId = tagId
        self.score = score
        self.source = source
    }
}
