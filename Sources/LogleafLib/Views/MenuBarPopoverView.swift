import SwiftUI
import AppKit

public struct MenuBarPopoverView: View {
    @EnvironmentObject var appState: AppState

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Status header
            HStack {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(appState.captureStatus.rawValue)
                    .font(.headline)
                Spacer()
            }

            Divider()

            // Today's stats
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "clock")
                    Text("本日の記録: \(formatMinutes(appState.todayRecordedMinutes))")
                }

                if !appState.latestActivity.isEmpty {
                    HStack {
                        Image(systemName: "eye")
                        Text("直近: \(appState.latestActivity)")
                            .lineLimit(1)
                    }
                }

                if appState.unconfirmedCount > 0 {
                    HStack {
                        Image(systemName: "exclamationmark.circle")
                        Text("未確認: \(appState.unconfirmedCount)件")
                    }
                    .foregroundColor(.orange)
                }

                if let next = appState.nextCaptureDate {
                    HStack {
                        Image(systemName: "timer")
                        Text("次回: \(next, style: .relative)")
                    }
                    .foregroundColor(.secondary)
                    .font(.caption)
                }
            }
            .font(.body)

            Divider()

            // Action buttons
            Button(action: { appState.toggleCapturing() }) {
                Label(
                    appState.isCapturing ? "一時停止" : "開始",
                    systemImage: appState.isCapturing ? "pause.circle" : "play.circle"
                )
            }

            Button(action: {
                Task { await appState.captureNow() }
            }) {
                Label("今すぐ記録", systemImage: "camera")
            }
            .disabled(!appState.isSetupComplete)

            Divider()

            Button(action: openMainWindow) {
                Label("今日のログを開く", systemImage: "list.bullet.rectangle")
            }

            Button(action: openSettings) {
                Label("設定", systemImage: "gear")
            }

            Divider()

            Button(action: { NSApplication.shared.terminate(nil) }) {
                Label("終了", systemImage: "power")
            }
        }
        .padding()
        .frame(width: 280)
        .onAppear {
            refreshStats()
        }
    }

    private var statusColor: Color {
        switch appState.captureStatus {
        case .capturing: return .green
        case .paused: return .orange
        case .idle: return .gray
        case .permissionDenied: return .red
        case .inferring: return .blue
        }
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
        appState.unconfirmedCount = (try? appState.workSessionRepository.countUnconfirmed()) ?? 0
        appState.nextCaptureDate = appState.schedulerService.nextFireDate
    }

    private func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "main" }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            NSApp.sendAction(Selector(("showMainWindow:")), to: nil, from: nil)
        }
    }

    private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}
