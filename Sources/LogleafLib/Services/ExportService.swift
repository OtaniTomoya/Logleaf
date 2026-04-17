import Foundation

public final class ExportService {
    private let workSessionRepository: WorkSessionRepository
    private let observationRepository: ObservationRepository
    private let tagRepository: TagRepository
    private let exportRepository: ExportRepository
    private let fileStorageService: FileStorageService

    public init(workSessionRepository: WorkSessionRepository,
         observationRepository: ObservationRepository,
         tagRepository: TagRepository,
         exportRepository: ExportRepository,
         fileStorageService: FileStorageService) {
        self.workSessionRepository = workSessionRepository
        self.observationRepository = observationRepository
        self.tagRepository = tagRepository
        self.exportRepository = exportRepository
        self.fileStorageService = fileStorageService
    }

    public func exportCSV(filter: ExportFilter) throws -> URL {
        let sessions = try fetchFilteredSessions(filter: filter)
        let allTags = try tagRepository.fetchAll()
        let tagMap = Dictionary(uniqueKeysWithValues: allTags.map { ($0.id, $0.name) })

        var csv = "開始時刻,終了時刻,タイトル,タグ,信頼度,ステータス,時間(分)\n"
        for session in sessions {
            let tags = try workSessionRepository.fetchTags(sessionId: session.id)
            let tagNames = tags.compactMap { tagMap[$0.tagId] }.joined(separator: "; ")
            let title = session.displayTitle.replacingOccurrences(of: ",", with: "，")

            let formatter = ISO8601DateFormatter()
            let startStr = formatter.string(from: session.startAt)
            let endStr = formatter.string(from: session.endAt)

            csv += "\(startStr),\(endStr),\(title),\(tagNames),\(session.aiConfidence ?? 0),\(session.status.rawValue),\(session.durationMinutes)\n"
        }

        let url = fileStorageService.exportFilePath(
            startDate: filter.startDate ?? Date.distantPast,
            endDate: filter.endDate ?? Date(),
            format: .csv
        )
        try csv.write(to: url, atomically: true, encoding: .utf8)

        let record = ExportRecord(format: .csv, targetPath: url.path)
        try exportRepository.save(record)

        return url
    }

    public func exportMarkdown(filter: ExportFilter) throws -> URL {
        let sessions = try fetchFilteredSessions(filter: filter)
        let allTags = try tagRepository.fetchAll()
        let tagMap = Dictionary(uniqueKeysWithValues: allTags.map { ($0.id, $0.name) })

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"

        var md = "# 作業記録\n\n"

        // Group by date
        let grouped = Dictionary(grouping: sessions) { session in
            dateFormatter.string(from: session.startAt)
        }

        for date in grouped.keys.sorted() {
            md += "## \(date)\n\n"
            md += "| 時間 | タイトル | タグ | 信頼度 |\n"
            md += "|------|---------|------|--------|\n"

            for session in grouped[date]! {
                let tags = try workSessionRepository.fetchTags(sessionId: session.id)
                let tagNames = tags.compactMap { tagMap[$0.tagId] }.joined(separator: ", ")
                let start = timeFormatter.string(from: session.startAt)
                let end = timeFormatter.string(from: session.endAt)
                let confidence = session.aiConfidence.map { String(format: "%.0f%%", $0 * 100) } ?? "-"

                md += "| \(start)-\(end) | \(session.displayTitle) | \(tagNames) | \(confidence) |\n"
            }
            md += "\n"
        }

        let url = fileStorageService.exportFilePath(
            startDate: filter.startDate ?? Date.distantPast,
            endDate: filter.endDate ?? Date(),
            format: .markdown
        )
        try md.write(to: url, atomically: true, encoding: .utf8)

        let record = ExportRecord(format: .markdown, targetPath: url.path)
        try exportRepository.save(record)

        return url
    }

    public func exportJSON(filter: ExportFilter) throws -> URL {
        let sessions = try fetchFilteredSessions(filter: filter)
        let allTags = try tagRepository.fetchAll()
        let tagMap = Dictionary(uniqueKeysWithValues: allTags.map { ($0.id, $0.name) })

        var jsonSessions: [[String: Any]] = []
        let formatter = ISO8601DateFormatter()

        for session in sessions {
            let tags = try workSessionRepository.fetchTags(sessionId: session.id)
            let tagNames = tags.compactMap { tagMap[$0.tagId] }

            let dict: [String: Any] = [
                "id": session.id,
                "start_at": formatter.string(from: session.startAt),
                "end_at": formatter.string(from: session.endAt),
                "title": session.displayTitle,
                "tags": tagNames,
                "confidence": session.aiConfidence ?? 0,
                "status": session.status.rawValue,
                "duration_minutes": session.durationMinutes,
                "note": session.finalNote ?? ""
            ]
            jsonSessions.append(dict)
        }

        let json: [String: Any] = [
            "exported_at": formatter.string(from: Date()),
            "sessions": jsonSessions
        ]

        let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])

        let url = fileStorageService.exportFilePath(
            startDate: filter.startDate ?? Date.distantPast,
            endDate: filter.endDate ?? Date(),
            format: .json
        )
        try data.write(to: url)

        let record = ExportRecord(format: .json, targetPath: url.path)
        try exportRepository.save(record)

        return url
    }

    private func fetchFilteredSessions(filter: ExportFilter) throws -> [WorkSession] {
        let start = filter.startDate ?? Date.distantPast
        let end = filter.endDate ?? Date()
        let sessions = try workSessionRepository.fetchByDateRange(start: start, end: end)
        let requestedTagIds = Set(filter.tagIds ?? [])

        return try sessions.filter { session in
            let tags = try workSessionRepository.fetchTags(sessionId: session.id)
            let sessionTagIds = Set(tags.map(\.tagId))
            let isUnclassified = sessionTagIds.isEmpty

            if requestedTagIds.isEmpty {
                return filter.includeUnclassified || !isUnclassified
            }

            if !sessionTagIds.isDisjoint(with: requestedTagIds) {
                return true
            }

            return filter.includeUnclassified && isUnclassified
        }
    }
}
