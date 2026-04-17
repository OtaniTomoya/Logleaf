import SwiftUI

@MainActor
public final class SummaryViewModel: ObservableObject {
    public enum Period {
        case weekly
        case monthly
    }

    @Published public var period: Period = .weekly
    @Published public var startDate: Date = Date()
    @Published public var tagSummaries: [TagSummary] = []
    @Published public var dailyMinutes: [DailyMinutes] = []
    @Published public var totalMinutes: Int = 0
    @Published public var unclassifiedMinutes: Int = 0
    @Published public var averageConfidence: Double = 0
    @Published public var manualEditRate: Double = 0

    public struct TagSummary: Identifiable {
        public let id: String
        public let tagName: String
        public let colorHex: String?
        public let minutes: Int
        public let percentage: Double
    }

    public struct DailyMinutes: Identifiable {
        public var id: String { dateString }
        public let dateString: String
        public let minutes: Int
    }

    private let workSessionRepository: WorkSessionRepository
    private let tagRepository: TagRepository

    public init(workSessionRepository: WorkSessionRepository, tagRepository: TagRepository) {
        self.workSessionRepository = workSessionRepository
        self.tagRepository = tagRepository
    }

    public func loadSummary() {
        do {
            let calendar = Calendar.current
            let (rangeStart, rangeEnd) = dateRange()

            let sessions = try workSessionRepository.fetchByDateRange(start: rangeStart, end: rangeEnd)
            let allTags = try tagRepository.fetchAll()
            let tagMap = Dictionary(uniqueKeysWithValues: allTags.map { ($0.id, $0) })

            // Total minutes
            totalMinutes = sessions.reduce(0) { $0 + $1.durationMinutes }
            unclassifiedMinutes = 0

            // Tag breakdown
            var tagMinutes: [String: Int] = [:]
            var editedCount = 0

            for session in sessions {
                let wsTags = try workSessionRepository.fetchTags(sessionId: session.id)
                if wsTags.isEmpty {
                    unclassifiedMinutes += session.durationMinutes
                } else {
                    let perTag = session.durationMinutes / max(wsTags.count, 1)
                    for wsTag in wsTags {
                        tagMinutes[wsTag.tagId, default: 0] += perTag
                    }
                }
                if session.status == .edited || session.status == .confirmed {
                    editedCount += 1
                }
            }

            tagSummaries = tagMinutes.compactMap { (tagId, minutes) in
                guard let tag = tagMap[tagId] else { return nil }
                return TagSummary(
                    id: tagId,
                    tagName: tag.name,
                    colorHex: tag.colorHex,
                    minutes: minutes,
                    percentage: totalMinutes > 0 ? Double(minutes) / Double(totalMinutes) * 100 : 0
                )
            }.sorted { $0.minutes > $1.minutes }

            // Daily breakdown
            var dayMap: [Date: Int] = [:]
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "MM/dd"

            var current = rangeStart
            while current < rangeEnd {
                dayMap[current] = 0
                current = calendar.date(byAdding: .day, value: 1, to: current)!
            }

            for session in sessions {
                let dayStart = calendar.startOfDay(for: session.startAt)
                dayMap[dayStart, default: 0] += session.durationMinutes
            }

            dailyMinutes = dayMap.sorted { $0.key < $1.key }.map {
                DailyMinutes(dateString: dateFormatter.string(from: $0.key), minutes: $0.value)
            }

            // Average confidence
            let confidences = sessions.compactMap(\.aiConfidence)
            averageConfidence = confidences.isEmpty ? 0 : confidences.reduce(0, +) / Double(confidences.count)

            // Manual edit rate
            manualEditRate = sessions.isEmpty ? 0 : Double(editedCount) / Double(sessions.count) * 100

        } catch {
            AppLogger.error("Failed to load summary: \(error)")
        }
    }

    public func previousPeriod() {
        let calendar = Calendar.current
        switch period {
        case .weekly:
            startDate = calendar.date(byAdding: .weekOfYear, value: -1, to: startDate)!
        case .monthly:
            startDate = calendar.date(byAdding: .month, value: -1, to: startDate)!
        }
        loadSummary()
    }

    public func nextPeriod() {
        let calendar = Calendar.current
        switch period {
        case .weekly:
            startDate = calendar.date(byAdding: .weekOfYear, value: 1, to: startDate)!
        case .monthly:
            startDate = calendar.date(byAdding: .month, value: 1, to: startDate)!
        }
        loadSummary()
    }

    private func dateRange() -> (Date, Date) {
        let calendar = Calendar.current
        switch period {
        case .weekly:
            let weekStart = calendar.dateInterval(of: .weekOfYear, for: startDate)!.start
            let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart)!
            return (weekStart, weekEnd)
        case .monthly:
            let monthStart = calendar.dateInterval(of: .month, for: startDate)!.start
            let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart)!
            return (monthStart, monthEnd)
        }
    }
}
