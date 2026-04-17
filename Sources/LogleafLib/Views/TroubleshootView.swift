import SwiftUI

public struct TroubleshootView: View {
    @EnvironmentObject var appState: AppState
    @State private var screenCaptureOK = false
    @State private var accessibilityOK = false
    @State private var ollamaOK = false
    @State private var storageInfo = ""
    @State private var isChecking = false

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("トラブルシュート")
                    .font(.title2)
                    .fontWeight(.semibold)

                // Permission checks
                GroupBox("権限") {
                    VStack(alignment: .leading, spacing: 12) {
                        StatusRow(
                            title: "画面収録",
                            isOK: screenCaptureOK,
                            action: "システム設定を開く",
                            onAction: { appState.permissionService.requestScreenCapturePermission() }
                        )
                        StatusRow(
                            title: "アクセシビリティ",
                            isOK: accessibilityOK,
                            action: "権限を要求",
                            onAction: { appState.permissionService.requestAccessibilityPermission() }
                        )
                    }
                    .padding(.vertical, 4)
                }

                // Ollama check
                GroupBox("AIモデル") {
                    StatusRow(
                        title: "Ollama接続",
                        isOK: ollamaOK,
                        action: "再確認",
                        onAction: {
                            Task {
                                ollamaOK = await appState.inferenceService.testConnection()
                            }
                        }
                    )
                    .padding(.vertical, 4)
                }

                // Storage
                GroupBox("ストレージ") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(storageInfo)
                            .font(.body)

                        HStack {
                            Button("保存先を開く") {
                                NSWorkspace.shared.open(appState.fileStorageService.appSupportURL)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

                // Actions
                GroupBox("メンテナンス") {
                    VStack(alignment: .leading, spacing: 8) {
                        Button("全権限を再確認") {
                            Task { await checkAll() }
                        }
                        .disabled(isChecking)
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding()
        }
        .task { await checkAll() }
    }

    private func checkAll() async {
        isChecking = true
        screenCaptureOK = await appState.permissionService.checkScreenCapturePermission()
        accessibilityOK = appState.permissionService.checkAccessibilityPermission()
        ollamaOK = await appState.inferenceService.testConnection()
        updateStorageInfo()
        isChecking = false
    }

    private func updateStorageInfo() {
        let fm = FileManager.default
        let appSupport = appState.fileStorageService.appSupportURL
        if let attrs = try? fm.attributesOfFileSystem(forPath: appSupport.path) {
            let freeSpace = (attrs[.systemFreeSize] as? Int64) ?? 0
            let freeGB = Double(freeSpace) / 1_073_741_824
            storageInfo = String(format: "空き容量: %.1f GB", freeGB)
        } else {
            storageInfo = "ストレージ情報を取得できませんでした"
        }
    }
}

public struct StatusRow: View {
    public let title: String
    public let isOK: Bool
    public let action: String
    public let onAction: () -> Void

    public init(title: String, isOK: Bool, action: String, onAction: @escaping () -> Void) {
        self.title = title
        self.isOK = isOK
        self.action = action
        self.onAction = onAction
    }

    public var body: some View {
        HStack {
            Image(systemName: isOK ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(isOK ? .green : .red)
            Text(title)
            Spacer()
            if !isOK {
                Button(action, action: onAction)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
    }
}
