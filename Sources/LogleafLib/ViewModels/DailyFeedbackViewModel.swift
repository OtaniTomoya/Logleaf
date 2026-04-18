import SwiftUI

@MainActor
public final class DailyFeedbackViewModel: ObservableObject {
    @Published public var feedback: DailyFeedback?
    @Published public var isGenerating = false
    @Published public var isEditing = false
    @Published public var editedText = ""
    @Published public var errorMessage: String?

    private let dailyFeedbackService: DailyFeedbackService
    private let date: Date

    public init(dailyFeedbackService: DailyFeedbackService, date: Date) {
        self.dailyFeedbackService = dailyFeedbackService
        self.date = date
    }

    public func loadExisting() {
        do {
            feedback = try dailyFeedbackService.fetchExisting(for: date)
            if let feedback {
                editedText = feedback.displayFeedback
            }
        } catch {
            AppLogger.error("Failed to load feedback: \(error)")
        }
    }

    public func generate() {
        isGenerating = true
        errorMessage = nil
        Task {
            do {
                let result = try await dailyFeedbackService.generateFeedback(for: date)
                feedback = result
                editedText = result.displayFeedback
            } catch {
                errorMessage = error.localizedDescription
                AppLogger.error("Failed to generate feedback: \(error)")
            }
            isGenerating = false
        }
    }

    public func startEditing() {
        editedText = feedback?.displayFeedback ?? ""
        isEditing = true
    }

    public func saveEdits() {
        guard var fb = feedback else { return }
        fb.editedFeedback = editedText.isEmpty ? nil : editedText
        do {
            try dailyFeedbackService.updateFeedback(fb)
            feedback = fb
            isEditing = false
        } catch {
            AppLogger.error("Failed to save feedback edits: \(error)")
        }
    }

    public func cancelEditing() {
        editedText = feedback?.displayFeedback ?? ""
        isEditing = false
    }
}
