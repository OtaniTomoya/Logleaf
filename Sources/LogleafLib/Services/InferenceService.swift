import Foundation
import AppKit

public final class InferenceService {
    private let ollamaClient: OllamaClientProtocol
    private let promptBuilder: PromptBuilder
    private let observationRepository: ObservationRepository
    private let tagRepository: TagRepository
    private let fileStorageService: FileStorageService

    public init(ollamaClient: OllamaClientProtocol,
         promptBuilder: PromptBuilder,
         observationRepository: ObservationRepository,
         tagRepository: TagRepository,
         fileStorageService: FileStorageService) {
        self.ollamaClient = ollamaClient
        self.promptBuilder = promptBuilder
        self.observationRepository = observationRepository
        self.tagRepository = tagRepository
        self.fileStorageService = fileStorageService
    }

    public func configure(host: String, model: String) {
        ollamaClient.configure(host: host, model: model)
    }

    public func infer(observationId: String, imageURL: URL,
               frontmostApp: String?, frontmostWindowTitle: String?) async {
        do {
            let allowedTags = try tagRepository.fetchActive()
            guard !allowedTags.isEmpty else {
                AppLogger.warning("No active tags configured, skipping inference")
                return
            }

            let input = InferenceInput(
                imageURL: imageURL,
                frontmostApp: frontmostApp,
                frontmostWindowTitle: frontmostWindowTitle,
                allowedTags: allowedTags
            )

            let prompt = promptBuilder.buildPrompt(input: input)

            // Read image and convert to base64
            let imageData = try Data(contentsOf: imageURL)
            let base64Image = imageData.base64EncodedString()

            let responseText = try await ollamaClient.generate(prompt: prompt, imageBase64: base64Image)

            guard let result = promptBuilder.parseResponse(responseText, allowedTags: allowedTags) else {
                AppLogger.error("Failed to parse inference result for observation \(observationId)")
                return
            }

            // Save inference result to observation
            try observationRepository.updateInferenceResult(observationId: observationId, result: result)

            // Save observation tags
            try observationRepository.deleteTagsForObservation(observationId, source: .ai)
            var tags: [ObservationTag] = []
            for tagName in result.predictedTags {
                if let tag = allowedTags.first(where: { $0.name == tagName }) {
                    tags.append(ObservationTag(
                        observationId: observationId,
                        tagId: tag.id,
                        score: result.confidence,
                        source: .ai
                    ))
                }
            }
            try observationRepository.saveTags(tags)
            deleteScreenshotAfterInference(observationId: observationId, imageURL: imageURL)

            AppLogger.info("Inference complete for \(observationId): \(result.activitySummary)")
        } catch {
            AppLogger.error("Inference failed for \(observationId): \(error)")
        }
    }

    private func deleteScreenshotAfterInference(observationId: String, imageURL: URL) {
        do {
            try fileStorageService.deleteFile(at: imageURL)
            try observationRepository.clearImageReference(observationId: observationId)
        } catch {
            AppLogger.error("Failed to delete screenshot after inference for \(observationId): \(error)")
        }
    }

    public func reInfer(observationId: String) async {
        guard let observation = try? observationRepository.fetch(id: observationId),
              let imagePath = observation.imagePath else {
            AppLogger.error("Cannot re-infer: observation or image not found")
            return
        }

        let imageURL = URL(fileURLWithPath: imagePath)
        await infer(
            observationId: observationId,
            imageURL: imageURL,
            frontmostApp: observation.frontmostApp,
            frontmostWindowTitle: observation.frontmostWindowTitle
        )
    }

    public func testConnection() async -> Bool {
        do {
            return try await ollamaClient.testConnection()
        } catch {
            return false
        }
    }

    public func listModels() async -> [String] {
        do {
            return try await ollamaClient.listModels()
        } catch {
            return []
        }
    }
}
