import Foundation
import ScreenCaptureKit
import AppKit
import CoreGraphics

public final class PermissionService {
    public init() {}

    public func checkScreenCapturePermission() async -> Bool {
        do {
            // Attempting to get shareable content will trigger permission check
            _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            return true
        } catch {
            return false
        }
    }

    public func requestScreenCapturePermission() {
        // Open System Preferences to the Privacy & Security pane
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    public func checkAccessibilityPermission() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): false] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    public func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }
}
