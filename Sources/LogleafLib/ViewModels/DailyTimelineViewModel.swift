import SwiftUI

@MainActor
public final class DailyTimelineViewModel: ObservableObject {
    @Published public var selectedDate: Date = Date()
    @Published public var sessions: [WorkSession] = []
    @Published public var sessionTags: [String: [Tag]] = [:]
    @Published public var isLoading = false

    private let workSessionRepository: WorkSessionRepository
    private let tagRepository: TagRepository
    private let aggregationService: AggregationService
    private let observationRepository: ObservationRepository

    public init(workSessionRepository: WorkSessionRepository,
         tagRepository: TagRepository,
         aggregationService: AggregationService,
         observationRepository: ObservationRepository) {
        self.workSessionRepository = workSessionRepository
        self.tagRepository = tagRepository
        self.aggregationService = aggregationService
        self.observationRepository = observationRepository
    }

    public func loadSessions() {
        isLoading = true
        do {
            sessions = try workSessionRepository.fetchForDate(selectedDate)
            let allTags = try tagRepository.fetchAll()
            let tagMap = Dictionary(uniqueKeysWithValues: allTags.map { ($0.id, $0) })

            sessionTags = [:]
            for session in sessions {
                let wsTags = try workSessionRepository.fetchTags(sessionId: session.id)
                sessionTags[session.id] = wsTags.compactMap { tagMap[$0.tagId] }
            }
        } catch {
            AppLogger.error("Failed to load sessions: \(error)")
        }
        isLoading = false
    }

    public func rebuildSessions() {
        isLoading = true
        do {
            try aggregationService.buildCheckpoints(for: selectedDate)
            _ = try aggregationService.buildSessions(for: selectedDate)
            loadSessions()
        } catch {
            AppLogger.error("Failed to rebuild sessions: \(error)")
        }
        isLoading = false
    }

    public func deleteSession(id: String) {
        do {
            try workSessionRepository.delete(id: id)
            loadSessions()
        } catch {
            AppLogger.error("Failed to delete session: \(error)")
        }
    }

    public func mergeSessions(ids: [String]) {
        do {
            try aggregationService.mergeSessions(sessionIds: ids)
            loadSessions()
        } catch {
            AppLogger.error("Failed to merge sessions: \(error)")
        }
    }

    public func previousDay() {
        selectedDate = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate
        loadSessions()
    }

    public func nextDay() {
        selectedDate = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate) ?? selectedDate
        loadSessions()
    }

    public func goToToday() {
        selectedDate = Date()
        loadSessions()
    }
}
