import SwiftUI
import LogleafLib

@main
struct LogleafApp: App {
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

        Settings {
            SettingsView(viewModel: SettingsViewModel(
                settingsService: appState.settingsService,
                inferenceService: appState.inferenceService
            ))
                .environmentObject(appState)
        }
    }
}
