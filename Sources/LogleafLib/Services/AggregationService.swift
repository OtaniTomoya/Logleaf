import Foundation

public final class AggregationService {
    private let observationRepository: ObservationRepository
    private let checkpointRepository: CheckpointRepository
    private let workSessionRepository: WorkSessionRepository
    private let fileStorageService: FileStorageService

    private let sessionGapThresholdSeconds: TimeInterval = 180 // 3 minutes

    public init(observationRepository: ObservationRepository,
         checkpointRepository: CheckpointRepository,
         workSessionRepository: WorkSessionRepository,
         fileStorageService: FileStorageService) {
        self.observationRepository = observationRepository
        self.checkpointRepository = checkpointRepository
        self.workSessionRepository = workSessionRepository
        self.fileStorageService = fileStorageService
    }

    // MARK: - Checkpoint Generation

    public func buildCheckpoints(for date: Date, intervalMinutes: Int = 5) throws {
        let observations = try observationRepository.fetchForDate(date)
        guard !observations.isEmpty else { return }

        // Clear existing checkpoints for the date
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        try checkpointRepository.deleteByDateRange(start: start, end: end)

        // Group observations into time windows
        let windowSize = TimeInterval(intervalMinutes * 60)
        var currentWindowStart = observations[0].capturedAt
        var currentGroup: [Observation] = []

        for obs in observations {
            if obs.capturedAt.timeIntervalSince(currentWindowStart) > windowSize && !currentGroup.isEmpty {
                try saveCheckpoint(from: currentGroup)
                currentGroup = []
                currentWindowStart = obs.capturedAt
            }
            currentGroup.append(obs)
        }

        if !currentGroup.isEmpty {
            try saveCheckpoint(from: currentGroup)
        }
    }

    private func saveCheckpoint(from observations: [Observation]) throws {
        guard let first = observations.first, let last = observations.last else { return }

        // Determine representative summary by majority vote
        let summaries = observations.compactMap(\.aiSummary)
        let representative = summaries.first ?? ""

        // Calculate average confidence
        let confidences = observations.compactMap(\.aiConfidence)
        let avgConfidence = confidences.isEmpty ? 0.0 : confidences.reduce(0, +) / Double(confidences.count)

        let checkpoint = Checkpoint(
            startAt: first.capturedAt,
            endAt: last.capturedAt,
            title: representative,
            confidence: avgConfidence,
            sourceObservationCount: observations.count
        )
        try checkpointRepository.save(checkpoint)

        // Collect and save tags with weighted scores
        let tagScores = aggregateTagScores(from: observations)
        var checkpointTags: [CheckpointTag] = []
        for (tagId, score) in tagScores {
            checkpointTags.append(CheckpointTag(
                checkpointId: checkpoint.id,
                tagId: tagId,
                score: score,
                source: .ai
            ))
        }
        try checkpointRepository.saveTags(checkpointTags)
    }

    // MARK: - Session Generation

    public func buildSessions(for date: Date) throws -> [WorkSession] {
        let observations = try observationRepository.fetchForDate(date)
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        let existingSessions = try workSessionRepository.fetchByDateRange(start: start, end: end)
        let protectedSessions = try existingSessions.filter(shouldPreserveSession)
        let sessionsToRebuild = existingSessions.filter { session in
            !protectedSessions.contains(where: { $0.id == session.id })
        }
        let protectedObservationIds = try Set(
            protectedSessions.flatMap { try workSessionRepository.fetchObservationIds(sessionId: $0.id) }
        )
        let observationsToRebuild = observations.filter { !protectedObservationIds.contains($0.id) }

        try workSessionRepository.hardDelete(ids: sessionsToRebuild.map(\.id))

        guard !observationsToRebuild.isEmpty else {
            return protectedSessions.sorted { $0.startAt < $1.startAt }
        }

        // Group observations into sessions based on time gaps and tag similarity
        var sessions: [WorkSession] = []
        var currentGroup: [Observation] = [observationsToRebuild[0]]

        for i in 1..<observationsToRebuild.count {
            let prev = observationsToRebuild[i - 1]
            let curr = observationsToRebuild[i]
            let gap = curr.capturedAt.timeIntervalSince(prev.capturedAt)

            if gap > sessionGapThresholdSeconds || !hasSimilarTags(prev, curr) {
                let session = try createSession(from: currentGroup)
                sessions.append(session)
                currentGroup = []
            }
            currentGroup.append(curr)
        }

        if !currentGroup.isEmpty {
            let session = try createSession(from: currentGroup)
            sessions.append(session)
        }

        return (protectedSessions + sessions).sorted { $0.startAt < $1.startAt }
    }

    private func createSession(from observations: [Observation]) throws -> WorkSession {
        guard let first = observations.first, let last = observations.last else {
            fatalError("Cannot create session from empty observations")
        }

        let summaries = observations.compactMap(\.aiSummary)
        let title = summaries.first ?? "未分類"

        let confidences = observations.compactMap(\.aiConfidence)
        let avgConfidence = confidences.isEmpty ? 0.0 : confidences.reduce(0, +) / Double(confidences.count)

        // Select representative image (highest confidence)
        let representative = observations.max(by: { ($0.aiConfidence ?? 0) < ($1.aiConfidence ?? 0) })
        let repImagePath = representative?.imagePath

        let session = WorkSession(
            startAt: first.capturedAt,
            endAt: last.capturedAt,
            aiTitle: title,
            aiConfidence: avgConfidence,
            representativeImagePath: repImagePath
        )
        try workSessionRepository.save(session)

        // Link observations to session
        for obs in observations {
            try workSessionRepository.saveSessionObservation(
                SessionObservation(workSessionId: session.id, observationId: obs.id)
            )
        }

        // Save session tags
        let tagScores = aggregateTagScores(from: observations)
        var sessionTags: [WorkSessionTag] = []
        for (tagId, _) in tagScores {
            sessionTags.append(WorkSessionTag(
                workSessionId: session.id,
                tagId: tagId,
                source: .ai
            ))
        }
        try workSessionRepository.saveTags(sessionTags)

        return session
    }

    // MARK: - Session Merge / Split

    public func mergeSessions(sessionIds: [String]) throws {
        let sessions = try sessionIds.compactMap { try workSessionRepository.fetch(id: $0) }
        guard sessions.count >= 2 else { return }

        let sorted = sessions.sorted { $0.startAt < $1.startAt }
        let observationIds = try sorted.flatMap { try workSessionRepository.fetchObservationIds(sessionId: $0.id) }
        let observations = try observationIds.compactMap { try observationRepository.fetch(id: $0) }
        let carriedTags = try uniqueMergedTags(from: sorted)
        let confidenceValues = sorted.compactMap(\.aiConfidence)
        let mergedConfidence = confidenceValues.isEmpty
            ? nil
            : confidenceValues.reduce(0, +) / Double(confidenceValues.count)
        let merged = WorkSession(
            startAt: sorted.first!.startAt,
            endAt: sorted.last!.endAt,
            aiTitle: sorted.first!.displayTitle,
            aiConfidence: mergedConfidence,
            status: .confirmed
        )
        try workSessionRepository.save(merged)

        // Move observation links
        for session in sorted {
            let obsIds = try workSessionRepository.fetchObservationIds(sessionId: session.id)
            for obsId in obsIds {
                try workSessionRepository.saveSessionObservation(
                    SessionObservation(workSessionId: merged.id, observationId: obsId)
                )
            }
            try workSessionRepository.delete(id: session.id)
        }

        if !carriedTags.isEmpty {
            try workSessionRepository.saveTags(
                carriedTags.map { WorkSessionTag(workSessionId: merged.id, tagId: $0.tagId, source: $0.source) }
            )
        } else {
            let tagScores = aggregateTagScores(from: observations)
            try workSessionRepository.saveTags(
                tagScores.map { WorkSessionTag(workSessionId: merged.id, tagId: $0.0, source: .ai) }
            )
        }
    }

    public func splitSession(sessionId: String, at splitTime: Date) throws {
        guard try workSessionRepository.fetch(id: sessionId) != nil else { return }
        let obsIds = try workSessionRepository.fetchObservationIds(sessionId: sessionId)
        let observations = try obsIds
            .compactMap { try observationRepository.fetch(id: $0) }
            .sorted(by: { $0.capturedAt < $1.capturedAt })

        let before = observations.filter { $0.capturedAt < splitTime }
        let after = observations.filter { $0.capturedAt >= splitTime }

        guard !before.isEmpty, !after.isEmpty else { return }

        // Delete original
        try workSessionRepository.delete(id: sessionId)

        // Create two new sessions
        _ = try createSession(from: before)
        _ = try createSession(from: after)
    }

    // MARK: - Helpers

    private func hasSimilarTags(_ a: Observation, _ b: Observation) -> Bool {
        guard let aTags = try? observationRepository.fetchTags(observationId: a.id),
              let bTags = try? observationRepository.fetchTags(observationId: b.id) else {
            return true // If we can't check, assume similar
        }

        let aTagIds = Set(aTags.map(\.tagId))
        let bTagIds = Set(bTags.map(\.tagId))

        if aTagIds.isEmpty && bTagIds.isEmpty { return true }
        if aTagIds.isEmpty || bTagIds.isEmpty { return false }

        let intersection = aTagIds.intersection(bTagIds)
        let union = aTagIds.union(bTagIds)

        return Double(intersection.count) / Double(union.count) > 0.3
    }

    private func aggregateTagScores(from observations: [Observation]) -> [(String, Double)] {
        var tagCounts: [String: (count: Int, totalScore: Double)] = [:]

        for obs in observations {
            guard let tags = try? observationRepository.fetchTags(observationId: obs.id) else { continue }
            for tag in tags {
                let existing = tagCounts[tag.tagId] ?? (count: 0, totalScore: 0)
                tagCounts[tag.tagId] = (count: existing.count + 1, totalScore: existing.totalScore + tag.score)
            }
        }

        return tagCounts.map { (tagId, data) in
            (tagId, data.totalScore / Double(data.count))
        }.sorted { $0.1 > $1.1 }
    }

    private func shouldPreserveSession(_ session: WorkSession) throws -> Bool {
        if session.status == .edited { return true }
        if session.finalTitle != nil || session.finalNote != nil { return true }

        let tags = try workSessionRepository.fetchTags(sessionId: session.id)
        return tags.contains { $0.source == .user }
    }

    private func uniqueMergedTags(from sessions: [WorkSession]) throws -> [WorkSessionTag] {
        var seen = Set<String>()
        var mergedTags: [WorkSessionTag] = []

        for session in sessions {
            let tags = try workSessionRepository.fetchTags(sessionId: session.id)
            for tag in tags {
                let key = "\(tag.tagId)::\(tag.source.rawValue)"
                if seen.insert(key).inserted {
                    mergedTags.append(tag)
                }
            }
        }

        return mergedTags
    }
}
