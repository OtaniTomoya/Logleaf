import Foundation
import Darwin

public final class InferenceService {
    private let ollamaClient: OllamaClientProtocol
    private let promptBuilder: PromptBuilder
    private let observationRepository: ObservationRepository
    private let tagRepository: TagRepository

    private var configuredHost: String = "http://localhost:11434"
    private var configuredModel: String = "gemma4:e4b"
    private let inferenceBatchSize: Int = 10

    public init(ollamaClient: OllamaClientProtocol,
         promptBuilder: PromptBuilder,
         observationRepository: ObservationRepository,
         tagRepository: TagRepository) {
        self.ollamaClient = ollamaClient
        self.promptBuilder = promptBuilder
        self.observationRepository = observationRepository
        self.tagRepository = tagRepository
    }

    public func configure(host: String, model: String) {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        configuredHost = trimmedHost.isEmpty ? "http://localhost:11434" : trimmedHost
        configuredModel = model
        ollamaClient.configure(host: configuredHost, model: configuredModel)
    }

    public func infer(observationId: String, imageURL: URL,
               frontmostApp: String?, frontmostWindowTitle: String?) async {
        await withManagedOllamaRuntime {
            do {
                let allowedTags = try tagRepository.fetchActive()
                if allowedTags.isEmpty {
                    AppLogger.warning("No active tags configured, running inference without tag assignment")
                }

                let target = BatchTarget(
                    observationId: observationId,
                    imageURL: imageURL,
                    frontmostApp: frontmostApp,
                    frontmostWindowTitle: frontmostWindowTitle
                )
                await inferBatch([target], allowedTags: allowedTags)
            } catch {
                AppLogger.error("Inference failed for \(observationId): \(error)")
            }
        }
    }

    public func inferPendingObservations(
        _ observations: [Observation],
        progress: ((Int, Int) -> Void)? = nil
    ) async {
        guard !observations.isEmpty else {
            progress?(0, 0)
            return
        }

        await withManagedOllamaRuntime {
            do {
                let allowedTags = try tagRepository.fetchActive()
                if allowedTags.isEmpty {
                    AppLogger.warning("No active tags configured, running inference without tag assignment")
                }

                var processed = 0
                let total = observations.count
                for observationChunk in makeObservationChunks(of: observations, size: inferenceBatchSize) {
                    let targets = observationChunk.compactMap { observation -> BatchTarget? in
                        guard let imagePath = observation.imagePath else { return nil }
                        return BatchTarget(
                            observationId: observation.id,
                            imageURL: URL(fileURLWithPath: imagePath),
                            frontmostApp: observation.frontmostApp,
                            frontmostWindowTitle: observation.frontmostWindowTitle
                        )
                    }
                    await inferBatch(targets, allowedTags: allowedTags)
                    for _ in observationChunk {
                        processed += 1
                        progress?(processed, total)
                    }
                }
            } catch {
                AppLogger.error("Inference failed for pending observations: \(error)")
            }
        }
    }

    public func reInfer(observationId: String) async {
        guard let observation = try? observationRepository.fetch(id: observationId),
              let imagePath = observation.imagePath else {
            AppLogger.error("Cannot re-infer: observation or image not found")
            return
        }

        await infer(
            observationId: observationId,
            imageURL: URL(fileURLWithPath: imagePath),
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

    private struct BatchTarget {
        let observationId: String
        let imageURL: URL
        let frontmostApp: String?
        let frontmostWindowTitle: String?
    }

    private func inferBatch(_ targets: [BatchTarget], allowedTags: [Tag]) async {
        guard !targets.isEmpty else { return }

        var validTargets: [BatchTarget] = []
        var imageBase64List: [String] = []
        var promptItems: [PromptBuilder.BatchInferenceItem] = []

        for target in targets {
            do {
                let imageData = try Data(contentsOf: target.imageURL)
                imageBase64List.append(imageData.base64EncodedString())
                validTargets.append(target)
                promptItems.append(
                    PromptBuilder.BatchInferenceItem(
                        frontmostApp: target.frontmostApp,
                        frontmostWindowTitle: target.frontmostWindowTitle
                    )
                )
            } catch {
                AppLogger.error("Failed to read screenshot for \(target.observationId): \(error)")
                do {
                    try observationRepository.clearImageReference(observationId: target.observationId)
                } catch {
                    AppLogger.error("Failed to clear broken image reference for \(target.observationId): \(error)")
                }
            }
        }

        guard !validTargets.isEmpty else { return }

        do {
            let prompt = promptBuilder.buildBatchPrompt(items: promptItems, allowedTags: allowedTags)
            let responseText = try await ollamaClient.generate(prompt: prompt, imageBase64List: imageBase64List)
            guard let results = promptBuilder.parseBatchResponse(
                responseText,
                expectedCount: validTargets.count,
                allowedTags: allowedTags
            ) else {
                AppLogger.error("Failed to parse batch inference result")
                return
            }

            for (index, target) in validTargets.enumerated() {
                guard index < results.count, let result = results[index] else {
                    AppLogger.error("Missing inference result for observation \(target.observationId)")
                    continue
                }
                try saveInferenceResult(
                    observationId: target.observationId,
                    result: result,
                    allowedTags: allowedTags
                )
            }
        } catch {
            let ids = validTargets.map(\.observationId).joined(separator: ",")
            AppLogger.error("Batch inference failed for observations [\(ids)]: \(error)")
        }
    }

    private func saveInferenceResult(
        observationId: String,
        result: InferenceResult,
        allowedTags: [Tag]
    ) throws {
        try observationRepository.updateInferenceResult(observationId: observationId, result: result)
        try observationRepository.deleteTagsForObservation(observationId, source: .ai)

        var tags: [ObservationTag] = []
        for tagName in result.predictedTags {
            if let tag = allowedTags.first(where: { $0.name == tagName }) {
                tags.append(ObservationTag(
                    observationId: observationId,
                    tagId: tag.id,
                    score: 1.0,
                    source: .ai
                ))
            }
        }
        try observationRepository.saveTags(tags)
        AppLogger.info("Inference complete for \(observationId): \(result.activitySummary)")
    }

    private func makeObservationChunks(of observations: [Observation], size: Int) -> [[Observation]] {
        guard size > 0 else { return [observations] }
        var chunks: [[Observation]] = []
        chunks.reserveCapacity((observations.count + size - 1) / size)
        var index = 0
        while index < observations.count {
            let end = min(index + size, observations.count)
            chunks.append(Array(observations[index..<end]))
            index = end
        }
        return chunks
    }

    private func withManagedOllamaRuntime(_ operation: () async -> Void) async {
        guard shouldManageLocalOllamaProcess() else {
            await ensureConfiguredModelAvailable()
            await operation()
            return
        }

        if await testConnection() {
            await ensureConfiguredModelAvailable()
            await operation()
            return
        }

        guard let process = startOllamaServeProcess() else {
            await ensureConfiguredModelAvailable()
            await operation()
            return
        }

        defer {
            stopOllamaServeProcess(process)
        }

        let isReady = await waitForOllamaReady(timeoutSeconds: 20)
        guard isReady else {
            AppLogger.error("Ollama process started but connection was not established in time")
            await ensureConfiguredModelAvailable()
            await operation()
            return
        }

        await ensureConfiguredModelAvailable()
        await operation()
    }

    private func ensureConfiguredModelAvailable() async {
        let availableModels: [String]
        do {
            availableModels = try await ollamaClient.listModels()
        } catch {
            AppLogger.warning("Failed to list Ollama models: \(error)")
            return
        }

        guard !availableModels.isEmpty else { return }
        if availableModels.contains(configuredModel) { return }

        let lowered = availableModels.map { $0.lowercased() }
        if let llavaIndex = lowered.firstIndex(where: { $0.contains("llava") }) {
            configuredModel = availableModels[llavaIndex]
        } else {
            configuredModel = availableModels[0]
        }

        ollamaClient.configure(host: configuredHost, model: configuredModel)
        AppLogger.warning("Configured model was unavailable. Fallback model selected: \(configuredModel)")
    }

    private func shouldManageLocalOllamaProcess() -> Bool {
        let normalizedHost: String
        if configuredHost.hasPrefix("http://") || configuredHost.hasPrefix("https://") {
            normalizedHost = configuredHost
        } else {
            normalizedHost = "http://\(configuredHost)"
        }

        guard let components = URLComponents(string: normalizedHost),
              let host = components.host?.lowercased() else {
            return false
        }

        return host == "localhost" || host == "127.0.0.1" || host == "::1"
    }

    private func startOllamaServeProcess() -> Process? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["ollama", "serve"]
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        do {
            try process.run()
            AppLogger.info("Started local Ollama process for on-demand inference")
            return process
        } catch {
            AppLogger.error("Failed to start local Ollama process: \(error)")
            return nil
        }
    }

    private func stopOllamaServeProcess(_ process: Process) {
        guard process.isRunning else { return }
        process.terminate()
        let deadline = Date().addingTimeInterval(3)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }
        AppLogger.info("Stopped local Ollama process after on-demand inference")
    }

    private func waitForOllamaReady(timeoutSeconds: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if await testConnection() {
                return true
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        return false
    }
}
