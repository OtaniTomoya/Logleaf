import SwiftUI
import AppKit

public struct DailyTimelineView: View {
    @StateObject var viewModel: DailyTimelineViewModel
    @ObservedObject var appState: AppState
    @State private var selectedSession: WorkSession?
    private let refreshTimer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    public init(viewModel: DailyTimelineViewModel, appState: AppState) {
        self._viewModel = StateObject(wrappedValue: viewModel)
        self.appState = appState
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Date navigation
            dateNavigationBar

            Divider()

            // Status + action bar
            statusActionBar
                .padding(.horizontal)
                .padding(.vertical, 8)

            // Inference progress bar (only during inference)
            if appState.captureStatus == .inferring {
                inferenceProgressBar
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            Divider()

            // Main content
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
                    VStack(spacing: 8) {
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

                        DailyFeedbackView(
                            viewModel: DailyFeedbackViewModel(
                                dailyFeedbackService: appState.dailyFeedbackService,
                                date: viewModel.selectedDate
                            )
                        )
                        .id(Calendar.current.startOfDay(for: viewModel.selectedDate))
                    }
                    .padding()
                }
            }

            Divider()

            // Bottom toolbar
            bottomToolbar
                .padding(.horizontal)
                .padding(.vertical, 8)
        }
        .animation(.easeInOut(duration: 0.25), value: appState.captureStatus == .inferring)
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
            refreshStats()
        }
        .onReceive(refreshTimer) { _ in
            refreshStats()
        }
        .onChange(of: appState.inferenceJustCompleted) {
            if appState.inferenceJustCompleted {
                appState.inferenceJustCompleted = false
                viewModel.loadSessions()
            }
        }
    }

    // MARK: - Date Navigation

    private var dateNavigationBar: some View {
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
    }

    // MARK: - Status + Action Bar

    private var statusActionBar: some View {
        HStack(spacing: 12) {
            // Status indicator
            HStack(spacing: 6) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(appState.captureStatus.rawValue)
                    .font(.callout)
                    .fontWeight(.medium)
            }

            Spacer()

            // Action buttons
            HStack(spacing: 4) {
                Button(action: { appState.toggleCapturing() }) {
                    Label(
                        appState.isCapturing ? "一時停止" : "開始",
                        systemImage: appState.isCapturing ? "pause.circle.fill" : "play.circle.fill"
                    )
                    .font(.callout)
                }
                .buttonStyle(.borderless)

                Button(action: { Task { await appState.captureNow() } }) {
                    Label("記録", systemImage: "camera.fill")
                        .font(.callout)
                }
                .buttonStyle(.borderless)
                .disabled(!appState.isSetupComplete)

                Button(action: { Task { await appState.runPendingInference() } }) {
                    HStack(spacing: 4) {
                        Label("推論", systemImage: "brain")
                            .font(.callout)
                        if appState.pendingInferenceCount > 0 && appState.captureStatus != .inferring {
                            Text("\(appState.pendingInferenceCount)")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(.orange))
                        }
                    }
                }
                .buttonStyle(.borderless)
                .disabled(!appState.isSetupComplete || appState.pendingInferenceCount == 0 || appState.captureStatus == .inferring)
            }
        }
    }

    // MARK: - Inference Progress

    private var inferenceProgressBar: some View {
        VStack(spacing: 4) {
            ProgressView(
                value: Double(appState.currentInferenceProcessedCount),
                total: max(Double(appState.currentInferenceTotalCount), 1)
            )
            .tint(.blue)

            HStack {
                Text("推論中…")
                    .font(.caption)
                    .foregroundColor(.blue)
                Spacer()
                Text("\(appState.currentInferenceProcessedCount) / \(appState.currentInferenceTotalCount)枚完了")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(10)
        .background(Color.blue.opacity(0.06))
        .cornerRadius(8)
    }

    // MARK: - Bottom Toolbar

    private var bottomToolbar: some View {
        HStack {
            Text("\(viewModel.sessions.count)件のセッション")
                .foregroundColor(.secondary)
                .font(.caption)

            if appState.todayRecordedMinutes > 0 && Calendar.current.isDateInToday(viewModel.selectedDate) {
                Text("・\(formatMinutes(appState.todayRecordedMinutes))")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }

            Spacer()

            Button {
                viewModel.rebuildSessions()
            } label: {
                Label("更新", systemImage: "arrow.clockwise")
                    .font(.caption)
            }
        }
    }

    // MARK: - Helpers

    private var statusColor: Color {
        switch appState.captureStatus {
        case .capturing: return .green
        case .paused: return .orange
        case .idle: return .gray
        case .permissionDenied: return .red
        case .inferring: return .blue
        }
    }

    private var dateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy年M月d日（E）"
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter.string(from: viewModel.selectedDate)
    }

    private func formatMinutes(_ minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60
        if hours > 0 {
            return "\(hours)時間\(mins)分"
        }
        return "\(mins)分"
    }

    private func refreshStats() {
        appState.todayRecordedMinutes = (try? appState.workSessionRepository.totalMinutesForDate(Date())) ?? 0
        appState.nextCaptureDate = appState.schedulerService.nextFireDate
        appState.refreshInferenceQueueStats()
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

    /// Returns white or black depending on which has better contrast against this color.
    /// Uses W3C relative luminance formula.
    var contrastingTextColor: Color {
        let nsColor = NSColor(self)
        guard let rgb = nsColor.usingColorSpace(.sRGB) else { return .white }
        let r = rgb.redComponent
        let g = rgb.greenComponent
        let b = rgb.blueComponent
        // Relative luminance (ITU-R BT.709)
        let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
        return luminance > 0.45 ? .black : .white
    }
}
