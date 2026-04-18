import SwiftUI
import AppKit

public struct WeeklyMonthlySummaryView: View {
    @StateObject var viewModel: SummaryViewModel

    public init(viewModel: SummaryViewModel) {
        self._viewModel = StateObject(wrappedValue: viewModel)
    }

    private let weekdaySymbols = ["日", "月", "火", "水", "木", "金", "土"]
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    public var body: some View {
        VStack(spacing: 0) {
            // Header: navigation + period picker
            HStack {
                Button(action: viewModel.previousPeriod) {
                    Image(systemName: "chevron.left")
                }

                Spacer()

                HStack(spacing: 16) {
                    Text(viewModel.periodLabel)
                        .font(.title2)
                        .fontWeight(.semibold)

                    Picker("", selection: $viewModel.period) {
                        Text("週次").tag(SummaryViewModel.Period.weekly)
                        Text("月次").tag(SummaryViewModel.Period.monthly)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 140)
                }

                Spacer()

                Button(action: viewModel.nextPeriod) {
                    Image(systemName: "chevron.right")
                }
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    calendarSection

                    if viewModel.selectedDay != nil {
                        selectedDaySection
                    }

                    Divider()

                    tagBreakdownSection

                    Divider()

                    dailyChartSection
                }
                .padding()
            }
        }
        .onAppear { viewModel.loadSummary() }
        .onChange(of: viewModel.period) { viewModel.loadSummary() }
    }

    // MARK: - Calendar

    private var calendarSection: some View {
        VStack(spacing: 4) {
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(viewModel.calendarDays) { day in
                    CalendarDayCell(
                        day: day,
                        isSelected: viewModel.selectedDay.map {
                            Calendar.current.isDate($0, inSameDayAs: day.date)
                        } ?? false
                    )
                    .onTapGesture {
                        if day.isCurrentMonth {
                            viewModel.selectDay(day.date)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Selected Day Detail

    private var selectedDaySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(selectedDayTitle)
                    .font(.headline)
                Spacer()
                Button {
                    viewModel.selectedDay = nil
                    viewModel.selectedDaySessions = []
                    viewModel.selectedDaySessionTags = [:]
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }

            if viewModel.selectedDaySessions.isEmpty {
                Text("この日の記録はありません")
                    .foregroundColor(.secondary)
                    .font(.caption)
                    .padding(.vertical, 8)
            } else {
                ForEach(viewModel.selectedDaySessions) { session in
                    SessionSummaryRow(
                        session: session,
                        tags: viewModel.selectedDaySessionTags[session.id] ?? []
                    )
                }
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }

    private var selectedDayTitle: String {
        guard let day = viewModel.selectedDay else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日（E）"
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter.string(from: day)
    }

    // MARK: - Tag Breakdown

    private var tagBreakdownSection: some View {
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
                            .tint(Color(hex: summary.colorHex ?? "#4A90D9"))
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
    }

    // MARK: - Daily Chart

    private var dailyChartSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("日別作業時間")
                .font(.headline)

            if viewModel.dailyMinutes.isEmpty {
                Text("データがありません")
                    .foregroundColor(.secondary)
            } else {
                let maxMinutes = max(viewModel.dailyMinutes.map(\.minutes).max() ?? 1, 1)
                let barSpacing: CGFloat = 3

                GeometryReader { geometry in
                    let dayCount = CGFloat(viewModel.dailyMinutes.count)
                    let totalSpacing = max(dayCount - 1, 0) * barSpacing
                    let barWidth = max(18, (geometry.size.width - totalSpacing) / max(dayCount, 1))

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .bottom, spacing: barSpacing) {
                            ForEach(viewModel.dailyMinutes) { day in
                                VStack(spacing: 2) {
                                    if day.minutes > 0 {
                                        Text("\(day.minutes)")
                                            .font(.system(size: 8))
                                            .foregroundColor(.secondary)
                                    }
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(Color.accentColor.opacity(day.minutes > 0 ? 1 : 0.15))
                                        .frame(
                                            width: barWidth,
                                            height: max(CGFloat(day.minutes) / CGFloat(maxMinutes) * 80, 2)
                                        )
                                    Text(day.dateString)
                                        .font(.system(size: 9))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .frame(minWidth: geometry.size.width, alignment: .leading)
                        .frame(height: 110)
                        .padding(.top, 4)
                    }
                }
                .frame(height: 114)
            }
        }
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

// MARK: - Calendar Day Cell

private struct CalendarDayCell: View {
    let day: SummaryViewModel.CalendarDay
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Day number — always at top
            Text("\(day.day)")
                .font(.system(size: 12, weight: day.isCurrentMonth ? .medium : .regular))
                .foregroundColor(day.isCurrentMonth ? .primary : .secondary.opacity(0.4))
                .padding(.top, 4)

            // Content area with fixed space
            VStack(spacing: 2) {
                if day.isCurrentMonth && !day.topTags.isEmpty {
                    TagFlowLayout(spacing: 2) {
                        ForEach(day.topTags.prefix(2), id: \.name) { tag in
                            let bgColor = Color(hex: tag.colorHex ?? "#4A90D9")
                            Text(tag.name)
                                .font(.system(size: 9, weight: .medium))
                                .lineLimit(1)
                                .foregroundColor(bgColor.contrastingTextColor)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(bgColor)
                                .cornerRadius(4)
                        }
                    }
                }

                if day.isCurrentMonth && day.minutes > 0 {
                    Text(shortMinutes(day.minutes))
                        .font(.system(size: 8))
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 36, alignment: .top)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 60)
        .padding(.horizontal, 2)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
        )
    }

    private func shortMinutes(_ minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60
        if hours > 0 { return "\(hours)h\(mins)m" }
        return "\(mins)m"
    }
}

// MARK: - Tag Flow Layout

private struct TagFlowLayout: Layout {
    var spacing: CGFloat = 2

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrangeSubviews(in: proposal.width ?? 0, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangeSubviews(in: bounds.width, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private func arrangeSubviews(in maxWidth: CGFloat, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxX = max(maxX, x)
        }

        return (CGSize(width: maxX, height: y + rowHeight), positions)
    }
}

// MARK: - Session Summary Row

private struct SessionSummaryRow: View {
    let session: WorkSession
    let tags: [Tag]

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading) {
                Text(timeString(session.startAt))
                    .font(.caption)
                    .fontWeight(.semibold)
                Text(timeString(session.endAt))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(width: 44)

            RoundedRectangle(cornerRadius: 2)
                .fill(tags.first.flatMap { $0.colorHex.map { Color(hex: $0) } } ?? Color.accentColor)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 2) {
                Text(session.displayTitle)
                    .font(.callout)
                    .fontWeight(.medium)
                HStack(spacing: 4) {
                    ForEach(tags) { tag in
                        Text(tag.name)
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color(hex: tag.colorHex ?? "#4A90D9").opacity(0.2))
                            .foregroundColor(Color(hex: tag.colorHex ?? "#4A90D9"))
                            .cornerRadius(3)
                    }
                    Spacer()
                    Text("\(session.durationMinutes)分")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}
