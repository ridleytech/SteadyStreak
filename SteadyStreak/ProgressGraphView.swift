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

    @State private var points: [DataService.DailyPoint] = []
    @State private var selectedPoint: DataService.DailyPoint? = nil // ⬅️ ADDED

    private let dateFormatter: DateFormatter = { // ⬅️ ADDED
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                if points.isEmpty {
                    ContentUnavailableView(
                        "No Data",
                        systemImage: "chart.xyaxis.line",
                        description: Text("Log reps to see your progress.")
                    )
                } else {
                    Chart { // ⬅️ CHANGED: Use Chart { } builder
                        ForEach(points, id: \.id) { p in
                            LineMark(
                                x: .value("Day", p.day),
                                y: .value("Total", p.total)
                            )
                            PointMark(
                                x: .value("Day", p.day),
                                y: .value("Total", p.total)
                            )
                        }

                        // Selection adornments (rule + highlighted point + callout)
                        if let sel = selectedPoint {
                            RuleMark(x: .value("Selected Day", sel.day))
                                .foregroundStyle(.secondary)
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                                .annotation(position: .top, alignment: .leading) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(dateFormatter.string(from: sel.day))
                                            .font(.caption).fontWeight(.semibold)
                                        // Show reps too; remove this line if you only want the date
                                        Text("\(sel.total) reps")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(8)
                                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                }

                            PointMark(
                                x: .value("Day", sel.day),
                                y: .value("Total", sel.total)
                            )
                            .symbolSize(80)
                        }
                    }
                    .chartOverlay { proxy in // ⬅️ Tap/drag to select nearest point
                        GeometryReader { geo in
                            Rectangle()
                                .fill(.clear)
                                .contentShape(Rectangle())
                                .gesture(
                                    DragGesture(minimumDistance: 0)
                                        .onChanged { value in
                                            // Convert tap location to plot area's x
                                            let plotFrame = geo[proxy.plotAreaFrame]
                                            guard plotFrame.contains(value.location) else { return }
                                            let xInPlot = value.location.x - plotFrame.minX
                                            if let date: Date = proxy.value(atX: xInPlot) {
                                                if let nearest = nearestPoint(to: date) {
                                                    selectedPoint = nearest
                                                }
                                            }
                                        }
                                        .onEnded { _ in
                                            // Keep selection on lift; uncomment next line to clear
                                            // selectedPoint = nil
                                        }
                                )
                        }
                    }
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .day, count: 7)) // weekly ticks for a 60-day window
                    }
                    .frame(height: 260)
                }
                Spacer()
            }
            .padding()
            .navigationTitle(exercise.name + " Progress")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .task { await load() }
    }

    @MainActor private func load() async {
        do {
            points = try DataService.dailySeries(for: exercise, context: context, daysBack: 60)
        } catch { points = [] }
    }

    // MARK: - Helpers

    private func nearestPoint(to date: Date) -> DataService.DailyPoint? {
        guard !points.isEmpty else { return nil }
        return points.min { a, b in
            abs(a.day.timeIntervalSince(date)) < abs(b.day.timeIntervalSince(date))
        }
    }
}
