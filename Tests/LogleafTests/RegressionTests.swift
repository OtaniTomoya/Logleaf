import Foundation
import XCTest
@testable import LogleafLib

final class RegressionTests: XCTestCase {
    @MainActor
    func testAppStateAppliesSavedOllamaSettingsAndCaptureInterval() throws {
        let env = TestEnvironment()

        var settings = AppSettings()
        settings.ollamaHost = "http://127.0.0.1:18080"
        settings.ollamaModel = "llava:test"
        settings.captureIntervalSeconds = 120
        try env.settingsService.saveSettings(settings)
        try env.settingsService.saveBool(true, forKey: "setup_complete")

        let ollamaClient = OllamaClient()
        let appState = AppState(fileStorageService: env.fileStorageService, ollamaClient: ollamaClient)

        XCTAssertEqual(ollamaClient.configuredHost, "http://127.0.0.1:18080")
        XCTAssertEqual(ollamaClient.configuredModel, "llava:test")

        appState.startCapturing()
        XCTAssertEqual(appState.schedulerService.configuredIntervalSeconds, 120)
        appState.stopCapturing()
    }

    func testBuildSessionsPreservesProtectedSessionsDuringRebuild() throws {
        let env = TestEnvironment()
        let baseDate = makeDate(year: 2026, month: 4, day: 18, hour: 9, minute: 0)

        let protectedObservation = try env.makeObservation(at: baseDate)
        let rebuiltObservation1 = try env.makeObservation(at: baseDate.addingTimeInterval(60))
        let rebuiltObservation2 = try env.makeObservation(at: baseDate.addingTimeInterval(120))

        let protectedSession = WorkSession(
            startAt: protectedObservation.capturedAt,
            endAt: protectedObservation.capturedAt.addingTimeInterval(60),
            aiTitle: "AI title",
            finalTitle: "Manual title"
        )
        try env.workSessionRepository.save(protectedSession)
        try env.workSessionRepository.saveSessionObservation(
            SessionObservation(workSessionId: protectedSession.id, observationId: protectedObservation.id)
        )

        let draftSession = WorkSession(
            startAt: rebuiltObservation1.capturedAt,
            endAt: rebuiltObservation2.capturedAt,
            aiTitle: "Draft"
        )
        try env.workSessionRepository.save(draftSession)
        try env.workSessionRepository.saveSessionObservation(
            SessionObservation(workSessionId: draftSession.id, observationId: rebuiltObservation1.id)
        )
        try env.workSessionRepository.saveSessionObservation(
            SessionObservation(workSessionId: draftSession.id, observationId: rebuiltObservation2.id)
        )

        let sessions = try env.aggregationService.buildSessions(for: baseDate)
        let storedSessions = try env.workSessionRepository.fetchForDate(baseDate)

        XCTAssertEqual(sessions.count, 2)
        XCTAssertEqual(storedSessions.count, 2)
        XCTAssertEqual(try env.workSessionRepository.fetch(id: protectedSession.id)?.finalTitle, "Manual title")
        XCTAssertNil(try env.workSessionRepository.fetch(id: draftSession.id))

        let rebuiltSession = try XCTUnwrap(storedSessions.first { $0.id != protectedSession.id })
        let rebuiltObservationIds = try env.workSessionRepository.fetchObservationIds(sessionId: rebuiltSession.id)
        XCTAssertEqual(Set(rebuiltObservationIds), Set([rebuiltObservation1.id, rebuiltObservation2.id]))
    }

    func testMergeSessionsCarriesExistingTagsToMergedSession() throws {
        let env = TestEnvironment()
        let baseDate = makeDate(year: 2026, month: 4, day: 18, hour: 10, minute: 0)
        let aiTag = Tag(name: "開発")
        let userTag = Tag(name: "会議")
        try env.tagRepository.save(aiTag)
        try env.tagRepository.save(userTag)

        let session1 = WorkSession(startAt: baseDate, endAt: baseDate.addingTimeInterval(300), aiTitle: "A")
        let session2 = WorkSession(startAt: baseDate.addingTimeInterval(360), endAt: baseDate.addingTimeInterval(660), aiTitle: "B")
        try env.workSessionRepository.save(session1)
        try env.workSessionRepository.save(session2)
        try env.workSessionRepository.saveTags([
            WorkSessionTag(workSessionId: session1.id, tagId: aiTag.id, source: .ai),
            WorkSessionTag(workSessionId: session2.id, tagId: userTag.id, source: .user),
        ])

        try env.aggregationService.mergeSessions(sessionIds: [session1.id, session2.id])

        let mergedSession = try XCTUnwrap(try env.workSessionRepository.fetchForDate(baseDate).onlyElement)
        let mergedTags = try env.workSessionRepository.fetchTags(sessionId: mergedSession.id)

        XCTAssertEqual(Set(mergedTags.map(\.tagId)), Set([aiTag.id, userTag.id]))
        XCTAssertEqual(Set(mergedTags.map(\.source)), Set([.ai, .user]))
    }

    func testExportExcludesUnclassifiedWhenFlagIsDisabled() throws {
        let env = TestEnvironment()
        let date = makeDate(year: 2026, month: 4, day: 18, hour: 11, minute: 0)
        let tag = Tag(name: "開発")
        try env.tagRepository.save(tag)

        let taggedSession = WorkSession(startAt: date, endAt: date.addingTimeInterval(300), aiTitle: "Tagged")
        let unclassifiedSession = WorkSession(startAt: date.addingTimeInterval(600), endAt: date.addingTimeInterval(900), aiTitle: "Unclassified")
        try env.workSessionRepository.save(taggedSession)
        try env.workSessionRepository.save(unclassifiedSession)
        try env.workSessionRepository.saveTags([
            WorkSessionTag(workSessionId: taggedSession.id, tagId: tag.id, source: .ai),
        ])

        let url = try env.exportService.exportJSON(
            filter: ExportFilter(
                startDate: date.addingTimeInterval(-60),
                endDate: date.addingTimeInterval(1200),
                includeUnclassified: false
            )
        )

        XCTAssertEqual(try loadExportedSessionIDs(from: url), [taggedSession.id])
    }

    func testExportCanKeepUnclassifiedAlongsideTagFilter() throws {
        let env = TestEnvironment()
        let date = makeDate(year: 2026, month: 4, day: 18, hour: 12, minute: 0)
        let tag = Tag(name: "開発")
        try env.tagRepository.save(tag)

        let taggedSession = WorkSession(startAt: date, endAt: date.addingTimeInterval(300), aiTitle: "Tagged")
        let unclassifiedSession = WorkSession(startAt: date.addingTimeInterval(600), endAt: date.addingTimeInterval(900), aiTitle: "Unclassified")
        try env.workSessionRepository.save(taggedSession)
        try env.workSessionRepository.save(unclassifiedSession)
        try env.workSessionRepository.saveTags([
            WorkSessionTag(workSessionId: taggedSession.id, tagId: tag.id, source: .ai),
        ])

        let url = try env.exportService.exportJSON(
            filter: ExportFilter(
                startDate: date.addingTimeInterval(-60),
                endDate: date.addingTimeInterval(1200),
                tagIds: [tag.id],
                includeUnclassified: true
            )
        )

        XCTAssertEqual(
            Set(try loadExportedSessionIDs(from: url)),
            Set([taggedSession.id, unclassifiedSession.id])
        )
    }

    func testLoadSettingsKeepsDefaultAutoDeleteEnabledWhenNotSaved() throws {
        let env = TestEnvironment()

        let settings = try env.settingsService.loadSettings()

        XCTAssertTrue(settings.autoDeleteEnabled)
    }

    @MainActor
    func testSummaryDailyMinutesAreSortedByDateAcrossYearBoundary() {
        let env = TestEnvironment()
        let viewModel = SummaryViewModel(
            workSessionRepository: env.workSessionRepository,
            tagRepository: env.tagRepository
        )
        let anchor = makeLocalDate(year: 2026, month: 1, day: 1, hour: 9, minute: 0)
        viewModel.period = .weekly
        viewModel.startDate = anchor

        viewModel.loadSummary()

        let calendar = Calendar.current
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: anchor)!.start
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd"

        var expected: [String] = []
        var current = weekStart
        for _ in 0..<7 {
            expected.append(formatter.string(from: current))
            current = calendar.date(byAdding: .day, value: 1, to: current)!
        }

        XCTAssertEqual(viewModel.dailyMinutes.map(\.dateString), expected)
    }

    func testBestDisplayIDPrefersDisplayWithLargestIntersection() {
        let selected = CaptureService.bestDisplayID(
            for: CGRect(x: 1500, y: 100, width: 300, height: 400),
            displayFrames: [
                (id: CGDirectDisplayID(1), bounds: CGRect(x: 0, y: 0, width: 1440, height: 900)),
                (id: CGDirectDisplayID(2), bounds: CGRect(x: 1440, y: 0, width: 1440, height: 900)),
            ]
        )

        XCTAssertEqual(selected, CGDirectDisplayID(2))
    }

    @MainActor
    func testSchedulerOnlyResumesAfterSystemInterruptionWhenCaptureWasRunning() {
        let env = TestEnvironment()

        XCTAssertFalse(env.schedulerService.isRunning)
        env.schedulerService.resumeAfterSystemInterruptionIfNeeded()
        XCTAssertFalse(env.schedulerService.isRunning)

        env.schedulerService.start(intervalSeconds: 120)
        XCTAssertTrue(env.schedulerService.isRunning)

        env.schedulerService.pauseForSystemInterruption()
        XCTAssertFalse(env.schedulerService.isRunning)

        env.schedulerService.resumeAfterSystemInterruptionIfNeeded()
        XCTAssertTrue(env.schedulerService.isRunning)

        env.schedulerService.stop()
        XCTAssertFalse(env.schedulerService.isRunning)

        env.schedulerService.resumeAfterSystemInterruptionIfNeeded()
        XCTAssertFalse(env.schedulerService.isRunning)
    }

    @MainActor
    func testSummaryReloadDoesNotAccumulateUnclassifiedMinutes() throws {
        let env = TestEnvironment()
        let baseDate = makeDate(year: 2026, month: 4, day: 18, hour: 13, minute: 0)
        let session = WorkSession(
            startAt: baseDate,
            endAt: baseDate.addingTimeInterval(900),
            aiTitle: "Unclassified"
        )
        try env.workSessionRepository.save(session)

        let viewModel = SummaryViewModel(
            workSessionRepository: env.workSessionRepository,
            tagRepository: env.tagRepository
        )
        viewModel.startDate = baseDate

        viewModel.loadSummary()
        XCTAssertEqual(viewModel.unclassifiedMinutes, 15)

        viewModel.loadSummary()
        XCTAssertEqual(viewModel.unclassifiedMinutes, 15)
    }

    @MainActor
    func testExportViewModelNormalizesDateOnlyRangeToWholeDays() throws {
        let env = TestEnvironment()
        let firstDay = makeLocalDate(year: 2026, month: 4, day: 11, hour: 9, minute: 0)
        let lastDay = makeLocalDate(year: 2026, month: 4, day: 18, hour: 20, minute: 0)

        let firstSession = WorkSession(
            startAt: firstDay,
            endAt: firstDay.addingTimeInterval(300),
            aiTitle: "Start boundary"
        )
        let lastSession = WorkSession(
            startAt: lastDay,
            endAt: lastDay.addingTimeInterval(300),
            aiTitle: "End boundary"
        )
        try env.workSessionRepository.save(firstSession)
        try env.workSessionRepository.save(lastSession)

        let viewModel = ExportViewModel(
            exportService: env.exportService,
            tagRepository: env.tagRepository
        )
        viewModel.selectedFormat = .json
        viewModel.startDate = makeLocalDate(year: 2026, month: 4, day: 11, hour: 15, minute: 30)
        viewModel.endDate = makeLocalDate(year: 2026, month: 4, day: 18, hour: 15, minute: 30)

        viewModel.export()

        let exportedURL = try XCTUnwrap(viewModel.exportedURL)
        XCTAssertEqual(
            Set(try loadExportedSessionIDs(from: exportedURL)),
            Set([firstSession.id, lastSession.id])
        )
    }
}

private final class TestEnvironment {
    let rootURL: URL
    let fileStorageService: FileStorageService
    let databaseManager: DatabaseManager
    let settingsRepository: SettingsRepository
    let settingsService: SettingsService
    let tagRepository: TagRepository
    let exclusionRuleRepository: ExclusionRuleRepository
    let captureJobRepository: CaptureJobRepository
    let observationRepository: ObservationRepository
    let checkpointRepository: CheckpointRepository
    let workSessionRepository: WorkSessionRepository
    let exportRepository: ExportRepository
    let exclusionService: ExclusionService
    let inferenceService: InferenceService
    let captureService: CaptureService
    let schedulerService: SchedulerService
    let aggregationService: AggregationService
    let exportService: ExportService

    init() {
        rootURL = FileManager.default.temporaryDirectory.appendingPathComponent("LogleafTests-\(UUID().uuidString)")
        fileStorageService = FileStorageService(appSupportURL: rootURL)
        databaseManager = DatabaseManager(fileStorageService: fileStorageService)
        settingsRepository = SettingsRepository(databaseManager: databaseManager)
        settingsService = SettingsService(repository: settingsRepository)
        tagRepository = TagRepository(databaseManager: databaseManager)
        exclusionRuleRepository = ExclusionRuleRepository(databaseManager: databaseManager)
        captureJobRepository = CaptureJobRepository(databaseManager: databaseManager)
        observationRepository = ObservationRepository(databaseManager: databaseManager)
        checkpointRepository = CheckpointRepository(databaseManager: databaseManager)
        workSessionRepository = WorkSessionRepository(databaseManager: databaseManager)
        exportRepository = ExportRepository(databaseManager: databaseManager)
        exclusionService = ExclusionService(repository: exclusionRuleRepository)
        inferenceService = InferenceService(
            ollamaClient: OllamaClient(),
            promptBuilder: PromptBuilder(),
            observationRepository: observationRepository,
            tagRepository: tagRepository
        )
        captureService = CaptureService(
            captureJobRepository: captureJobRepository,
            observationRepository: observationRepository,
            exclusionService: exclusionService,
            fileStorageService: fileStorageService,
            inferenceService: inferenceService
        )
        schedulerService = SchedulerService(captureService: captureService)
        aggregationService = AggregationService(
            observationRepository: observationRepository,
            checkpointRepository: checkpointRepository,
            workSessionRepository: workSessionRepository,
            fileStorageService: fileStorageService
        )
        exportService = ExportService(
            workSessionRepository: workSessionRepository,
            observationRepository: observationRepository,
            tagRepository: tagRepository,
            exportRepository: exportRepository,
            fileStorageService: fileStorageService
        )
    }

    deinit {
        try? FileManager.default.removeItem(at: rootURL)
    }

    func makeObservation(at capturedAt: Date) throws -> Observation {
        let job = CaptureJob(scheduledAt: capturedAt, executedAt: capturedAt, status: .succeeded)
        try captureJobRepository.save(job)

        let observation = Observation(
            captureJobId: job.id,
            capturedAt: capturedAt,
            captureState: .captured
        )
        try observationRepository.save(observation)
        return observation
    }
}

private func makeDate(year: Int, month: Int, day: Int, hour: Int, minute: Int) -> Date {
    var components = DateComponents()
    components.calendar = Calendar(identifier: .gregorian)
    components.timeZone = TimeZone(secondsFromGMT: 0)
    components.year = year
    components.month = month
    components.day = day
    components.hour = hour
    components.minute = minute
    return components.date ?? Date(timeIntervalSince1970: 0)
}

private func makeLocalDate(year: Int, month: Int, day: Int, hour: Int, minute: Int) -> Date {
    var components = DateComponents()
    components.calendar = Calendar(identifier: .gregorian)
    components.timeZone = .current
    components.year = year
    components.month = month
    components.day = day
    components.hour = hour
    components.minute = minute
    return components.date ?? Date(timeIntervalSince1970: 0)
}

private func loadExportedSessionIDs(from url: URL) throws -> [String] {
    let data = try Data(contentsOf: url)
    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    let sessions = json?["sessions"] as? [[String: Any]] ?? []
    return sessions.compactMap { $0["id"] as? String }
}

private extension Array {
    var onlyElement: Element? {
        count == 1 ? first : nil
    }
}
