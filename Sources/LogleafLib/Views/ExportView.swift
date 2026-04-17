import SwiftUI

public struct ExportView: View {
    @StateObject var viewModel: ExportViewModel

    public init(viewModel: ExportViewModel) {
        self._viewModel = StateObject(wrappedValue: viewModel)
    }

    public var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("期間") {
                    DatePicker("開始日", selection: $viewModel.startDate, displayedComponents: .date)
                    DatePicker("終了日", selection: $viewModel.endDate, displayedComponents: .date)
                }

                Section("出力形式") {
                    Picker("形式", selection: $viewModel.selectedFormat) {
                        Text("CSV").tag(ExportRecord.ExportFormat.csv)
                        Text("Markdown").tag(ExportRecord.ExportFormat.markdown)
                        Text("JSON").tag(ExportRecord.ExportFormat.json)
                    }
                    .pickerStyle(.segmented)
                }

                Section("フィルタ") {
                    Toggle("未分類を含む", isOn: $viewModel.includeUnclassified)

                    if !viewModel.availableTags.isEmpty {
                        VStack(alignment: .leading) {
                            Text("タグフィルタ（空の場合は全て）")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            FlowLayout(spacing: 6) {
                                ForEach(viewModel.availableTags) { tag in
                                    Button(action: {
                                        if viewModel.selectedTagIds.contains(tag.id) {
                                            viewModel.selectedTagIds.remove(tag.id)
                                        } else {
                                            viewModel.selectedTagIds.insert(tag.id)
                                        }
                                    }) {
                                        Text(tag.name)
                                            .font(.caption)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(
                                                viewModel.selectedTagIds.contains(tag.id)
                                                    ? Color.accentColor.opacity(0.3)
                                                    : Color.gray.opacity(0.1)
                                            )
                                            .cornerRadius(6)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }

                Section {
                    HStack {
                        Spacer()
                        Button("エクスポート") {
                            viewModel.export()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(viewModel.isExporting)
                    }
                }
            }
            .formStyle(.grouped)

            if let url = viewModel.exportedURL {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("エクスポート完了: \(url.lastPathComponent)")
                    Button("Finderで表示") {
                        NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
                    }
                }
                .padding()
            }

            if let error = viewModel.errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .padding()
            }
        }
        .onAppear { viewModel.loadTags() }
    }
}
