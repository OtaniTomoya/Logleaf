import SwiftUI

public struct MainWindowView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab: Tab = .timeline

    public enum Tab: String, CaseIterable {
        case timeline = "タイムライン"
        case summary = "サマリ"
        case exclusions = "除外ルール"
        case settings = "設定"
        case troubleshoot = "トラブルシュート"
    }

    public init() {}

    public var body: some View {
        Group {
            if !appState.isSetupComplete {
                SetupView(appState: appState)
            } else {
                NavigationSplitView {
                    List(Tab.allCases, id: \.self, selection: $selectedTab) { tab in
                        Label(tab.rawValue, systemImage: iconForTab(tab))
                    }
                    .listStyle(.sidebar)
                    .frame(minWidth: 160)
                } detail: {
                    contentForTab(selectedTab)
                }
            }
        }
        .frame(minWidth: 800, minHeight: 500)
        .onAppear {
            if appState.shouldOpenSettings {
                selectedTab = .settings
                appState.shouldOpenSettings = false
            }
        }
        .onChange(of: appState.shouldOpenSettings) {
            if appState.shouldOpenSettings {
                selectedTab = .settings
                appState.shouldOpenSettings = false
            }
        }
    }

    @ViewBuilder
    private func contentForTab(_ tab: Tab) -> some View {
        switch tab {
        case .timeline:
            DailyTimelineView(
                viewModel: DailyTimelineViewModel(
                    workSessionRepository: appState.workSessionRepository,
                    tagRepository: appState.tagRepository,
                    aggregationService: appState.aggregationService,
                    observationRepository: appState.observationRepository
                ),
                appState: appState
            )
        case .summary:
            WeeklyMonthlySummaryView(
                viewModel: SummaryViewModel(
                    workSessionRepository: appState.workSessionRepository,
                    tagRepository: appState.tagRepository
                )
            )
        case .exclusions:
            ExclusionRuleView(
                viewModel: ExclusionRuleViewModel(exclusionService: appState.exclusionService)
            )
        case .settings:
            SettingsView(viewModel: SettingsViewModel(
                settingsService: appState.settingsService,
                inferenceService: appState.inferenceService
            ))
            .environmentObject(appState)
        case .troubleshoot:
            TroubleshootView()
                .environmentObject(appState)
        }
    }

    private func iconForTab(_ tab: Tab) -> String {
        switch tab {
        case .timeline: return "calendar.day.timeline.left"
        case .summary: return "chart.bar"
        case .exclusions: return "eye.slash"
        case .settings: return "gear"
        case .troubleshoot: return "wrench.and.screwdriver"
        }
    }
}
