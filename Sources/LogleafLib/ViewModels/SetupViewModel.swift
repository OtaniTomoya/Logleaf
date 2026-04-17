import SwiftUI

@MainActor
public final class SetupViewModel: ObservableObject {
    @Published public var currentStep: SetupStep = .welcome
    @Published public var hasScreenCapturePermission = false
    @Published public var hasAccessibilityPermission = false
    @Published public var selectedModel: String = ""
    @Published public var availableModels: [String] = []
    @Published public var isModelConnected = false
    @Published public var retentionDays: Int = 30
    @Published public var newTagName: String = ""
    @Published public var tags: [Tag] = []
    @Published public var isLoading = false
    @Published public var errorMessage: String?

    private let permissionService: PermissionService
    private let inferenceService: InferenceService
    private let tagService: TagService
    private let settingsService: SettingsService

    public enum SetupStep: Int, CaseIterable {
        case welcome
        case screenCapturePermission
        case accessibilityPermission
        case modelSelection
        case retentionPolicy
        case tagSetup
        case complete
    }

    public init(permissionService: PermissionService, inferenceService: InferenceService,
         tagService: TagService, settingsService: SettingsService) {
        self.permissionService = permissionService
        self.inferenceService = inferenceService
        self.tagService = tagService
        self.settingsService = settingsService
    }

    public func checkPermissions() async {
        hasScreenCapturePermission = await permissionService.checkScreenCapturePermission()
        hasAccessibilityPermission = permissionService.checkAccessibilityPermission()
    }

    public func requestScreenCapture() {
        permissionService.requestScreenCapturePermission()
    }

    public func requestAccessibility() {
        permissionService.requestAccessibilityPermission()
    }

    public func testModelConnection() async {
        let settings = (try? settingsService.loadSettings()) ?? AppSettings()
        inferenceService.configure(
            host: settings.ollamaHost,
            model: selectedModel.isEmpty ? settings.ollamaModel : selectedModel
        )
        isLoading = true
        isModelConnected = await inferenceService.testConnection()
        if isModelConnected {
            availableModels = await inferenceService.listModels()
            if selectedModel.isEmpty, let first = availableModels.first {
                selectedModel = first
            }
        }
        isLoading = false
    }

    public func addTag() {
        let name = newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        do {
            let tag = try tagService.createTag(name: name)
            tags.append(tag)
            newTagName = ""
        } catch {
            errorMessage = "タグの追加に失敗しました: \(error.localizedDescription)"
        }
    }

    public func removeTag(at offsets: IndexSet) {
        for index in offsets {
            let tag = tags[index]
            try? tagService.deleteTag(id: tag.id)
        }
        tags.remove(atOffsets: offsets)
    }

    public func saveSettings() {
        do {
            var settings = try settingsService.loadSettings()
            settings.ollamaModel = selectedModel
            settings.retentionDays = retentionDays
            try settingsService.saveSettings(settings)
            inferenceService.configure(host: settings.ollamaHost, model: settings.ollamaModel)
            try settingsService.saveBool(true, forKey: "setup_complete")
        } catch {
            errorMessage = "設定の保存に失敗しました"
        }
    }

    public var canProceed: Bool {
        switch currentStep {
        case .welcome: return true
        case .screenCapturePermission: return hasScreenCapturePermission
        case .accessibilityPermission: return true // Optional
        case .modelSelection: return isModelConnected && !selectedModel.isEmpty
        case .retentionPolicy: return true
        case .tagSetup: return !tags.isEmpty
        case .complete: return true
        }
    }

    public func nextStep() {
        guard let next = SetupStep(rawValue: currentStep.rawValue + 1) else { return }
        currentStep = next
    }

    public func previousStep() {
        guard let prev = SetupStep(rawValue: currentStep.rawValue - 1) else { return }
        currentStep = prev
    }
}
