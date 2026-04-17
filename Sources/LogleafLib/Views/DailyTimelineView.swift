import SwiftUI

public struct DailyTimelineView: View {
    @StateObject var viewModel: DailyTimelineViewModel
    let appState: AppState
    @State private var selectedSession: WorkSession?

    public init(viewModel: DailyTimelineViewModel, appState: AppState) {
        self._viewModel = StateObject(wrappedValue: viewModel)
        self.appState = appState
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Date navigation
            HStack {
                Button(action: viewModel.previousDay) {
                    Image(systemName: "chevron.left")
                }
                Spacer()
                Text(dateString)
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Button("今日", action: viewModel.goToToday)
                    .disabled(Calendar.current.isDateInToday(viewModel.selectedDate))
                Button(action: viewModel.nextDay) {
                    Image(systemName: "chevron.right")
                }
                .disabled(Calendar.current.isDateInToday(viewModel.selectedDate))
            }
            .padding()

            Divider()

            if viewModel.isLoading {
                ProgressView()
                    .frame(maxHeight: .infinity)
            } else if viewModel.sessions.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "tray")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("この日の記録はありません")
                        .foregroundColor(.secondary)
                }
                .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(viewModel.sessions) { session in
                            SessionRowView(
                                session: session,
                                tags: viewModel.sessionTags[session.id] ?? []
                            )
                            .onTapGesture {
                                selectedSession = session
                            }
                        }
                    }
                    .padding()
                }
            }

            Divider()

            // Bottom toolbar
            HStack {
                Text("\(viewModel.sessions.count)件のセッション")
                    .foregroundColor(.secondary)
                    .font(.caption)
                Spacer()
                Button("再集約") {
                    viewModel.rebuildSessions()
                }
                .font(.caption)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .sheet(item: $selectedSession) { session in
            SessionDetailView(
                viewModel: SessionDetailViewModel(
                    session: session,
                    workSessionRepository: appState.workSessionRepository,
                    observationRepository: appState.observationRepository,
                    tagRepository: appState.tagRepository,
                    inferenceService: appState.inferenceService
                )
            )
        }
        .onAppear {
            viewModel.loadSessions()
        }
    }

    private var dateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy年M月d日（E）"
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter.string(from: viewModel.selectedDate)
    }
}

public struct SessionRowView: View {
    public let session: WorkSession
    public let tags: [Tag]

    public init(session: WorkSession, tags: [Tag]) {
        self.session = session
        self.tags = tags
    }

    public var body: some View {
        HStack(spacing: 12) {
            // Time
            VStack(alignment: .leading) {
                Text(timeString(session.startAt))
                    .font(.caption)
                    .fontWeight(.semibold)
                Text(timeString(session.endAt))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(width: 50)

            // Time bar
            RoundedRectangle(cornerRadius: 2)
                .fill(barColor)
                .frame(width: 4)

            // Content
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(session.displayTitle)
                        .font(.body)
                        .fontWeight(.medium)
                    Spacer()
                    if session.status == .edited || session.status == .confirmed {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                    }
                }

                HStack(spacing: 4) {
                    ForEach(tags) { tag in
                        Text(tag.name)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(tagColor(tag).opacity(0.2))
                            .foregroundColor(tagColor(tag))
                            .cornerRadius(4)
                    }
                    Spacer()
                    if let confidence = session.aiConfidence {
                        Text(String(format: "%.0f%%", confidence * 100))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Text("\(session.durationMinutes)分")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }

    private var barColor: Color {
        if let tag = tags.first, let hex = tag.colorHex {
            return Color(hex: hex)
        }
        return .accentColor
    }

    private func tagColor(_ tag: Tag) -> Color {
        if let hex = tag.colorHex {
            return Color(hex: hex)
        }
        return .accentColor
    }

    private func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

public extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: UInt64
        switch hex.count {
        case 6:
            (r, g, b) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (r, g, b) = (74, 144, 217)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: 1
        )
    }
}
