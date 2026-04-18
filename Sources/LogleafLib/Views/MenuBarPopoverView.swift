import SwiftUI
import AppKit

public struct MenuBarPopoverView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.openWindow) private var openWindow
    private let refreshTimer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

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

                HStack {
                    Image(systemName: "photo.on.rectangle.angled")
                    Text("未推論: \(appState.pendingInferenceCount)枚")
                }
                .foregroundColor(appState.pendingInferenceCount > 0 ? .orange : .secondary)

                HStack {
                    Image(systemName: "checkmark.seal")
                    Text("推論完了: \(appState.completedInferenceCount)枚")
                }
                .foregroundColor(.secondary)

                if appState.captureStatus == .inferring {
                    HStack {
                        Image(systemName: "brain")
                        Text("推論中: \(appState.currentInferenceProcessedCount)/\(appState.currentInferenceTotalCount)")
                    }
                    .foregroundColor(.blue)
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

            Button(action: {
                Task { await appState.runPendingInference() }
            }) {
                Label("溜まった画像を推論", systemImage: "brain")
            }
            .disabled(!appState.isSetupComplete || appState.pendingInferenceCount == 0 || appState.captureStatus == .inferring)

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
        .onReceive(refreshTimer) { _ in
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
        appState.nextCaptureDate = appState.schedulerService.nextFireDate
        appState.refreshInferenceQueueStats()
    }

    private func openMainWindow() {
        if resolveMainWindow() == nil {
            openWindow(id: "main")
        }
        activateAndFocusMainWindow(after: 0)
        activateAndFocusMainWindow(after: 0.15)
    }

    private func openSettings() {
        appState.shouldOpenSettings = true
        openMainWindow()
    }

    private func activateAndFocusMainWindow(after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            NSApp.activate(ignoringOtherApps: true)
            guard let mainWindow = resolveMainWindow() else { return }
            mainWindow.orderFrontRegardless()
            mainWindow.makeMain()
            mainWindow.makeKeyAndOrderFront(nil)
            dismissMenuBarPopoverWindows(except: mainWindow)
            if let firstResponder = mainWindow.initialFirstResponder {
                mainWindow.makeFirstResponder(firstResponder)
            } else if let contentView = mainWindow.contentView {
                mainWindow.makeFirstResponder(contentView)
            }
        }
    }

    private func resolveMainWindow() -> NSWindow? {
        let candidates = NSApp.windows.filter { window in
            guard window.canBecomeKey else { return false }
            let matchesID = window.identifier?.rawValue == "main"
            let matchesTitle = window.title == "Logleaf"
            let looksLikeMainSize = window.frame.width >= 500
            return (matchesID || matchesTitle) && looksLikeMainSize
        }
        if let visible = candidates.first(where: \.isVisible) {
            return visible
        }
        return candidates.max(by: { lhs, rhs in
            lhs.frame.width * lhs.frame.height < rhs.frame.width * rhs.frame.height
        })
    }

    private func dismissMenuBarPopoverWindows(except mainWindow: NSWindow) {
        for window in NSApp.windows where window != mainWindow {
            let className = String(describing: type(of: window))
            if className.contains("NSStatusBarWindow") {
                window.orderOut(nil)
            }
        }
    }
}
