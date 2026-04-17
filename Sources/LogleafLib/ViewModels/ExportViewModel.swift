import SwiftUI
import Foundation

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
    private let exportQueue: OperationQueue

    public init(exportService: ExportService, tagRepository: TagRepository) {
        self.exportService = exportService
        self.tagRepository = tagRepository
        self.exportQueue = OperationQueue()
        self.exportQueue.qualityOfService = .userInitiated
        self.exportQueue.maxConcurrentOperationCount = 1
    }

    public func loadTags() {
        do {
            availableTags = try tagRepository.fetchActive()
        } catch {
            errorMessage = "タグの読み込みに失敗しました"
        }
    }

    public func export() {
        guard !isExporting else { return }
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
        let format = selectedFormat
        let exportService = self.exportService

        exportQueue.addOperation {
            let result: Result<URL, Error> = Result {
                switch format {
                case .csv:
                    return try exportService.exportCSV(filter: filter)
                case .markdown:
                    return try exportService.exportMarkdown(filter: filter)
                case .json:
                    return try exportService.exportJSON(filter: filter)
                }
            }

            Task { @MainActor [weak self] in
                guard let self else { return }
                switch result {
                case .success(let url):
                    exportedURL = url
                case .failure(let error):
                    errorMessage = "エクスポートに失敗しました: \(error.localizedDescription)"
                }
                isExporting = false
            }
        }
    }
}
