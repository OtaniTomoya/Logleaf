import SwiftUI
import Combine

@MainActor
public final class AppState: ObservableObject {
    // MARK: - Published State
    @Published public var isCapturing: Bool = false
    @Published public var isSetupComplete: Bool = false
    @Published public var captureStatus: CaptureStatus = .idle
    @Published public var todayRecordedMinutes: Int = 0
    @Published public var latestActivity: String = ""
    @Published public var nextCaptureDate: Date?
    @Published public var selectedDate: Date = Date()
    @Published public var pendingInferenceCount: Int = 0
    @Published public var completedInferenceCount: Int = 0
    @Published public var currentInferenceProcessedCount: Int = 0
    @Published public var currentInferenceTotalCount: Int = 0
    @Published public var shouldOpenSettings: Bool = false
    @Published public var inferenceJustCompleted: Bool = false
    private var isRunningPendingInference: Bool = false
    private let inferredScreenshotRetention: TimeInterval = 24 * 60 * 60

    // MARK: - Services
    public let databaseManager: DatabaseManager
    public let settingsRepository: SettingsRepository
    public let tagRepository: TagRepository
    public let exclusionRuleRepository: ExclusionRuleRepository
    public let captureJobRepository: CaptureJobRepository
    public let observationRepository: ObservationRepository
    public let checkpointRepository: CheckpointRepository
    public let workSessionRepository: WorkSessionRepository
    public let auditLogRepository: AuditLogRepository

    public let fileStorageService: FileStorageService
    public let permissionService: PermissionService
    public let captureService: CaptureService
    public let exclusionService: ExclusionService
    public let inferenceService: InferenceService
    public let aggregationService: AggregationService
    public let tagService: TagService
    public let settingsService: SettingsService
    public let schedulerService: SchedulerService
    public let dailyFeedbackService: DailyFeedbackService
    public let dailyFeedbackRepository: DailyFeedbackRepository

    public init(
        fileStorageService: FileStorageService = FileStorageService(),
        ollamaClient: OllamaClient = OllamaClient()
    ) {
        let fileStorage = fileStorageService
        self.fileStorageService = fileStorage

        let dbManager = DatabaseManager(fileStorageService: fileStorage)
        self.databaseManager = dbManager

        let settingsRepo = SettingsRepository(databaseManager: dbManager)
        self.settingsRepository = settingsRepo
        let tagRepo = TagRepository(databaseManager: dbManager)
        self.tagRepository = tagRepo
        let exclusionRepo = ExclusionRuleRepository(databaseManager: dbManager)
        self.exclusionRuleRepository = exclusionRepo
        let captureJobRepo = CaptureJobRepository(databaseManager: dbManager)
        self.captureJobRepository = captureJobRepo
        let observationRepo = ObservationRepository(databaseManager: dbManager)
        self.observationRepository = observationRepo
        let checkpointRepo = CheckpointRepository(databaseManager: dbManager)
        self.checkpointRepository = checkpointRepo
        let workSessionRepo = WorkSessionRepository(databaseManager: dbManager)
        self.workSessionRepository = workSessionRepo
        let auditLogRepo = AuditLogRepository(databaseManager: dbManager)
        self.auditLogRepository = auditLogRepo

        self.permissionService = PermissionService()
        self.settingsService = SettingsService(repository: settingsRepo)
        self.tagService = TagService(tagRepository: tagRepo)
        self.exclusionService = ExclusionService(repository: exclusionRepo)

        let promptBuilder = PromptBuilder()
        self.inferenceService = InferenceService(
            ollamaClient: ollamaClient,
            promptBuilder: promptBuilder,
            observationRepository: observationRepo,
            tagRepository: tagRepo
        )

        self.captureService = CaptureService(
            captureJobRepository: captureJobRepo,
            observationRepository: observationRepo,
            exclusionService: self.exclusionService,
            fileStorageService: fileStorage
        )

        self.aggregationService = AggregationService(
            observationRepository: observationRepo,
            checkpointRepository: checkpointRepo,
            workSessionRepository: workSessionRepo,
            fileStorageService: fileStorage
        )

        let dailyFeedbackRepo = DailyFeedbackRepository(databaseManager: dbManager)
        self.dailyFeedbackRepository = dailyFeedbackRepo
        self.dailyFeedbackService = DailyFeedbackService(
            ollamaClient: ollamaClient,
            promptBuilder: promptBuilder,
            workSessionRepository: workSessionRepo,
            tagRepository: tagRepo,
            dailyFeedbackRepository: dailyFeedbackRepo
        )

        self.schedulerService = SchedulerService(captureService: captureService)

        loadInitialState()
    }

    private func loadInitialState() {
        let settings = (try? settingsService.loadSettings()) ?? AppSettings()
        inferenceService.configure(host: settings.ollamaHost, model: settings.ollamaModel)
        cleanupOldInferredScreenshots()
        refreshInferenceQueueStats()
        do {
            let setupDone = try settingsService.loadBool(forKey: "setup_complete")
            isSetupComplete = setupDone
        } catch {
            isSetupComplete = false
        }
    }

    public func applyRuntimeSettings() {
        let settings = (try? settingsService.loadSettings()) ?? AppSettings()
        inferenceService.configure(host: settings.ollamaHost, model: settings.ollamaModel)

        if isCapturing {
            schedulerService.start(intervalSeconds: TimeInterval(settings.captureIntervalSeconds))
        }
    }

    public func startCapturing() {
        guard isSetupComplete else { return }
        let settings = (try? settingsService.loadSettings()) ?? AppSettings()
        inferenceService.configure(host: settings.ollamaHost, model: settings.ollamaModel)
        isCapturing = true
        captureStatus = .capturing
        schedulerService.start(intervalSeconds: TimeInterval(settings.captureIntervalSeconds))
    }

    public func stopCapturing() {
        isCapturing = false
        captureStatus = .paused
        schedulerService.stop()
    }

    public func toggleCapturing() {
        if isCapturing {
            stopCapturing()
        } else {
            startCapturing()
        }
    }

    public func captureNow() async {
        let wasInferring = isRunningPendingInference
        if !wasInferring {
            captureStatus = .capturing
        }
        await captureService.captureOnce()
        if !wasInferring {
            captureStatus = isCapturing ? .capturing : .idle
        }
        refreshInferenceQueueStats()
    }

    public func runPendingInference() async {
        guard !isRunningPendingInference else { return }
        isRunningPendingInference = true
        defer {
            isRunningPendingInference = false
            if captureStatus == .inferring {
                captureStatus = isCapturing ? .capturing : .idle
            }
        }

        applyRuntimeSettings()

        let pendingObservations = (try? observationRepository.fetchPendingInferenceObservations()) ?? []
        currentInferenceProcessedCount = 0
        currentInferenceTotalCount = pendingObservations.count

        guard !pendingObservations.isEmpty else {
            refreshInferenceQueueStats()
            return
        }

        captureStatus = .inferring
        await inferenceService.inferPendingObservations(pendingObservations) { [weak self] processed, total in
            Task { @MainActor [weak self] in
                self?.currentInferenceProcessedCount = processed
                self?.currentInferenceTotalCount = total
                self?.refreshInferenceQueueStats()
            }
        }
        // 推論完了後にセッションを自動再構築
        do {
            let calendar = Calendar.current
            let affectedDates = Set(pendingObservations.map { calendar.startOfDay(for: $0.capturedAt) })
            for day in affectedDates.sorted() {
                try aggregationService.buildCheckpoints(for: day)
                _ = try aggregationService.buildSessions(for: day)
            }
        } catch {
            AppLogger.error("Failed to rebuild sessions after inference: \(error)")
        }

        refreshInferenceQueueStats()
        inferenceJustCompleted = true
        cleanupOldInferredScreenshots()
    }

    public func refreshInferenceQueueStats() {
        pendingInferenceCount = (try? observationRepository.countPendingInference()) ?? 0
        completedInferenceCount = (try? observationRepository.countCompletedInference()) ?? 0
    }

    public func cleanupOldInferredScreenshots() {
        let cutoff = Date().addingTimeInterval(-inferredScreenshotRetention)
        do {
            let targets = try observationRepository.fetchInferredWithImage(olderThan: cutoff)
            guard !targets.isEmpty else { return }
            for observation in targets {
                guard let imagePath = observation.imagePath else { continue }
                do {
                    try fileStorageService.deleteFile(at: URL(fileURLWithPath: imagePath))
                } catch {
                    AppLogger.warning("Failed to delete old screenshot for \(observation.id): \(error)")
                }
                try observationRepository.clearImageReference(observationId: observation.id)
            }
        } catch {
            AppLogger.error("Failed to cleanup old inferred screenshots: \(error)")
        }
    }

    public func completeSetup() {
        do {
            try settingsService.saveBool(true, forKey: "setup_complete")
            isSetupComplete = true
        } catch {
            AppLogger.error("Failed to save setup state: \(error)")
        }
    }
}

public enum CaptureStatus: String {
    case idle = "待機中"
    case capturing = "収録中"
    case paused = "一時停止"
    case permissionDenied = "権限不足"
    case inferring = "推論中"
}
