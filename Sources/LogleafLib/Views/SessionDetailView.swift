import SwiftUI

public struct SessionDetailView: View {
    @StateObject var viewModel: SessionDetailViewModel
    @Environment(\.dismiss) private var dismiss

    public init(viewModel: SessionDetailViewModel) {
        self._viewModel = StateObject(wrappedValue: viewModel)
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("セッション詳細")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Button("閉じる") { dismiss() }
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Time range
                    HStack {
                        Label(formatTime(viewModel.session.startAt), systemImage: "clock")
                        Text("〜")
                        Text(formatTime(viewModel.session.endAt))
                        Text("（\(viewModel.session.durationMinutes)分）")
                            .foregroundColor(.secondary)
                    }

                    // Title
                    VStack(alignment: .leading, spacing: 4) {
                        Text("タイトル")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        if viewModel.isEditing {
                            TextField("タイトル", text: $viewModel.editedTitle)
                                .textFieldStyle(.roundedBorder)
                        } else {
                            Text(viewModel.session.displayTitle)
                                .font(.headline)
                        }
                    }

                    // Tags
                    VStack(alignment: .leading, spacing: 4) {
                        Text("タグ")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        FlowLayout(spacing: 6) {
                            ForEach(viewModel.tags) { tag in
                                Text(tag.name)
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.accentColor.opacity(0.15))
                                    .cornerRadius(6)
                            }
                        }
                    }

                    // AI Reason
                    if let obs = viewModel.observations.first, let reason = obs.aiReason {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("推論理由")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(reason)
                                .font(.body)
                                .padding(8)
                                .background(Color(nsColor: .controlBackgroundColor))
                                .cornerRadius(6)
                        }
                    }

                    // Note
                    VStack(alignment: .leading, spacing: 4) {
                        Text("メモ")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        if viewModel.isEditing {
                            TextEditor(text: $viewModel.editedNote)
                                .frame(height: 80)
                                .border(Color.gray.opacity(0.3))
                        } else {
                            Text(viewModel.session.finalNote ?? "なし")
                                .foregroundColor(viewModel.session.finalNote == nil ? .secondary : .primary)
                        }
                    }

                    Divider()

                    // Observations list
                    VStack(alignment: .leading, spacing: 8) {
                        Text("観測一覧（\(viewModel.observations.count)件）")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        ForEach(viewModel.observations.filter { !$0.isUserHidden }, id: \.id) { obs in
                            ObservationRowView(observation: obs) {
                                viewModel.hideObservation(id: obs.id)
                            } onReInfer: {
                                viewModel.reInferObservation(id: obs.id)
                            }
                        }
                    }
                }
                .padding()
            }

            Divider()

            // Bottom toolbar
            HStack {
                if viewModel.isEditing {
                    Button("キャンセル") {
                        viewModel.isEditing = false
                    }
                    Spacer()
                    Button("保存") {
                        viewModel.saveEdits()
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("編集") {
                        viewModel.isEditing = true
                    }
                    Spacer()
                    if viewModel.session.status == .draft {
                        Button("確定") {
                            viewModel.confirmSession()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            .padding()
        }
        .frame(width: 500, height: 600)
        .onAppear { viewModel.loadDetails() }
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

public struct ObservationRowView: View {
    public let observation: Observation
    public let onHide: () -> Void
    public let onReInfer: () -> Void

    public init(observation: Observation, onHide: @escaping () -> Void, onReInfer: @escaping () -> Void) {
        self.observation = observation
        self.onHide = onHide
        self.onReInfer = onReInfer
    }

    public var body: some View {
        HStack(spacing: 8) {
            // Thumbnail
            if let path = observation.imagePath {
                let url = URL(fileURLWithPath: path)
                AsyncImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Color.gray.opacity(0.2)
                }
                .frame(width: 60, height: 40)
                .cornerRadius(4)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(timeString(observation.capturedAt))
                        .font(.caption)
                        .fontWeight(.medium)
                    if let app = observation.frontmostApp {
                        Text(app)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                if let summary = observation.aiSummary {
                    Text(summary)
                        .font(.caption2)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Actions
            Menu {
                Button("再推論", action: onReInfer)
                Button("非表示", action: onHide)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
        }
        .padding(.vertical, 4)
    }

    private func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}

public struct FlowLayout: Layout {
    public var spacing: CGFloat = 8

    public init(spacing: CGFloat = 8) {
        self.spacing = spacing
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = computeLayout(proposal: proposal, subviews: subviews)
        return result.size
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = computeLayout(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                                  proposal: .unspecified)
        }
    }

    private func computeLayout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }

        return (CGSize(width: maxWidth, height: y + rowHeight), positions)
    }
}
