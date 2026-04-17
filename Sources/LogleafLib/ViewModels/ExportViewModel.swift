import SwiftUI

@MainActor
public final class ExportViewModel: ObservableObject {
    @Published public var startDate: Date = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
    @Published public var endDate: Date = Date()
    @Published public var selectedFormat: ExportRecord.ExportFormat = .csv
    @Published public var selectedTagIds: Set<String> = []
    @Published public var includeUnclassified: Bool = true
    @Published public var availableTags: [Tag] = []
    @Published public var isExporting: Bool = false
    @Published public var exportedURL: URL?
    @Published public var errorMessage: String?

    private let exportService: ExportService
    private let tagRepository: TagRepository

    public init(exportService: ExportService, tagRepository: TagRepository) {
        self.exportService = exportService
        self.tagRepository = tagRepository
    }

    public func loadTags() {
        do {
            availableTags = try tagRepository.fetchActive()
        } catch {
            errorMessage = "タグの読み込みに失敗しました"
        }
    }

    public func export() {
        isExporting = true
        errorMessage = nil
        exportedURL = nil
        let calendar = Calendar.current
        let normalizedStartDate = calendar.startOfDay(for: startDate)
        let normalizedEndDate = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: endDate)) ?? endDate

        let filter = ExportFilter(
            startDate: normalizedStartDate,
            endDate: normalizedEndDate,
            tagIds: selectedTagIds.isEmpty ? nil : Array(selectedTagIds),
            includeUnclassified: includeUnclassified
        )

        do {
            switch selectedFormat {
            case .csv:
                exportedURL = try exportService.exportCSV(filter: filter)
            case .markdown:
                exportedURL = try exportService.exportMarkdown(filter: filter)
            case .json:
                exportedURL = try exportService.exportJSON(filter: filter)
            }
        } catch {
            errorMessage = "エクスポートに失敗しました: \(error.localizedDescription)"
        }
        isExporting = false
    }
}
