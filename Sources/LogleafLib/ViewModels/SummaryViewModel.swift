import SwiftUI

@MainActor
public final class SummaryViewModel: ObservableObject {
    public enum Period {
        case weekly
        case monthly
    }

    @Published public var period: Period = .monthly
    @Published public var currentDate: Date = Date()
    @Published public var tagSummaries: [TagSummary] = []
    @Published public var dailyMinutes: [DailyMinutes] = []
    @Published public var calendarDays: [CalendarDay] = []
    @Published public var selectedDay: Date?
    @Published public var selectedDaySessions: [WorkSession] = []
    @Published public var selectedDaySessionTags: [String: [Tag]] = [:]

    public struct TagSummary: Identifiable {
        public let id: String
        public let tagName: String
        public let colorHex: String?
        public let minutes: Int
        public let percentage: Double
    }

    public struct DailyMinutes: Identifiable {
        public var id: String { dateString }
        public let date: Date
        public let dateString: String
        public let minutes: Int
    }

    public struct CalendarDay: Identifiable {
        public let id: String
        public let date: Date
        public let day: Int
        public let isCurrentMonth: Bool
        public let isInActivePeriod: Bool
        public let minutes: Int
        public let topTags: [TagInfo]

        public struct TagInfo {
            public let name: String
            public let colorHex: String?
        }
    }

    private let workSessionRepository: WorkSessionRepository
    private let tagRepository: TagRepository

    public init(workSessionRepository: WorkSessionRepository, tagRepository: TagRepository) {
        self.workSessionRepository = workSessionRepository
        self.tagRepository = tagRepository
    }

    public var monthTitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy年M月"
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter.string(from: currentDate)
    }

    public var periodLabel: String {
        switch period {
        case .monthly:
            return monthTitle
        case .weekly:
            let (start, end) = periodDateRange()
            let formatter = DateFormatter()
            formatter.dateFormat = "M/d"
            formatter.locale = Locale(identifier: "ja_JP")
            let endDay = Calendar.current.date(byAdding: .day, value: -1, to: end)!
            return "\(formatter.string(from: start)) – \(formatter.string(from: endDay))"
        }
    }

    // MARK: - Actions

    public func loadSummary() {
        do {
            let calendar = Calendar.current
            let (monthStart, monthEnd) = monthRange()
            let (periodStart, periodEnd) = periodDateRange()
            let calendarRange = calendarDateRange()
            let fetchStart = min(monthStart, min(periodStart, calendarRange.0))
            let fetchEnd = max(monthEnd, max(periodEnd, calendarRange.1))

            let allSessions = try workSessionRepository.fetchByDateRange(start: fetchStart, end: fetchEnd)
            let allTags = try tagRepository.fetchAll()
            let tagMap = Dictionary(uniqueKeysWithValues: allTags.map { ($0.id, $0) })

            // Per-session tag cache
            var sessionTagCache: [String: [WorkSessionTag]] = [:]
            var dayMap: [Date: Int] = [:]
            var dayTagMinutes: [Date: [String: Int]] = [:]

            // Initialize days for calendar range
            let (calStart, calEnd) = calendarRange
            var current = calStart
            while current < calEnd {
                dayMap[current] = 0
                current = calendar.date(byAdding: .day, value: 1, to: current)!
            }

            for session in allSessions {
                let dayStart = calendar.startOfDay(for: session.startAt)
                let wsTags = try workSessionRepository.fetchTags(sessionId: session.id)
                sessionTagCache[session.id] = wsTags

                if dayStart >= calStart && dayStart < calEnd {
                    dayMap[dayStart, default: 0] += session.durationMinutes
                    if !wsTags.isEmpty {
                        let perTag = session.durationMinutes / max(wsTags.count, 1)
                        for wsTag in wsTags {
                            dayTagMinutes[dayStart, default: [:]][wsTag.tagId, default: 0] += perTag
                        }
                    }
                }
            }

            // Build calendar grid
            buildCalendarDays(dayMap: dayMap, dayTagMinutes: dayTagMinutes, tagMap: tagMap)

            // Period-scoped data for tag breakdown and daily chart
            let periodSessions = allSessions.filter { $0.startAt >= periodStart && $0.startAt < periodEnd }
            let periodTotal = periodSessions.reduce(0) { $0 + $1.durationMinutes }

            var periodTagMinutes: [String: Int] = [:]
            for session in periodSessions {
                let wsTags = sessionTagCache[session.id] ?? []
                if !wsTags.isEmpty {
                    let perTag = session.durationMinutes / max(wsTags.count, 1)
                    for wsTag in wsTags {
                        periodTagMinutes[wsTag.tagId, default: 0] += perTag
                    }
                }
            }

            tagSummaries = periodTagMinutes.compactMap { (tagId, minutes) in
                guard let tag = tagMap[tagId] else { return nil }
                return TagSummary(
                    id: tagId,
                    tagName: tag.name,
                    colorHex: tag.colorHex,
                    minutes: minutes,
                    percentage: periodTotal > 0 ? Double(minutes) / Double(periodTotal) * 100 : 0
                )
            }.sorted { $0.minutes > $1.minutes }

            // Daily chart (period-scoped, day number only)
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "d"

            // Build day entries for the period range
            var periodDayMap: [Date: Int] = [:]
            var d = periodStart
            while d < periodEnd {
                periodDayMap[d] = 0
                d = calendar.date(byAdding: .day, value: 1, to: d)!
            }
            for session in periodSessions {
                let dayStart = calendar.startOfDay(for: session.startAt)
                periodDayMap[dayStart, default: 0] += session.durationMinutes
            }

            dailyMinutes = periodDayMap.sorted { $0.key < $1.key }.map {
                DailyMinutes(date: $0.key, dateString: dateFormatter.string(from: $0.key), minutes: $0.value)
            }

        } catch {
            AppLogger.error("Failed to load summary: \(error)")
        }
    }

    public func selectDay(_ date: Date) {
        selectedDay = date
        loadSelectedDaySessions()
    }

    public func previousPeriod() {
        let calendar = Calendar.current
        switch period {
        case .weekly:
            currentDate = calendar.date(byAdding: .weekOfYear, value: -1, to: currentDate)!
        case .monthly:
            currentDate = calendar.date(byAdding: .month, value: -1, to: currentDate)!
        }
        loadSummary()
    }

    public func nextPeriod() {
        let calendar = Calendar.current
        switch period {
        case .weekly:
            currentDate = calendar.date(byAdding: .weekOfYear, value: 1, to: currentDate)!
        case .monthly:
            currentDate = calendar.date(byAdding: .month, value: 1, to: currentDate)!
        }
        loadSummary()
    }

    // MARK: - Private

    private func loadSelectedDaySessions() {
        guard let day = selectedDay else {
            selectedDaySessions = []
            selectedDaySessionTags = [:]
            return
        }
        do {
            selectedDaySessions = try workSessionRepository.fetchForDate(day)
            let allTags = try tagRepository.fetchAll()
            let tagMap = Dictionary(uniqueKeysWithValues: allTags.map { ($0.id, $0) })

            selectedDaySessionTags = [:]
            for session in selectedDaySessions {
                let wsTags = try workSessionRepository.fetchTags(sessionId: session.id)
                selectedDaySessionTags[session.id] = wsTags.compactMap { tagMap[$0.tagId] }
            }
        } catch {
            AppLogger.error("Failed to load sessions for selected day: \(error)")
        }
    }

    private func buildCalendarDays(
        dayMap: [Date: Int],
        dayTagMinutes: [Date: [String: Int]],
        tagMap: [String: Tag]
    ) {
        let calendar = Calendar.current
        let (periodStart, periodEnd) = periodDateRange()

        switch period {
        case .weekly:
            // Weekly: show only 7 days
            var days: [CalendarDay] = []
            var current = periodStart
            while current < periodEnd {
                let day = calendar.component(.day, from: current)
                let topTags = resolveTopTags(
                    dayTagMinutes: dayTagMinutes[current],
                    tagMap: tagMap,
                    limit: 2
                )
                days.append(CalendarDay(
                    id: "week-\(day)",
                    date: current,
                    day: day,
                    isCurrentMonth: true,
                    isInActivePeriod: true,
                    minutes: dayMap[current] ?? 0,
                    topTags: topTags
                ))
                current = calendar.date(byAdding: .day, value: 1, to: current)!
            }
            calendarDays = days

        case .monthly:
            let (monthStart, monthEnd) = monthRange()
            let firstWeekday = calendar.component(.weekday, from: monthStart)
            let leadingCount = (firstWeekday - calendar.firstWeekday + 7) % 7

            var days: [CalendarDay] = []

            // Leading days from previous month
            for i in (0..<leadingCount).reversed() {
                let date = calendar.date(byAdding: .day, value: -(i + 1), to: monthStart)!
                days.append(CalendarDay(
                    id: "prev-\(i)",
                    date: date,
                    day: calendar.component(.day, from: date),
                    isCurrentMonth: false,
                    isInActivePeriod: date >= periodStart && date < periodEnd,
                    minutes: 0,
                    topTags: []
                ))
            }

            // Current month days
            var current = monthStart
            while current < monthEnd {
                let day = calendar.component(.day, from: current)
                let topTags = resolveTopTags(
                    dayTagMinutes: dayTagMinutes[current],
                    tagMap: tagMap,
                    limit: 2
                )
                days.append(CalendarDay(
                    id: "cur-\(day)",
                    date: current,
                    day: day,
                    isCurrentMonth: true,
                    isInActivePeriod: current >= periodStart && current < periodEnd,
                    minutes: dayMap[current] ?? 0,
                    topTags: topTags
                ))
                current = calendar.date(byAdding: .day, value: 1, to: current)!
            }

            // Trailing days
            let remainder = days.count % 7
            if remainder > 0 {
                let trailingCount = 7 - remainder
                for i in 0..<trailingCount {
                    let date = calendar.date(byAdding: .day, value: i, to: monthEnd)!
                    days.append(CalendarDay(
                        id: "next-\(i)",
                        date: date,
                        day: calendar.component(.day, from: date),
                        isCurrentMonth: false,
                        isInActivePeriod: date >= periodStart && date < periodEnd,
                        minutes: 0,
                        topTags: []
                    ))
                }
            }

            calendarDays = days
        }
    }

    private func resolveTopTags(
        dayTagMinutes: [String: Int]?,
        tagMap: [String: Tag],
        limit: Int
    ) -> [CalendarDay.TagInfo] {
        guard let tagMinutes = dayTagMinutes else { return [] }
        return tagMinutes
            .sorted { $0.value > $1.value }
            .prefix(limit)
            .compactMap { (tagId, _) in
                guard let tag = tagMap[tagId] else { return nil }
                return CalendarDay.TagInfo(name: tag.name, colorHex: tag.colorHex)
            }
    }

    private func monthRange() -> (Date, Date) {
        let calendar = Calendar.current
        let monthStart = calendar.dateInterval(of: .month, for: currentDate)!.start
        let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart)!
        return (monthStart, monthEnd)
    }

    private func periodDateRange() -> (Date, Date) {
        let calendar = Calendar.current
        switch period {
        case .weekly:
            let weekStart = calendar.dateInterval(of: .weekOfYear, for: currentDate)!.start
            let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart)!
            return (weekStart, weekEnd)
        case .monthly:
            return monthRange()
        }
    }

    private func calendarDateRange() -> (Date, Date) {
        switch period {
        case .weekly:
            return periodDateRange()
        case .monthly:
            return monthRange()
        }
    }
}
