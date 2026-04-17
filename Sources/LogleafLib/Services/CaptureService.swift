import Foundation
import ScreenCaptureKit
import AppKit
import CoreGraphics

public final class CaptureService {
    private let captureJobRepository: CaptureJobRepository
    private let observationRepository: ObservationRepository
    private let exclusionService: ExclusionService
    private let fileStorageService: FileStorageService
    private let inferenceService: InferenceService

    public init(captureJobRepository: CaptureJobRepository,
         observationRepository: ObservationRepository,
         exclusionService: ExclusionService,
         fileStorageService: FileStorageService,
         inferenceService: InferenceService) {
        self.captureJobRepository = captureJobRepository
        self.observationRepository = observationRepository
        self.exclusionService = exclusionService
        self.fileStorageService = fileStorageService
        self.inferenceService = inferenceService
    }

    public func captureOnce() async {
        let jobId = UUID().uuidString
        let job = CaptureJob(id: jobId, scheduledAt: Date(), status: .running)
        do {
            try captureJobRepository.save(job)
        } catch {
            AppLogger.error("Failed to save capture job: \(error)")
            return
        }

        // Get frontmost app context
        let context = getFrontmostContext()

        // Check exclusion
        if exclusionService.shouldExclude(context: context) {
            do {
                try captureJobRepository.update(id: jobId, status: .skipped, skipReason: "Excluded by rule")
            } catch {
                AppLogger.error("Failed to update job status: \(error)")
            }
            return
        }

        // Capture screenshot
        do {
            let frame = try await captureScreen(jobId: jobId)
            try captureJobRepository.update(id: jobId, status: .succeeded, executedAt: Date())

            // Save observation
            let observation = Observation(
                captureJobId: jobId,
                capturedAt: frame.capturedAt,
                imagePath: frame.imageURL.path,
                imageWidth: frame.width,
                imageHeight: frame.height,
                frontmostApp: frame.frontmostApp ?? context.appName,
                frontmostBundleId: frame.frontmostBundleId ?? context.bundleId,
                frontmostWindowTitle: frame.frontmostWindowTitle ?? context.windowTitle,
                displayId: frame.displayID,
                captureState: .captured
            )
            try observationRepository.save(observation)

            // Run inference asynchronously
            Task {
                await inferenceService.infer(observationId: observation.id, imageURL: frame.imageURL,
                                             frontmostApp: context.appName,
                                             frontmostWindowTitle: context.windowTitle)
            }
        } catch {
            AppLogger.error("Capture failed: \(error)")
            try? captureJobRepository.update(id: jobId, status: .failed, errorMessage: error.localizedDescription)
        }
    }

    private func captureScreen(jobId: String) async throws -> CapturedFrame {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = preferredDisplay(from: content) else {
            throw CaptureError.noDisplay
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.width = display.width
        config.height = display.height
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = false

        let image = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: config
        )

        let now = Date()
        let obsId = UUID().uuidString
        let imageURL = fileStorageService.screenshotPath(for: now, id: obsId)

        // Save as JPEG
        let nsImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        guard let tiffData = nsImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.7]) else {
            throw CaptureError.imageConversionFailed
        }
        try jpegData.write(to: imageURL)

        let context = getFrontmostContext()

        return CapturedFrame(
            imageURL: imageURL,
            capturedAt: now,
            displayID: "\(display.displayID)",
            width: image.width,
            height: image.height,
            frontmostApp: context.appName,
            frontmostBundleId: context.bundleId,
            frontmostWindowTitle: context.windowTitle
        )
    }

    private func preferredDisplay(from content: SCShareableContent) -> SCDisplay? {
        let displayFrames = content.displays.map { ($0.displayID, CGDisplayBounds($0.displayID)) }

        if let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
           let windowBounds = frontmostWindowBounds(for: pid),
           let displayID = CaptureService.bestDisplayID(for: windowBounds, displayFrames: displayFrames) {
            return content.displays.first { $0.displayID == displayID }
        }

        return content.displays.first
    }

    private func frontmostWindowBounds(for pid: pid_t) -> CGRect? {
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return nil
        }

        for info in windowList {
            guard let ownerPID = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  ownerPID == pid else {
                continue
            }

            let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
            guard layer == 0,
                  let boundsDictionary = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDictionary),
                  !bounds.isEmpty else {
                continue
            }

            return bounds
        }

        return nil
    }

    static func bestDisplayID(
        for windowBounds: CGRect,
        displayFrames: [(id: CGDirectDisplayID, bounds: CGRect)]
    ) -> CGDirectDisplayID? {
        guard !displayFrames.isEmpty else { return nil }

        let displayByIntersection = displayFrames
            .map { (id: $0.id, area: windowBounds.intersection($0.bounds).integral.area) }
            .max { $0.area < $1.area }

        if let displayByIntersection, displayByIntersection.area > 0 {
            return displayByIntersection.id
        }

        let midpoint = CGPoint(x: windowBounds.midX, y: windowBounds.midY)
        return displayFrames.first(where: { $0.bounds.contains(midpoint) })?.id ?? displayFrames.first?.id
    }

    public func getFrontmostContext() -> FrontmostContext {
        let workspace = NSWorkspace.shared
        let frontApp = workspace.frontmostApplication
        var windowTitle: String?

        // Try to get window title via Accessibility API
        if let app = frontApp {
            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            var value: AnyObject?
            let result = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &value)
            if result == .success,
               let focusedWindowValue = value,
               CFGetTypeID(focusedWindowValue) == AXUIElementGetTypeID() {
                let focusedWindow = unsafeBitCast(focusedWindowValue, to: AXUIElement.self)
                var titleValue: AnyObject?
                let titleResult = AXUIElementCopyAttributeValue(
                    focusedWindow,
                    kAXTitleAttribute as CFString,
                    &titleValue
                )
                if titleResult == .success {
                    windowTitle = titleValue as? String
                }
            }
        }

        return FrontmostContext(
            appName: frontApp?.localizedName,
            bundleId: frontApp?.bundleIdentifier,
            windowTitle: windowTitle
        )
    }
}

private extension CGRect {
    var area: CGFloat {
        guard !isNull, !isEmpty else { return 0 }
        return width * height
    }
}

public enum CaptureError: Error, LocalizedError {
    case noDisplay
    case imageConversionFailed
    case permissionDenied

    public var errorDescription: String? {
        switch self {
        case .noDisplay: return "ディスプレイが見つかりません"
        case .imageConversionFailed: return "画像変換に失敗しました"
        case .permissionDenied: return "画面収録の権限がありません"
        }
    }
}
