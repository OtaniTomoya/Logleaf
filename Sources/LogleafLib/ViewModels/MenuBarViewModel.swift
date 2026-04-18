import SwiftUI

@MainActor
public final class MenuBarViewModel: ObservableObject {
    @Published public var isCapturing = false
    @Published public var statusText = "待機中"
    @Published public var todayMinutes = 0
    @Published public var latestActivity = ""

    @Published public var nextCaptureDate: Date?

    private let appState: AppState

    public init(appState: AppState) {
        self.appState = appState
    }

    public func refresh() {
        isCapturing = appState.isCapturing
        statusText = appState.captureStatus.rawValue
        todayMinutes = (try? appState.workSessionRepository.totalMinutesForDate(Date())) ?? 0
        nextCaptureDate = appState.schedulerService.nextFireDate
    }

    public func toggleCapture() {
        appState.toggleCapturing()
        refresh()
    }

    public func captureNow() {
        Task {
            await appState.captureNow()
            refresh()
        }
    }
}
