import SwiftUI

@MainActor
public final class SettingsViewModel: ObservableObject {
    @Published public var captureIntervalSeconds: Int = 60
    @Published public var checkpointIntervalMinutes: Int = 5
    @Published public var ollamaHost: String = "http://localhost:11434"
    @Published public var ollamaModel: String = "llava"
    @Published public var retentionDays: Int = 30
    @Published public var autoDeleteEnabled: Bool = true
    @Published public var availableModels: [String] = []
    @Published public var isModelConnected: Bool = false
    @Published public var errorMessage: String?

    private let settingsService: SettingsService
    private let inferenceService: InferenceService

    public init(settingsService: SettingsService, inferenceService: InferenceService) {
        self.settingsService = settingsService
        self.inferenceService = inferenceService
    }

    public func loadSettings() {
        do {
            let settings = try settingsService.loadSettings()
            captureIntervalSeconds = settings.captureIntervalSeconds
            checkpointIntervalMinutes = settings.checkpointIntervalMinutes
            ollamaHost = settings.ollamaHost
            ollamaModel = settings.ollamaModel
            retentionDays = settings.retentionDays
            autoDeleteEnabled = settings.autoDeleteEnabled
        } catch {
            errorMessage = "設定の読み込みに失敗しました"
        }
    }

    public func saveSettings() {
        do {
            var settings = AppSettings()
            settings.captureIntervalSeconds = captureIntervalSeconds
            settings.checkpointIntervalMinutes = checkpointIntervalMinutes
            settings.ollamaHost = ollamaHost
            settings.ollamaModel = ollamaModel
            settings.retentionDays = retentionDays
            settings.autoDeleteEnabled = autoDeleteEnabled
            try settingsService.saveSettings(settings)
            inferenceService.configure(host: ollamaHost, model: ollamaModel)
        } catch {
            errorMessage = "設定の保存に失敗しました"
        }
    }

    public func testConnection() async {
        inferenceService.configure(host: ollamaHost, model: ollamaModel)
        isModelConnected = await inferenceService.testConnection()
        if isModelConnected {
            availableModels = await inferenceService.listModels()
        }
    }
}
