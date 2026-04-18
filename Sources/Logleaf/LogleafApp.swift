import SwiftUI
import AppKit
import LogleafLib

private final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
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
