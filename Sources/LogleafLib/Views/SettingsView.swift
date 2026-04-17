import SwiftUI

public struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var viewModel: SettingsViewModel

    public init(viewModel: SettingsViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        Form {
            Section("キャプチャ設定") {
                Picker("キャプチャ間隔", selection: $viewModel.captureIntervalSeconds) {
                    Text("30秒").tag(30)
                    Text("1分").tag(60)
                    Text("2分").tag(120)
                    Text("5分").tag(300)
                }

                Picker("チェックポイント間隔", selection: $viewModel.checkpointIntervalMinutes) {
                    Text("5分").tag(5)
                    Text("10分").tag(10)
                    Text("15分").tag(15)
                }
            }

            Section("モデル設定") {
                TextField("Ollamaホスト", text: $viewModel.ollamaHost)

                HStack {
                    if viewModel.availableModels.isEmpty {
                        TextField("モデル名", text: $viewModel.ollamaModel)
                    } else {
                        Picker("モデル", selection: $viewModel.ollamaModel) {
                            ForEach(viewModel.availableModels, id: \.self) { model in
                                Text(model).tag(model)
                            }
                        }
                    }
                    Button("接続テスト") {
                        Task { await viewModel.testConnection() }
                    }
                }

                if viewModel.isModelConnected {
                    Label("接続済み", systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)
                }
            }

            Section("保存設定") {
                Picker("保存期間", selection: $viewModel.retentionDays) {
                    Text("7日").tag(7)
                    Text("14日").tag(14)
                    Text("30日").tag(30)
                    Text("60日").tag(60)
                    Text("90日").tag(90)
                }

                Toggle("自動削除", isOn: $viewModel.autoDeleteEnabled)
            }

            Section {
                HStack {
                    Spacer()
                    Button("保存") {
                        viewModel.saveSettings()
                        appState.applyRuntimeSettings()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 450, minHeight: 400)
        .onAppear { viewModel.loadSettings() }
    }
}
