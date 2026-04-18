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

    @MainActor
    func testAppStateCleanupOldInferredScreenshotsKeepsOneDay() throws {
        let env = TestEnvironment()
        let appState = AppState(fileStorageService: env.fileStorageService, ollamaClient: OllamaClient())

        let now = Date()
        let oldDate = now.addingTimeInterval(-(24 * 60 * 60 + 60))
        let recentDate = now.addingTimeInterval(-(23 * 60 * 60))

        let oldImageURL = env.fileStorageService.screenshotPath(for: oldDate, id: UUID().uuidString)
        try Data([0xFF, 0xD8, 0xFF]).write(to: oldImageURL)
        let oldJob = CaptureJob(scheduledAt: oldDate, executedAt: oldDate, status: .succeeded)
        try env.captureJobRepository.save(oldJob)
        var oldObservation = Observation(
            captureJobId: oldJob.id,
            capturedAt: oldDate,
            imagePath: oldImageURL.path,
            captureState: .captured
        )
        oldObservation.aiSummary = "old inferred"
        try env.observationRepository.save(oldObservation)

        let recentImageURL = env.fileStorageService.screenshotPath(for: recentDate, id: UUID().uuidString)
        try Data([0xFF, 0xD8, 0xFF]).write(to: recentImageURL)
        let recentJob = CaptureJob(scheduledAt: recentDate, executedAt: recentDate, status: .succeeded)
        try env.captureJobRepository.save(recentJob)
        var recentObservation = Observation(
            captureJobId: recentJob.id,
            capturedAt: recentDate,
            imagePath: recentImageURL.path,
            captureState: .captured
        )
        recentObservation.aiSummary = "recent inferred"
        try env.observationRepository.save(recentObservation)

        appState.cleanupOldInferredScreenshotsSync()

        XCTAssertFalse(FileManager.default.fileExists(atPath: oldImageURL.path))
        let refreshedOld = try XCTUnwrap(env.observationRepository.fetch(id: oldObservation.id))
        XCTAssertNil(refreshedOld.imagePath)

        XCTAssertTrue(FileManager.default.fileExists(atPath: recentImageURL.path))
        let refreshedRecent = try XCTUnwrap(env.observationRepository.fetch(id: recentObservation.id))
        XCTAssertEqual(refreshedRecent.imagePath, recentImageURL.path)
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

        let autoConfirmedSession = WorkSession(
            startAt: rebuiltObservation1.capturedAt,
            endAt: rebuiltObservation2.capturedAt,
            aiTitle: "Draft",
            status: .draft
        )
        try env.workSessionRepository.save(autoConfirmedSession)
        try env.workSessionRepository.saveSessionObservation(
            SessionObservation(workSessionId: autoConfirmedSession.id, observationId: rebuiltObservation1.id)
        )
        try env.workSessionRepository.saveSessionObservation(
            SessionObservation(workSessionId: autoConfirmedSession.id, observationId: rebuiltObservation2.id)
        )

        let sessions = try env.aggregationService.buildSessions(for: baseDate)
        let storedSessions = try env.workSessionRepository.fetchForDate(baseDate)

        XCTAssertEqual(sessions.count, 2)
        XCTAssertEqual(storedSessions.count, 2)
        XCTAssertEqual(try env.workSessionRepository.fetch(id: protectedSession.id)?.finalTitle, "Manual title")
        XCTAssertNil(try env.workSessionRepository.fetch(id: autoConfirmedSession.id))

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

    func testBuildSessionsPreservesMergedSession() throws {
        let env = TestEnvironment()
        let baseDate = makeDate(year: 2026, month: 4, day: 18, hour: 10, minute: 0)
        let firstObservation = try env.makeObservation(at: baseDate)
        let secondObservation = try env.makeObservation(at: baseDate.addingTimeInterval(300))

        let session1 = WorkSession(startAt: firstObservation.capturedAt, endAt: firstObservation.capturedAt, aiTitle: "A")
        let session2 = WorkSession(startAt: secondObservation.capturedAt, endAt: secondObservation.capturedAt, aiTitle: "B")
        try env.workSessionRepository.save(session1)
        try env.workSessionRepository.save(session2)
        try env.workSessionRepository.saveSessionObservation(
            SessionObservation(workSessionId: session1.id, observationId: firstObservation.id)
        )
        try env.workSessionRepository.saveSessionObservation(
            SessionObservation(workSessionId: session2.id, observationId: secondObservation.id)
        )

        try env.aggregationService.mergeSessions(sessionIds: [session1.id, session2.id])
        let mergedBefore = try XCTUnwrap(try env.workSessionRepository.fetchForDate(baseDate).onlyElement)
        XCTAssertEqual(mergedBefore.status, .edited)

        _ = try env.aggregationService.buildSessions(for: baseDate)

        let mergedAfter = try env.workSessionRepository.fetchForDate(baseDate)
        XCTAssertEqual(mergedAfter.map(\.id), [mergedBefore.id])
    }

    func testSplitSessionSortsObservationsByCapturedAtBeforeBuildingSessions() throws {
        let env = TestEnvironment()
        let t0 = makeDate(year: 2026, month: 4, day: 18, hour: 9, minute: 0)
        let t1 = makeDate(year: 2026, month: 4, day: 18, hour: 9, minute: 10)
        let t2 = makeDate(year: 2026, month: 4, day: 18, hour: 9, minute: 20)

        let obs0 = try env.makeObservation(at: t0)
        let obs1 = try env.makeObservation(at: t1)
        let obs2 = try env.makeObservation(at: t2)

        let session = WorkSession(startAt: t0, endAt: t2, aiTitle: "Split")
        try env.workSessionRepository.save(session)

        // Intentionally save links out of time order.
        try env.workSessionRepository.saveSessionObservation(
            SessionObservation(workSessionId: session.id, observationId: obs1.id)
        )
        try env.workSessionRepository.saveSessionObservation(
            SessionObservation(workSessionId: session.id, observationId: obs0.id)
        )
        try env.workSessionRepository.saveSessionObservation(
            SessionObservation(workSessionId: session.id, observationId: obs2.id)
        )

        try env.aggregationService.splitSession(
            sessionId: session.id,
            at: makeDate(year: 2026, month: 4, day: 18, hour: 9, minute: 15)
        )

        let splitSessions = try env.workSessionRepository.fetchForDate(t0)
        XCTAssertEqual(splitSessions.count, 2)

        let before = try XCTUnwrap(splitSessions.first(where: { $0.endAt <= t1 }))
        let after = try XCTUnwrap(splitSessions.first(where: { $0.startAt >= t2 }))

        XCTAssertEqual(before.startAt, t0)
        XCTAssertEqual(before.endAt, t1)
        XCTAssertEqual(after.startAt, t2)
        XCTAssertEqual(after.endAt, t2)
    }

    func testLoadSettingsKeepsDefaultAutoDeleteEnabledWhenNotSaved() throws {
        let env = TestEnvironment()

        let settings = try env.settingsService.loadSettings()

        XCTAssertTrue(settings.autoDeleteEnabled)
    }

    func testInferKeepsScreenshotAndImagePathOnSuccess() async throws {
        let env = TestEnvironment()
        let now = Date()
        let imageURL = env.fileStorageService.screenshotPath(for: now, id: UUID().uuidString)
        try Data([0xFF, 0xD8, 0xFF]).write(to: imageURL)
        let tag = Tag(name: "開発")
        try env.tagRepository.save(tag)

        let job = CaptureJob(scheduledAt: now, executedAt: now, status: .succeeded)
        try env.captureJobRepository.save(job)
        let observation = Observation(
            captureJobId: job.id,
            capturedAt: now,
            imagePath: imageURL.path,
            captureState: .captured
        )
        try env.observationRepository.save(observation)

        let mockClient = MockOllamaClient(
            generatedText: """
            {
              "results": [
                {
                  "index": 1,
                  "activity_summary": "コードを書いている",
                  "predicted_tags": ["開発"],
                  "reason": "IDEが見えるため",
                  "sensitivity_flag": "none"
                }
              ]
            }
            """
        )
        let inferenceService = InferenceService(
            ollamaClient: mockClient,
            promptBuilder: PromptBuilder(),
            observationRepository: env.observationRepository,
            tagRepository: env.tagRepository
        )

        await inferenceService.infer(
            observationId: observation.id,
            imageURL: imageURL,
            frontmostApp: "Xcode",
            frontmostWindowTitle: "Test"
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: imageURL.path))
        let refreshed = try XCTUnwrap(env.observationRepository.fetch(id: observation.id))
        XCTAssertEqual(refreshed.imagePath, imageURL.path)
    }

    func testInferKeepsScreenshotAndImagePathOnFailure() async throws {
        let env = TestEnvironment()
        let now = Date()
        let imageURL = env.fileStorageService.screenshotPath(for: now, id: UUID().uuidString)
        try Data([0xFF, 0xD8, 0xFF]).write(to: imageURL)
        let tag = Tag(name: "開発")
        try env.tagRepository.save(tag)

        let job = CaptureJob(scheduledAt: now, executedAt: now, status: .succeeded)
        try env.captureJobRepository.save(job)
        let observation = Observation(
            captureJobId: job.id,
            capturedAt: now,
            imagePath: imageURL.path,
            captureState: .captured
        )
        try env.observationRepository.save(observation)

        let mockClient = MockOllamaClient(generatedText: nil)
        let inferenceService = InferenceService(
            ollamaClient: mockClient,
            promptBuilder: PromptBuilder(),
            observationRepository: env.observationRepository,
            tagRepository: env.tagRepository
        )

        await inferenceService.infer(
            observationId: observation.id,
            imageURL: imageURL,
            frontmostApp: "Xcode",
            frontmostWindowTitle: "Test"
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: imageURL.path))
        let refreshed = try XCTUnwrap(env.observationRepository.fetch(id: observation.id))
        XCTAssertEqual(refreshed.imagePath, imageURL.path)
    }

    func testInferPendingObservationsUpdatesPendingAndCompletedCounts() async throws {
        let env = TestEnvironment()
        let now = Date()
        let tag = Tag(name: "開発")
        try env.tagRepository.save(tag)

        let imageURL1 = env.fileStorageService.screenshotPath(for: now, id: UUID().uuidString)
        let imageURL2 = env.fileStorageService.screenshotPath(for: now, id: UUID().uuidString)
        try Data([0xFF, 0xD8, 0xFF]).write(to: imageURL1)
        try Data([0xFF, 0xD8, 0xFF]).write(to: imageURL2)

        let job1 = CaptureJob(scheduledAt: now, executedAt: now, status: .succeeded)
        let job2 = CaptureJob(scheduledAt: now, executedAt: now, status: .succeeded)
        try env.captureJobRepository.save(job1)
        try env.captureJobRepository.save(job2)

        let observation1 = Observation(
            captureJobId: job1.id,
            capturedAt: now,
            imagePath: imageURL1.path,
            captureState: .captured
        )
        let observation2 = Observation(
            captureJobId: job2.id,
            capturedAt: now.addingTimeInterval(1),
            imagePath: imageURL2.path,
            captureState: .captured
        )
        try env.observationRepository.save(observation1)
        try env.observationRepository.save(observation2)

        let mockClient = MockOllamaClient(
            generatedText: """
            {
              "results": [
                {
                  "index": 1,
                  "activity_summary": "コードを書いている",
                  "predicted_tags": ["開発"],
                  "reason": "IDEが見えるため",
                  "sensitivity_flag": "none"
                },
                {
                  "index": 2,
                  "activity_summary": "コードレビューしている",
                  "predicted_tags": ["開発"],
                  "reason": "エディタが表示されているため",
                  "sensitivity_flag": "none"
                }
              ]
            }
            """
        )
        let inferenceService = InferenceService(
            ollamaClient: mockClient,
            promptBuilder: PromptBuilder(),
            observationRepository: env.observationRepository,
            tagRepository: env.tagRepository
        )

        let pending = try env.observationRepository.fetchPendingInferenceObservations()
        XCTAssertEqual(pending.count, 2)
        XCTAssertEqual(try env.observationRepository.countPendingInference(), 2)
        XCTAssertEqual(try env.observationRepository.countCompletedInference(), 0)

        var latestProgress = (0, 0)
        await inferenceService.inferPendingObservations(pending) { processed, total in
            latestProgress = (processed, total)
        }

        XCTAssertEqual(latestProgress.0, 2)
        XCTAssertEqual(latestProgress.1, 2)
        XCTAssertEqual(try env.observationRepository.countPendingInference(), 0)
        XCTAssertEqual(try env.observationRepository.countCompletedInference(), 2)
    }

    func testInferPendingObservationsRunsWithoutActiveTags() async throws {
        let env = TestEnvironment()
        let now = Date()

        let imageURL = env.fileStorageService.screenshotPath(for: now, id: UUID().uuidString)
        try Data([0xFF, 0xD8, 0xFF]).write(to: imageURL)

        let job = CaptureJob(scheduledAt: now, executedAt: now, status: .succeeded)
        try env.captureJobRepository.save(job)
        let observation = Observation(
            captureJobId: job.id,
            capturedAt: now,
            imagePath: imageURL.path,
            captureState: .captured
        )
        try env.observationRepository.save(observation)

        let mockClient = MockOllamaClient(
            generatedText: """
            {
              "results": [
                {
                  "index": 1,
                  "activity_summary": "仕様書を読んでいる",
                  "predicted_tags": [],
                  "reason": "ドキュメント画面が表示されているため",
                  "sensitivity_flag": "none"
                }
              ]
            }
            """
        )
        let inferenceService = InferenceService(
            ollamaClient: mockClient,
            promptBuilder: PromptBuilder(),
            observationRepository: env.observationRepository,
            tagRepository: env.tagRepository
        )

        let pending = try env.observationRepository.fetchPendingInferenceObservations()
        XCTAssertEqual(pending.count, 1)

        await inferenceService.inferPendingObservations(pending)

        XCTAssertEqual(try env.observationRepository.countPendingInference(), 0)
        XCTAssertEqual(try env.observationRepository.countCompletedInference(), 1)
        let refreshed = try XCTUnwrap(env.observationRepository.fetch(id: observation.id))
        XCTAssertEqual(refreshed.aiSummary, "仕様書を読んでいる")
        XCTAssertEqual(refreshed.imagePath, imageURL.path)
    }

    func testInferPendingObservationsFallsBackWhenConfiguredModelIsMissing() async throws {
        let env = TestEnvironment()
        let now = Date()
        let imageURL = env.fileStorageService.screenshotPath(for: now, id: UUID().uuidString)
        try Data([0xFF, 0xD8, 0xFF]).write(to: imageURL)
        let tag = Tag(name: "開発")
        try env.tagRepository.save(tag)

        let job = CaptureJob(scheduledAt: now, executedAt: now, status: .succeeded)
        try env.captureJobRepository.save(job)
        let observation = Observation(
            captureJobId: job.id,
            capturedAt: now,
            imagePath: imageURL.path,
            captureState: .captured
        )
        try env.observationRepository.save(observation)

        let mockClient = MockOllamaClient(
            generatedText: """
            {
              "results": [
                {
                  "index": 1,
                  "activity_summary": "コードレビュー中",
                  "predicted_tags": ["開発"],
                  "reason": "エディタ画面が表示されているため",
                  "sensitivity_flag": "none"
                }
              ]
            }
            """,
            availableModels: ["llava:latest", "gemma4:e2b"]
        )
        let inferenceService = InferenceService(
            ollamaClient: mockClient,
            promptBuilder: PromptBuilder(),
            observationRepository: env.observationRepository,
            tagRepository: env.tagRepository
        )
        inferenceService.configure(host: "http://localhost:11434", model: "gemma4:e4b")

        let pending = try env.observationRepository.fetchPendingInferenceObservations()
        await inferenceService.inferPendingObservations(pending)

        XCTAssertEqual(mockClient.configuredModel, "llava:latest")
        XCTAssertEqual(try env.observationRepository.countPendingInference(), 0)
        XCTAssertEqual(try env.observationRepository.countCompletedInference(), 1)
    }

    func testInferPendingObservationsBatchesByTen() async throws {
        let env = TestEnvironment()
        let now = Date()
        let tag = Tag(name: "開発")
        try env.tagRepository.save(tag)

        var created: [Observation] = []
        for i in 0..<12 {
            let imageURL = env.fileStorageService.screenshotPath(for: now, id: UUID().uuidString)
            try Data([0xFF, 0xD8, 0xFF]).write(to: imageURL)
            let job = CaptureJob(
                scheduledAt: now.addingTimeInterval(Double(i)),
                executedAt: now.addingTimeInterval(Double(i)),
                status: .succeeded
            )
            try env.captureJobRepository.save(job)
            let observation = Observation(
                captureJobId: job.id,
                capturedAt: now.addingTimeInterval(Double(i)),
                imagePath: imageURL.path,
                captureState: .captured
            )
            try env.observationRepository.save(observation)
            created.append(observation)
        }

        let mockClient = MockOllamaClient(
            generatedText: nil,
            generatedTextByCall: [
                makeBatchResponse(count: 10, summaryPrefix: "batch1"),
                makeBatchResponse(count: 2, summaryPrefix: "batch2")
            ]
        )
        let inferenceService = InferenceService(
            ollamaClient: mockClient,
            promptBuilder: PromptBuilder(),
            observationRepository: env.observationRepository,
            tagRepository: env.tagRepository
        )

        let pending = try env.observationRepository.fetchPendingInferenceObservations()
        await inferenceService.inferPendingObservations(pending)

        XCTAssertEqual(mockClient.receivedImageCounts, [10, 2])
        XCTAssertEqual(try env.observationRepository.countPendingInference(), 0)
        XCTAssertEqual(try env.observationRepository.countCompletedInference(), 12)
    }

    func testInferPendingObservationsClearsBrokenImageReference() async throws {
        let env = TestEnvironment()
        let now = Date()
        let job = CaptureJob(scheduledAt: now, executedAt: now, status: .succeeded)
        try env.captureJobRepository.save(job)

        let missingImagePath = env.fileStorageService
            .screenshotPath(for: now, id: UUID().uuidString)
            .path
        let observation = Observation(
            captureJobId: job.id,
            capturedAt: now,
            imagePath: missingImagePath,
            captureState: .captured
        )
        try env.observationRepository.save(observation)

        let inferenceService = InferenceService(
            ollamaClient: MockOllamaClient(generatedText: nil),
            promptBuilder: PromptBuilder(),
            observationRepository: env.observationRepository,
            tagRepository: env.tagRepository
        )

        let pending = try env.observationRepository.fetchPendingInferenceObservations()
        XCTAssertEqual(pending.count, 1)

        await inferenceService.inferPendingObservations(pending)

        XCTAssertEqual(try env.observationRepository.countPendingInference(), 0)
        let refreshed = try XCTUnwrap(env.observationRepository.fetch(id: observation.id))
        XCTAssertNil(refreshed.imagePath)
    }

    func testDailyFeedbackGenerateUpdatesSameDayRecordInsteadOfDuplicating() async throws {
        let env = TestEnvironment()
        let targetDate = makeDate(year: 2026, month: 4, day: 18, hour: 10, minute: 0)
        let session = WorkSession(
            startAt: targetDate,
            endAt: targetDate.addingTimeInterval(900),
            aiTitle: "集中作業"
        )
        try env.workSessionRepository.save(session)

        let service = DailyFeedbackService(
            ollamaClient: MockOllamaClient(generatedText: "要約テキスト"),
            promptBuilder: PromptBuilder(),
            workSessionRepository: env.workSessionRepository,
            tagRepository: env.tagRepository,
            dailyFeedbackRepository: DailyFeedbackRepository(databaseManager: env.databaseManager)
        )

        let first = try await service.generateFeedback(for: targetDate)
        var edited = first
        edited.editedFeedback = "手動編集"
        try service.updateFeedback(edited)

        let second = try await service.generateFeedback(for: targetDate)
        XCTAssertEqual(second.id, first.id)
        XCTAssertNil(second.editedFeedback)

        let fetched = try XCTUnwrap(service.fetchExisting(for: targetDate))
        XCTAssertEqual(fetched.id, first.id)
        XCTAssertEqual(fetched.aiFeedback, "要約テキスト")
        XCTAssertNil(fetched.editedFeedback)
    }

    func testDailyFeedbackFallsBackWhenConfiguredModelIsMissing() async throws {
        let env = TestEnvironment()
        let targetDate = makeDate(year: 2026, month: 4, day: 18, hour: 10, minute: 0)
        let session = WorkSession(
            startAt: targetDate,
            endAt: targetDate.addingTimeInterval(900),
            aiTitle: "集中作業"
        )
        try env.workSessionRepository.save(session)

        let mockClient = MockOllamaClient(
            generatedText: "フォールバック後の要約",
            availableModels: ["gemma4:e2b", "llava:latest"],
            generateTextErrorsByCall: [OllamaError.modelNotFound]
        )
        mockClient.configure(host: "http://localhost:11434", model: "gemma4:e4b")

        let service = DailyFeedbackService(
            ollamaClient: mockClient,
            promptBuilder: PromptBuilder(),
            workSessionRepository: env.workSessionRepository,
            tagRepository: env.tagRepository,
            dailyFeedbackRepository: DailyFeedbackRepository(databaseManager: env.databaseManager)
        )

        let result = try await service.generateFeedback(for: targetDate)
        XCTAssertEqual(result.aiFeedback, "フォールバック後の要約")
        XCTAssertEqual(mockClient.configuredModel, "gemma4:e4b")
    }

    func testDailyFeedbackGenerateUsesLocalFallbackWhenResponseIsEmpty() async throws {
        let env = TestEnvironment()
        let targetDate = makeDate(year: 2026, month: 4, day: 18, hour: 10, minute: 0)
        let session = WorkSession(
            startAt: targetDate,
            endAt: targetDate.addingTimeInterval(900),
            aiTitle: "集中作業"
        )
        try env.workSessionRepository.save(session)

        let service = DailyFeedbackService(
            ollamaClient: MockOllamaClient(generatedText: "   "),
            promptBuilder: PromptBuilder(),
            workSessionRepository: env.workSessionRepository,
            tagRepository: env.tagRepository,
            dailyFeedbackRepository: DailyFeedbackRepository(databaseManager: env.databaseManager)
        )

        let result = try await service.generateFeedback(for: targetDate)
        XCTAssertFalse(result.aiFeedback.isEmpty)
        XCTAssertTrue(result.aiFeedback.contains("合計"))
        XCTAssertTrue(result.aiFeedback.contains("集中作業"))

        let fetched = try XCTUnwrap(service.fetchExisting(for: targetDate))
        XCTAssertEqual(fetched.id, result.id)
        XCTAssertEqual(fetched.aiFeedback, result.aiFeedback)
    }

    func testDailyFeedbackGenerateOverwritesExistingWithFallbackWhenResponseIsEmpty() async throws {
        let env = TestEnvironment()
        let targetDate = makeDate(year: 2026, month: 4, day: 18, hour: 10, minute: 0)
        let session = WorkSession(
            startAt: targetDate,
            endAt: targetDate.addingTimeInterval(900),
            aiTitle: "集中作業"
        )
        try env.workSessionRepository.save(session)

        let repo = DailyFeedbackRepository(databaseManager: env.databaseManager)
        try repo.save(DailyFeedback(date: Calendar.current.startOfDay(for: targetDate), aiFeedback: "既存の内容"))

        let service = DailyFeedbackService(
            ollamaClient: MockOllamaClient(generatedText: "\n\n"),
            promptBuilder: PromptBuilder(),
            workSessionRepository: env.workSessionRepository,
            tagRepository: env.tagRepository,
            dailyFeedbackRepository: repo
        )

        let result = try await service.generateFeedback(for: targetDate)
        XCTAssertFalse(result.aiFeedback.isEmpty)
        XCTAssertNotEqual(result.aiFeedback, "既存の内容")

        let existing = try XCTUnwrap(service.fetchExisting(for: targetDate))
        XCTAssertEqual(existing.aiFeedback, result.aiFeedback)
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
        viewModel.currentDate = anchor

        viewModel.loadSummary()

        let calendar = Calendar.current
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: anchor)!.start
        let formatter = DateFormatter()
        formatter.dateFormat = "d"

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
    func testSchedulerDoesNotResumeIfManuallyStoppedDuringInterruption() {
        let env = TestEnvironment()
        env.schedulerService.start(intervalSeconds: 120)

        env.schedulerService.pauseForSystemInterruption()
        XCTAssertFalse(env.schedulerService.isRunning)

        env.schedulerService.stop()
        env.schedulerService.resumeAfterSystemInterruptionIfNeeded()

        XCTAssertFalse(env.schedulerService.isRunning)
    }

    @MainActor
    func testSetupViewModelSaveSettingsDoesNotCompleteSetupFlag() throws {
        let env = TestEnvironment()
        let viewModel = SetupViewModel(
            permissionService: PermissionService(),
            inferenceService: env.inferenceService,
            tagService: TagService(tagRepository: env.tagRepository),
            settingsService: env.settingsService
        )
        viewModel.selectedModel = "llava:test"
        viewModel.retentionDays = 14

        XCTAssertTrue(viewModel.saveSettings())
        XCTAssertFalse(try env.settingsService.loadBool(forKey: "setup_complete"))
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
    let exclusionService: ExclusionService
    let inferenceService: InferenceService
    let captureService: CaptureService
    let schedulerService: SchedulerService
    let aggregationService: AggregationService

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
            fileStorageService: fileStorageService
        )
        schedulerService = SchedulerService(captureService: captureService)
        aggregationService = AggregationService(
            observationRepository: observationRepository,
            checkpointRepository: checkpointRepository,
            workSessionRepository: workSessionRepository,
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

private extension Array {
    var onlyElement: Element? {
        count == 1 ? first : nil
    }
}

private final class MockOllamaClient: OllamaClientProtocol {
    private let generatedText: String?
    private let generatedTextByCall: [String]
    private let generateTextErrorsByCall: [Error]
    private let availableModels: [String]
    private var generateCallIndex: Int = 0
    private var generateTextCallIndex: Int = 0
    private(set) var configuredHost: String = "http://localhost:11434"
    private(set) var configuredModel: String = "gemma4:e4b"
    private(set) var receivedImageCounts: [Int] = []

    init(
        generatedText: String?,
        availableModels: [String] = [],
        generatedTextByCall: [String] = [],
        generateTextErrorsByCall: [Error] = []
    ) {
        self.generatedText = generatedText
        self.generatedTextByCall = generatedTextByCall
        self.availableModels = availableModels
        self.generateTextErrorsByCall = generateTextErrorsByCall
    }

    func configure(host: String, model: String) {
        configuredHost = host
        configuredModel = model
    }

    func testConnection() async throws -> Bool {
        true
    }

    func listModels() async throws -> [String] {
        availableModels
    }

    func generate(prompt: String, imageBase64: String) async throws -> String {
        try await generate(prompt: prompt, imageBase64List: [imageBase64])
    }

    func generate(prompt: String, imageBase64List: [String]) async throws -> String {
        receivedImageCounts.append(imageBase64List.count)

        if !generatedTextByCall.isEmpty {
            guard generateCallIndex < generatedTextByCall.count else {
                throw OllamaError.requestFailed
            }
            defer { generateCallIndex += 1 }
            return generatedTextByCall[generateCallIndex]
        }

        guard let generatedText else { throw OllamaError.requestFailed }
        return generatedText
    }

    func generateText(prompt: String) async throws -> String {
        if generateTextCallIndex < generateTextErrorsByCall.count {
            defer { generateTextCallIndex += 1 }
            throw generateTextErrorsByCall[generateTextCallIndex]
        }
        guard let generatedText else {
            throw OllamaError.requestFailed
        }
        return generatedText
    }
}

private func makeBatchResponse(count: Int, summaryPrefix: String) -> String {
    let results = (1...count).map { index in
        """
        {
          "index": \(index),
          "activity_summary": "\(summaryPrefix)-\(index)",
          "predicted_tags": ["開発"],
          "reason": "test",
          "sensitivity_flag": "none"
        }
        """
    }.joined(separator: ",")

    return """
    {
      "results": [
        \(results)
      ]
    }
    """
}
