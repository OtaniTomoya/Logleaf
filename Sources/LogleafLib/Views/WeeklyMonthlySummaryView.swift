import SwiftUI
import AppKit

public struct WeeklyMonthlySummaryView: View {
    @StateObject var viewModel: SummaryViewModel

    public init(viewModel: SummaryViewModel) {
        self._viewModel = StateObject(wrappedValue: viewModel)
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Period selector and navigation
            HStack {
                Button(action: viewModel.previousPeriod) {
                    Image(systemName: "chevron.left")
                }

                Spacer()

                Picker("", selection: $viewModel.period) {
                    Text("週次").tag(SummaryViewModel.Period.weekly)
                    Text("月次").tag(SummaryViewModel.Period.monthly)
                }
                .pickerStyle(.segmented)
                .frame(width: 160)

                Spacer()

                Button(action: viewModel.nextPeriod) {
                    Image(systemName: "chevron.right")
                }
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Summary stats
                    HStack(spacing: 24) {
                        StatCard(title: "合計時間", value: formatMinutes(viewModel.totalMinutes), icon: "clock")
                        StatCard(title: "未分類", value: formatMinutes(viewModel.unclassifiedMinutes), icon: "questionmark.circle")
                        StatCard(title: "平均信頼度", value: String(format: "%.0f%%", viewModel.averageConfidence * 100), icon: "brain")
                        StatCard(title: "手動修正率", value: String(format: "%.0f%%", viewModel.manualEditRate), icon: "pencil")
                    }

                    Divider()

                    // Tag breakdown
                    VStack(alignment: .leading, spacing: 8) {
                        Text("タグ別時間")
                            .font(.headline)

                        if viewModel.tagSummaries.isEmpty {
                            Text("データがありません")
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(viewModel.tagSummaries) { summary in
                                HStack {
                                    Circle()
                                        .fill(Color(hex: summary.colorHex ?? "#4A90D9"))
                                        .frame(width: 10, height: 10)
                                    Text(summary.tagName)
                                        .frame(width: 120, alignment: .leading)
                                    ProgressView(value: summary.percentage, total: 100)
                                    Text(formatMinutes(summary.minutes))
                                        .frame(width: 80, alignment: .trailing)
                                        .font(.caption)
                                    Text(String(format: "%.0f%%", summary.percentage))
                                        .frame(width: 40, alignment: .trailing)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }

                    Divider()

                    // Daily chart
                    VStack(alignment: .leading, spacing: 8) {
                        Text("日別作業時間")
                            .font(.headline)

                        if viewModel.dailyMinutes.isEmpty {
                            Text("データがありません")
                                .foregroundColor(.secondary)
                        } else {
                            HStack(alignment: .bottom, spacing: 4) {
                                ForEach(viewModel.dailyMinutes) { day in
                                    VStack(spacing: 2) {
                                        if day.minutes > 0 {
                                            Text("\(day.minutes)")
                                                .font(.system(size: 8))
                                        }
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(Color.accentColor)
                                            .frame(width: 24, height: max(CGFloat(day.minutes) / 6, 2))
                                        Text(day.dateString)
                                            .font(.system(size: 8))
                                            .rotationEffect(.degrees(-45))
                                    }
                                }
                            }
                            .frame(height: 120)
                        }
                    }
                }
                .padding()
            }
        }
        .onAppear { viewModel.loadSummary() }
        .onChange(of: viewModel.period) { viewModel.loadSummary() }
    }

    private func formatMinutes(_ minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60
        if hours > 0 {
            return "\(hours)h\(mins)m"
        }
        return "\(mins)m"
    }
}

public struct StatCard: View {
    public let title: String
    public let value: String
    public let icon: String

    public init(title: String, value: String, icon: String) {
        self.title = title
        self.value = value
        self.icon = icon
    }

    public var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.accentColor)
            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }
}
