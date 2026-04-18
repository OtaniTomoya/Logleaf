import SwiftUI

@MainActor
public final class SessionDetailViewModel: ObservableObject {
    @Published public var session: WorkSession
    @Published public var observations: [Observation] = []
    @Published public var tags: [Tag] = []
    @Published public var allTags: [Tag] = []
    @Published public var editedTitle: String = ""
    @Published public var editedNote: String = ""
    @Published public var isEditing = false

    private let workSessionRepository: WorkSessionRepository
    private let observationRepository: ObservationRepository
    private let tagRepository: TagRepository
    private let inferenceService: InferenceService

    public init(session: WorkSession,
         workSessionRepository: WorkSessionRepository,
         observationRepository: ObservationRepository,
         tagRepository: TagRepository,
         inferenceService: InferenceService) {
        self.session = session
        self.workSessionRepository = workSessionRepository
        self.observationRepository = observationRepository
        self.tagRepository = tagRepository
        self.inferenceService = inferenceService
        self.editedTitle = session.displayTitle
        self.editedNote = session.finalNote ?? ""
    }

    public func loadDetails() {
        do {
            let obsIds = try workSessionRepository.fetchObservationIds(sessionId: session.id)
            observations = obsIds.compactMap { try? observationRepository.fetch(id: $0) }

            let wsTags = try workSessionRepository.fetchTags(sessionId: session.id)
            allTags = try tagRepository.fetchAll()
            let tagMap = Dictionary(uniqueKeysWithValues: allTags.map { ($0.id, $0) })
            tags = wsTags.compactMap { tagMap[$0.tagId] }
        } catch {
            AppLogger.error("Failed to load session details: \(error)")
        }
    }

    public func saveEdits() {
        do {
            session.finalTitle = editedTitle
            session.finalNote = editedNote.isEmpty ? nil : editedNote
            session.status = .edited
            try workSessionRepository.update(session)
            isEditing = false
        } catch {
            AppLogger.error("Failed to save session edits: \(error)")
        }
    }

    public func updateTags(tagIds: Set<String>) {
        do {
            try workSessionRepository.deleteTagsForSession(session.id, source: .user)
            let newTags = tagIds.map { WorkSessionTag(workSessionId: session.id, tagId: $0, source: .user) }
            try workSessionRepository.saveTags(newTags)
            loadDetails()
        } catch {
            AppLogger.error("Failed to update tags: \(error)")
        }
    }

    public func reInferObservation(id: String) {
        Task {
            await inferenceService.reInfer(observationId: id)
            loadDetails()
        }
    }

    public func hideObservation(id: String) {
        do {
            if var obs = try observationRepository.fetch(id: id) {
                obs.isUserHidden = true
                try observationRepository.update(obs)
                loadDetails()
            }
        } catch {
            AppLogger.error("Failed to hide observation: \(error)")
        }
    }
}
