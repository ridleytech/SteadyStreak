//
//  ProgressGraphView.swift
//  SteadyStreak
//
//  Created by Randall Ridley on 8/21/25.
//

import Charts
import SwiftData
import SwiftUI

struct ProgressGraphView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var selectedRecord: Exercise?

    let exercise: Exercise
    let palette: ThemePalette

    // MARK: - Data for "Progress" tab

    @State private var points: [DataService.DailyPoint] = []
    @State private var selectedPoint: DataService.DailyPoint? = nil

    // MARK: - Macro / StreakPath

    enum ChartTab: Hashable { case progress, streakPath }
    @State private var tab: ChartTab = .progress

    private struct MacroSnapshot {
        let targetTotal: Int
        let completionDate: Date
    }

    @State private var macro: MacroSnapshot? = nil // present => show segmented control

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                // Inline header (no toolbar ambiguity)
                HStack {
                    Text(exercise.name + " Progress")
                        .font(.headline)
                    Spacer()
                    Button("Close") { dismiss() }
                }

                // Segmented control: only if we have a valid macro goal
                if macro != nil {
                    Picker("", selection: $tab) {
                        Text("Progress").tag(ChartTab.progress)
                        Text("StreakPath").tag(ChartTab.streakPath)
                    }
                    .pickerStyle(.segmented)
                }

                if points.isEmpty {
                    ContentUnavailableView(
                        "No Data",
                        systemImage: "chart.xyaxis.line",
                        description: Text("Log reps to see your progress.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                } else {
                    GeometryReader { outerGeo in
                        // Active series: raw daily totals OR cumulative totals for StreakPath
                        let series = (tab == .streakPath && macro != nil) ? cumulative(points) : points

                        // Dynamic content width: wider with more points; never smaller than container
                        let perPoint: CGFloat = 18
                        let dynamicWidth = max(outerGeo.size.width, CGFloat(series.count) * perPoint)

                        // Fixed X/Y domains (no rescale on selection)
                        let xDomain = (series.map { $0.day }.min() ?? Date())...(series.map { $0.day }.max() ?? Date())

                        // Y domain: include target line in StreakPath
                        let (minY, maxY): (Int, Int) = {
                            let localMin = series.map { $0.total }.min() ?? 0
                            var localMax = series.map { $0.total }.max() ?? 1
                            if let m = macro, tab == .streakPath {
                                localMax = max(localMax, m.targetTotal)
                            }
                            return (localMin, localMax)
                        }()
                        let pad = max(1, Int(Double(maxY - minY) * 0.1))
                        let yDomain = (minY - pad)...(maxY + pad)

                        // Avoid repeated-looking x labels: pick stride from density + width
                        let calendar = Calendar.current
                        let uniqueDays = Array(Set(series.map { calendar.startOfDay(for: $0.day) })).sorted()
                        let targetLabels = min(10, max(4, Int(outerGeo.size.width / 80)))
                        let strideDays = max(1, uniqueDays.count / max(1, targetLabels))

                        ScrollView(.horizontal, showsIndicators: true) {
                            Chart {
                                // Base series (static marks → no jump on select)
                                ForEach(series, id: \.id) { p in
                                    LineMark(
                                        x: .value("Date", p.day),
                                        y: .value("Total", p.total)
                                    )
                                    .interpolationMethod(.catmullRom)

                                    PointMark(
                                        x: .value("Date", p.day),
                                        y: .value("Total", p.total)
                                    )
                                }

                                // StreakPath overlays
                                if let m = macro, tab == .streakPath {
                                    RuleMark(y: .value("Target", m.targetTotal))
                                        .foregroundStyle(.secondary)
                                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                                        .annotation(position: .topTrailing) {
                                            Text("Target: \(m.targetTotal)")
                                                .font(.caption2)
                                                .padding(.horizontal, 6).padding(.vertical, 4)
                                                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 6))

//                                            Text("🎯")
//                                                .font(.caption2)
//                                                .padding(.horizontal, 6).padding(.vertical, 4)
//                                                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 6))
                                        }

                                    RuleMark(x: .value("Due", m.completionDate))
                                        .foregroundStyle(.secondary)
                                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                                        .annotation(position: .top) {
                                            Text("Due: \(m.completionDate.formatted(date: .abbreviated, time: .omitted))")
                                                .font(.caption2)
                                                .padding(.horizontal, 6).padding(.vertical, 4)
                                                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 6))
                                        }
                                }
                            }
                            .chartXScale(domain: xDomain)
                            .chartYScale(domain: yDomain)
                            .chartXAxis {
                                AxisMarks(values: .stride(by: .day, count: strideDays)) { value in
                                    if let dateValue = value.as(Date.self) {
                                        AxisGridLine()
                                        AxisValueLabel {
                                            Text(dateValue.formatted(date: .abbreviated, time: .omitted))
                                                .font(.caption2)
                                        }
                                    }
                                }
                            }
                            // Selection drawn in overlay (no re-layout)
                            .chartOverlay { proxy in
                                GeometryReader { geo in
                                    let plotFrame = geo[proxy.plotAreaFrame]
                                    ZStack {
                                        Rectangle()
                                            .fill(.clear)
                                            .contentShape(Rectangle())
                                            .gesture(
                                                DragGesture(minimumDistance: 0)
                                                    .onChanged { value in
                                                        guard plotFrame.contains(value.location) else { return }
                                                        let xInPlot = value.location.x - plotFrame.minX
                                                        if let date: Date = proxy.value(atX: xInPlot),
                                                           let nearest = nearestPoint(in: series, to: date)
                                                        {
                                                            withTransaction(Transaction(animation: nil)) {
                                                                selectedPoint = nearest
                                                            }
                                                        }
                                                    }
                                            )

                                        if let sel = selectedPoint,
                                           let px = proxy.position(forX: sel.day),
                                           let py = proxy.position(forY: sel.total)
                                        {
                                            // Overlay coords
                                            let pt = CGPoint(x: plotFrame.minX + px, y: plotFrame.minY + py)

                                            // Focus ring
                                            Circle()
                                                .strokeBorder(.primary, lineWidth: 2)
                                                .background(Circle().fill(Color(uiColor: .systemBackground)))
                                                .frame(width: 10, height: 10)
                                                .position(pt)

                                            // Date bubble clamped inside plot
                                            let bubbleSize = CGSize(width: 140, height: 34)
                                            let placeRight = pt.x < plotFrame.midX
                                            let placeBelow = pt.y < plotFrame.midY
                                            let dx: CGFloat = placeRight ? 12 : -12
                                            let dy: CGFloat = placeBelow ? 12 : -12

                                            let proposedOriginX = pt.x + (placeRight ? dx : -dx) + (placeRight ? 0 : -bubbleSize.width)
                                            let proposedOriginY = pt.y + (placeBelow ? dy : -dy) + (placeBelow ? 0 : -bubbleSize.height)

                                            let inset: CGFloat = 6
                                            let clampedOriginX = min(max(proposedOriginX, plotFrame.minX + inset),
                                                                     plotFrame.maxX - bubbleSize.width - inset)
                                            let clampedOriginY = min(max(proposedOriginY, plotFrame.minY + inset),
                                                                     plotFrame.maxY - bubbleSize.height - inset)

                                            let centerX = clampedOriginX + bubbleSize.width / 2
                                            let centerY = clampedOriginY + bubbleSize.height / 2

                                            Text("\(sel.total) - \(sel.day.formatted(date: .numeric, time: .omitted))")
                                                .font(.caption2).fontWeight(.semibold)
                                                .padding(.horizontal, 10).padding(.vertical, 6)
                                                .frame(width: bubbleSize.width, height: bubbleSize.height, alignment: .leading)
                                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
                                                .position(x: centerX, y: centerY)
                                        }
                                    }
                                }
                            }
                            .frame(width: dynamicWidth, height: 260)
                        }
                        .onAppear {
                            withTransaction(Transaction(animation: nil)) {
                                selectedPoint = series.last
                            }
                        }
                    }
                    .frame(height: 260)
                }

                Spacer()
            }
            .padding()
        }
        .task { await load() }
    }

    // MARK: - Load Data

    @MainActor private func load() async {
        do {
            // 1) Daily series for the Progress tab
            points = try DataService.dailySeries(for: exercise, context: context, daysBack: 60)

//            print("🔍 Loaded daily series with \(points.count) points")

            // 2) MacroGoal for this exercise (avoid @Query capture issues)
            let exID = exercise.id // capture constant

//            print("🔍 Fetching MacroGoal for exercise ID: \(exID)")

            let fd = FetchDescriptor<MacroGoal>( // adjust field names if needed
                predicate: #Predicate { $0.exerciseID == exID }
            )

            if let m = try context.fetch(fd).first,
               let due = parseDate(m.completionDate)
            {
                let target = (m.targetTotal as? Int) ?? (m.targetTotal ?? 0)
                macro = MacroSnapshot(targetTotal: target, completionDate: due)
            } else {
                macro = nil
                tab = .progress
            }
        } catch {
            points = []
            macro = nil
            tab = .progress
        }
    }

    // MARK: - Helpers

    /// Build a cumulative series (for StreakPath tab)
    private func cumulative(_ pts: [DataService.DailyPoint]) -> [DataService.DailyPoint] {
        let sorted = pts.sorted { $0.day < $1.day }
        var running = 0
        return sorted.map { p in
            running += p.total
            return DataService.DailyPoint(day: p.day, total: running)
        }
    }

    private func nearestPoint(in series: [DataService.DailyPoint], to date: Date) -> DataService.DailyPoint? {
        guard !series.isEmpty else { return nil }
        return series.min { a, b in
            abs(a.day.timeIntervalSince(date)) < abs(b.day.timeIntervalSince(date))
        }
    }
}
