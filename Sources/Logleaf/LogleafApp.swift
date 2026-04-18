import SwiftUI
import AppKit
import LogleafLib

private final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let iconImage = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = iconImage
        }
    }
}

@main
struct LogleafApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarPopoverView()
                .environmentObject(appState)
        } label: {
            Image(systemName: appState.isCapturing ? "leaf.fill" : "leaf")
        }
        .menuBarExtraStyle(.window)

        Window("Logleaf", id: "main") {
            MainWindowView()
                .environmentObject(appState)
        }

    }
}
