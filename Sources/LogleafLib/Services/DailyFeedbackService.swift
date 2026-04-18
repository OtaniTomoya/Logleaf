import Foundation

public final class DailyFeedbackService {
    private let ollamaClient: OllamaClientProtocol
    private let promptBuilder: PromptBuilder
    private let workSessionRepository: WorkSessionRepository
    private let tagRepository: TagRepository
    private let dailyFeedbackRepository: DailyFeedbackRepository

    public init(ollamaClient: OllamaClientProtocol,
                promptBuilder: PromptBuilder,
                workSessionRepository: WorkSessionRepository,
                tagRepository: TagRepository,
                dailyFeedbackRepository: DailyFeedbackRepository) {
        self.ollamaClient = ollamaClient
        self.promptBuilder = promptBuilder
        self.workSessionRepository = workSessionRepository
        self.tagRepository = tagRepository
        self.dailyFeedbackRepository = dailyFeedbackRepository
    }

    public func generateFeedback(for date: Date) async throws -> DailyFeedback {
        let sessions = try workSessionRepository.fetchForDate(date)
        guard !sessions.isEmpty else {
            throw FeedbackError.noSessions
        }

        let allTags = try tagRepository.fetchAll()
        let tagMap = Dictionary(uniqueKeysWithValues: allTags.map { ($0.id, $0.name) })

        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy年M月d日（E）"
        dateFormatter.locale = Locale(identifier: "ja_JP")

        let sessionInputs: [(title: String, tags: [String], startTime: String, endTime: String, durationMinutes: Int)] = try sessions.map { session in
            let wsTags = try workSessionRepository.fetchTags(sessionId: session.id)
            let tagNames = wsTags.compactMap { tagMap[$0.tagId] }
            return (
                title: session.displayTitle,
                tags: tagNames,
                startTime: timeFormatter.string(from: session.startAt),
                endTime: timeFormatter.string(from: session.endAt),
                durationMinutes: session.durationMinutes
            )
        }

        let input = PromptBuilder.FeedbackInput(
            dateString: dateFormatter.string(from: date),
            sessions: sessionInputs
        )

        let prompt = promptBuilder.buildFeedbackPrompt(input: input)
        let responseText = try await ollamaClient.generateText(prompt: prompt)

        let feedback = DailyFeedback(
            date: Calendar.current.startOfDay(for: date),
            aiFeedback: responseText.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        try dailyFeedbackRepository.save(feedback)

        return feedback
    }

    public func fetchExisting(for date: Date) throws -> DailyFeedback? {
        try dailyFeedbackRepository.fetchForDate(date)
    }

    public func updateFeedback(_ feedback: DailyFeedback) throws {
        try dailyFeedbackRepository.update(feedback)
    }
}

public enum FeedbackError: Error, LocalizedError {
    case noSessions

    public var errorDescription: String? {
        switch self {
        case .noSessions: return "この日の作業記録がありません"
        }
    }
}
