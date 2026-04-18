import SwiftUI

public struct DailyFeedbackView: View {
    @StateObject var viewModel: DailyFeedbackViewModel

    public init(viewModel: DailyFeedbackViewModel) {
        self._viewModel = StateObject(wrappedValue: viewModel)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "text.bubble")
                    .foregroundColor(.accentColor)
                Text("今日のフィードバック")
                    .font(.headline)
                Spacer()

                if viewModel.feedback != nil {
                    if viewModel.isEditing {
                        Button("キャンセル") {
                            viewModel.cancelEditing()
                        }
                        .font(.caption)
                        Button("保存") {
                            viewModel.saveEdits()
                        }
                        .font(.caption)
                        .buttonStyle(.borderedProminent)
                    } else {
                        Button {
                            viewModel.startEditing()
                        } label: {
                            Image(systemName: "pencil")
                        }
                        .font(.caption)
                        .buttonStyle(.plain)

                        Button {
                            viewModel.generate()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .font(.caption)
                        .buttonStyle(.plain)
                        .help("再生成")
                    }
                }
            }

            if viewModel.isGenerating {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("フィードバックを生成中...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 8)
            } else if let errorMessage = viewModel.errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else if let feedback = viewModel.feedback {
                if viewModel.isEditing {
                    TextEditor(text: $viewModel.editedText)
                        .font(.body)
                        .frame(minHeight: 120)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .background(Color(nsColor: .textBackgroundColor))
                        .cornerRadius(6)
                } else {
                    Text(feedback.displayFeedback)
                        .font(.body)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                Button {
                    viewModel.generate()
                } label: {
                    Label("フィードバックを生成", systemImage: "sparkles")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
        .onAppear {
            viewModel.loadExisting()
        }
    }
}
