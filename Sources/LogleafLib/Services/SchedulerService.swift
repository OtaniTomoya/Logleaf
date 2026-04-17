import Foundation
import AppKit

public final class SchedulerService {
    private let captureService: CaptureService
    private var timer: Timer?
    private var intervalSeconds: TimeInterval = 60
    private var shouldResumeAfterInterruption = false

    public init(captureService: CaptureService) {
        self.captureService = captureService
        observeSystemEvents()
    }

    public func start(intervalSeconds: TimeInterval = 60) {
        self.intervalSeconds = intervalSeconds
        shouldResumeAfterInterruption = false
        stop(clearResumeFlag: false)
        timer = Timer.scheduledTimer(withTimeInterval: intervalSeconds, repeats: true) { [weak self] _ in
            Task { [weak self] in
                await self?.captureService.captureOnce()
            }
        }
        AppLogger.info("Scheduler started with interval \(intervalSeconds)s")
    }

    public func stop() {
        stop(clearResumeFlag: true)
    }

    private func stop(clearResumeFlag: Bool) {
        timer?.invalidate()
        timer = nil
        if clearResumeFlag {
            shouldResumeAfterInterruption = false
        }
        AppLogger.info("Scheduler stopped")
    }

    public var isRunning: Bool {
        timer?.isValid == true
    }

    public var nextFireDate: Date? {
        timer?.fireDate
    }

    var configuredIntervalSeconds: TimeInterval {
        intervalSeconds
    }

    private func observeSystemEvents() {
        // Observe screen lock/sleep
        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(
            self,
            selector: #selector(screenLocked),
            name: NSNotification.Name("com.apple.screenIsLocked"),
            object: nil
        )
        dnc.addObserver(
            self,
            selector: #selector(screenUnlocked),
            name: NSNotification.Name("com.apple.screenIsUnlocked"),
            object: nil
        )

        let wsnc = NSWorkspace.shared.notificationCenter
        wsnc.addObserver(
            self,
            selector: #selector(willSleep),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        wsnc.addObserver(
            self,
            selector: #selector(didWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    @objc private func screenLocked() {
        AppLogger.info("Screen locked - pausing scheduler")
        pauseForSystemInterruption()
    }

    @objc private func screenUnlocked() {
        AppLogger.info("Screen unlocked - resuming scheduler")
        resumeAfterSystemInterruptionIfNeeded()
    }

    @objc private func willSleep() {
        AppLogger.info("System sleeping - pausing scheduler")
        pauseForSystemInterruption()
    }

    @objc private func didWake() {
        AppLogger.info("System woke up - resuming scheduler")
        resumeAfterSystemInterruptionIfNeeded()
    }

    func pauseForSystemInterruption() {
        shouldResumeAfterInterruption = isRunning
        stop(clearResumeFlag: false)
    }

    func resumeAfterSystemInterruptionIfNeeded() {
        guard shouldResumeAfterInterruption else { return }
        shouldResumeAfterInterruption = false
        start(intervalSeconds: intervalSeconds)
    }

    deinit {
        DistributedNotificationCenter.default().removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
}
