import SwiftUI

public struct SetupView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var viewModel: SetupViewModel

    public init(appState: AppState) {
        _viewModel = StateObject(wrappedValue: SetupViewModel(
            permissionService: appState.permissionService,
            inferenceService: appState.inferenceService,
            tagService: appState.tagService,
            settingsService: appState.settingsService
        ))
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Progress indicator
            HStack {
                ForEach(SetupViewModel.SetupStep.allCases, id: \.rawValue) { step in
                    Circle()
                        .fill(step.rawValue <= viewModel.currentStep.rawValue ? Color.accentColor : Color.gray.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }
            .padding()

            Divider()

            // Content
            ScrollView {
                VStack(spacing: 20) {
                    switch viewModel.currentStep {
                    case .welcome:
                        welcomeStep
                    case .screenCapturePermission:
                        screenCaptureStep
                    case .accessibilityPermission:
                        accessibilityStep
                    case .modelSelection:
                        modelStep
                    case .retentionPolicy:
                        retentionStep
                    case .tagSetup:
                        tagStep
                    case .complete:
                        completeStep
                    }
                }
                .padding(30)
            }

            Divider()

            // Navigation buttons
            HStack {
                if viewModel.currentStep != .welcome {
                    Button("戻る") { viewModel.previousStep() }
                }
                Spacer()
                if viewModel.currentStep == .complete {
                    Button("開始する") {
                        if viewModel.saveSettings() {
                            appState.completeSetup()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("次へ") { viewModel.nextStep() }
                        .buttonStyle(.borderedProminent)
                        .disabled(!viewModel.canProceed)
                }
            }
            .padding()
        }
        .frame(width: 500, height: 450)
        .task {
            await viewModel.checkPermissions()
        }
    }

    private var welcomeStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "leaf.fill")
                .font(.system(size: 64))
                .foregroundColor(.green)
            Text("Logleaf へようこそ")
                .font(.title)
            Text("スクリーンショットを定期取得し、ローカルAIで作業内容を自動記録するアプリです。すべてのデータはローカルに保存されます。")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
        }
    }

    private var screenCaptureStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "rectangle.dashed.badge.record")
                .font(.system(size: 48))
            Text("画面収録の許可")
                .font(.title2)
            Text("スクリーンショットを取得するために画面収録の権限が必要です。")
                .foregroundColor(.secondary)

            if viewModel.hasScreenCapturePermission {
                Label("許可済み", systemImage: "checkmark.circle.fill")
                    .foregroundColor(.green)
            } else {
                Button("システム設定を開く") {
                    viewModel.requestScreenCapture()
                }
                .buttonStyle(.bordered)

                Button("権限を再確認") {
                    Task { await viewModel.checkPermissions() }
                }
            }
        }
    }

    private var accessibilityStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "accessibility")
                .font(.system(size: 48))
            Text("アクセシビリティ権限（任意）")
                .font(.title2)
            Text("ウィンドウタイトルの取得に使用します。許可しなくても基本機能は利用可能です。")
                .foregroundColor(.secondary)

            if viewModel.hasAccessibilityPermission {
                Label("許可済み", systemImage: "checkmark.circle.fill")
                    .foregroundColor(.green)
            } else {
                Button("権限を要求") {
                    viewModel.requestAccessibility()
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var modelStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "brain")
                .font(.system(size: 48))
            Text("AIモデルの設定")
                .font(.title2)
            Text("Ollamaが起動していることを確認してください。")
                .foregroundColor(.secondary)

            Button("接続テスト") {
                Task { await viewModel.testModelConnection() }
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.isLoading)

            if viewModel.isModelConnected {
                Label("接続成功", systemImage: "checkmark.circle.fill")
                    .foregroundColor(.green)

                Picker("モデル", selection: $viewModel.selectedModel) {
                    ForEach(viewModel.availableModels, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }
            }
        }
    }

    private var retentionStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 48))
            Text("保存期間の設定")
                .font(.title2)

            Picker("保存期間", selection: $viewModel.retentionDays) {
                Text("7日").tag(7)
                Text("14日").tag(14)
                Text("30日").tag(30)
                Text("60日").tag(60)
                Text("90日").tag(90)
            }
            .pickerStyle(.segmented)

            Text("古いスクリーンショットは自動的に削除されます。")
                .foregroundColor(.secondary)
                .font(.caption)
        }
    }

    private var tagStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "tag.fill")
                .font(.system(size: 48))
            Text("タグの初期設定")
                .font(.title2)
            Text("作業分類に使うタグを登録してください。（1つ以上必須）")
                .foregroundColor(.secondary)

            HStack {
                TextField("タグ名", text: $viewModel.newTagName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { viewModel.addTag() }
                Button("追加") { viewModel.addTag() }
                    .disabled(viewModel.newTagName.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            List {
                ForEach(viewModel.tags) { tag in
                    Text(tag.name)
                }
                .onDelete(perform: viewModel.removeTag)
            }
            .frame(height: 120)
        }
    }

    private var completeStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(.green)
            Text("セットアップ完了")
                .font(.title)
            Text("準備が整いました。「開始する」をクリックして記録を始めましょう。")
                .foregroundColor(.secondary)
        }
    }
}
