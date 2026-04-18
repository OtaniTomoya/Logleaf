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
        let normalizedDate = Calendar.current.startOfDay(for: date)
        let normalizedFeedback = try await resolveFeedbackText(
            prompt: prompt,
            dateString: input.dateString,
            sessionInputs: sessionInputs
        )

        if var existing = try dailyFeedbackRepository.fetchForDate(normalizedDate) {
            existing.aiFeedback = normalizedFeedback
            existing.editedFeedback = nil
            try dailyFeedbackRepository.update(existing)
            return try dailyFeedbackRepository.fetchForDate(normalizedDate) ?? existing
        } else {
            let feedback = DailyFeedback(
                date: normalizedDate,
                aiFeedback: normalizedFeedback
            )
            try dailyFeedbackRepository.save(feedback)
            return feedback
        }
    }

    public func fetchExisting(for date: Date) throws -> DailyFeedback? {
        try dailyFeedbackRepository.fetchForDate(date)
    }

    public func updateFeedback(_ feedback: DailyFeedback) throws {
        try dailyFeedbackRepository.update(feedback)
    }

    private func generateFeedbackTextWithFallback(prompt: String) async throws -> String {
        do {
            return try await ollamaClient.generateText(prompt: prompt)
        } catch OllamaError.modelNotFound {
            let availableModels = try await ollamaClient.listModels()
            guard let fallbackModel = selectFallbackTextModel(from: availableModels) else {
                throw OllamaError.modelNotFound
            }
            let host = ollamaClient.configuredHost
            let originalModel = ollamaClient.configuredModel
            ollamaClient.configure(host: host, model: fallbackModel)
            AppLogger.warning("Daily feedback switched to fallback model: \(fallbackModel)")
            defer {
                ollamaClient.configure(host: host, model: originalModel)
            }
            return try await ollamaClient.generateText(prompt: prompt)
        }
    }

    private func selectFallbackTextModel(from models: [String]) -> String? {
        guard !models.isEmpty else { return nil }

        let rankedKeywords = ["gemma", "qwen", "llama", "mistral", "phi", "llava"]
        for keyword in rankedKeywords {
            if let matched = models.first(where: { $0.lowercased().contains(keyword) }) {
                return matched
            }
        }
        return models[0]
    }

    private func resolveFeedbackText(
        prompt: String,
        dateString: String,
        sessionInputs: [(title: String, tags: [String], startTime: String, endTime: String, durationMinutes: Int)]
    ) async throws -> String {
        let firstText = try await generateFeedbackTextWithFallback(prompt: prompt)
        let firstNormalized = normalizeFeedbackText(firstText)
        if !firstNormalized.isEmpty {
            return firstNormalized
        }

        AppLogger.warning("Daily feedback response was empty. Retrying with strict non-empty instruction.")
        let retryPrompt = prompt + "\n\n重要: 出力は必ず日本語で1文字以上にしてください。空文字は禁止です。"
        let retryText = try await generateFeedbackTextWithFallback(prompt: retryPrompt)
        let retryNormalized = normalizeFeedbackText(retryText)
        if !retryNormalized.isEmpty {
            return retryNormalized
        }

        AppLogger.warning("Daily feedback response remained empty. Using local fallback summary.")
        return buildLocalFallbackFeedback(dateString: dateString, sessions: sessionInputs)
    }

    private func normalizeFeedbackText(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func buildLocalFallbackFeedback(
        dateString: String,
        sessions: [(title: String, tags: [String], startTime: String, endTime: String, durationMinutes: Int)]
    ) -> String {
        let totalMinutes = sessions.reduce(0) { $0 + $1.durationMinutes }
        let totalHours = totalMinutes / 60
        let remainMinutes = totalMinutes % 60
        let totalText = totalHours > 0 ? "\(totalHours)時間\(remainMinutes)分" : "\(remainMinutes)分"

        var seenTitles = Set<String>()
        var orderedTitles: [String] = []
        for title in sessions.map(\.title).filter({ !$0.isEmpty }) {
            if seenTitles.insert(title).inserted {
                orderedTitles.append(title)
            }
        }
        let topTitles = orderedTitles.prefix(3)
        let titleText = topTitles.isEmpty ? "複数の作業" : topTitles.joined(separator: "、")

        let tagCounts = Dictionary(grouping: sessions.flatMap(\.tags), by: { $0 })
            .mapValues(\.count)
        let topTags = tagCounts
            .sorted { lhs, rhs in
                if lhs.value == rhs.value { return lhs.key < rhs.key }
                return lhs.value > rhs.value
            }
            .prefix(2)
            .map(\.key)
        let tagText = topTags.isEmpty ? "タグなし" : topTags.joined(separator: "、")

        return "\(dateString)の作業ログを集計しました。合計\(totalText)で、主な内容は\(titleText)です。記録タグは\(tagText)が中心でした。"
    }
}

public enum FeedbackError: Error, LocalizedError, Equatable {
    case noSessions

    public var errorDescription: String? {
        switch self {
        case .noSessions: return "この日の作業記録がありません"
        }
    }
}
