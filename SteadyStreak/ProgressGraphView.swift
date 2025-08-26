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
    @State private var selectedPoint: DataService.DailyPoint? = nil

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

                if points.isEmpty {
                    ContentUnavailableView(
                        "No Data",
                        systemImage: "chart.xyaxis.line",
                        description: Text("Log reps to see your progress.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                } else {
                    GeometryReader { outerGeo in
                        // Dynamic content width: wider with more points; never smaller than container
                        let perPoint: CGFloat = 18
                        let dynamicWidth = max(outerGeo.size.width, CGFloat(points.count) * perPoint)

                        // Fixed domains so selection doesn’t rescale → prevents “jump”
                        let xDomain = (points.map { $0.day }.min() ?? Date())...(points.map { $0.day }.max() ?? Date())
                        let minY = points.map { $0.total }.min() ?? 0
                        let maxY = points.map { $0.total }.max() ?? 1
                        let pad = max(1, Int(Double(maxY - minY) * 0.1))
                        let yDomain = (minY - pad)...(maxY + pad)

                        // Dynamic x-axis label density (avoid repeated-looking labels)
                        let calendar = Calendar.current
                        let uniqueDays = Array(Set(points.map { calendar.startOfDay(for: $0.day) })).sorted()
                        let targetLabels = min(10, max(4, Int(outerGeo.size.width / 80)))
                        let strideDays = max(1, uniqueDays.count / max(1, targetLabels))

                        ScrollView(.horizontal, showsIndicators: true) {
                            Chart {
                                ForEach(points, id: \.id) { p in
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
                            // Selection + tooltip drawn in overlay so marks don’t change (no jump)
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
                                                           let nearest = nearestPoint(to: date)
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
                                            // Convert plot coords → overlay coords
                                            let point = CGPoint(x: plotFrame.minX + px, y: plotFrame.minY + py)

                                            // Focus ring at selected point
                                            Circle()
                                                .strokeBorder(.primary, lineWidth: 2)
                                                .background(Circle().fill(Color(uiColor: .systemBackground)))
                                                .frame(width: 10, height: 10)
                                                .position(point)

                                            // Date bubble near the point; compute CLAMPED ORIGIN, then convert to CENTER
                                            let bubbleSize = CGSize(width: 140, height: 34)
                                            let placeRight = point.x < plotFrame.midX
                                            let placeBelow = point.y < plotFrame.midY
                                            let dx: CGFloat = placeRight ? 12 : -12
                                            let dy: CGFloat = placeBelow ? 12 : -12

                                            // Proposed TOP-LEFT origin before clamping
                                            let proposedOriginX = point.x + (placeRight ? dx : -dx) + (placeRight ? 0 : -bubbleSize.width)
                                            let proposedOriginY = point.y + (placeBelow ? dy : -dy) + (placeBelow ? 0 : -bubbleSize.height)

                                            // Clamp origin inside plot with padding
                                            let inset: CGFloat = 6
                                            let clampedOriginX = min(max(proposedOriginX, plotFrame.minX + inset), plotFrame.maxX - bubbleSize.width - inset)
                                            let clampedOriginY = min(max(proposedOriginY, plotFrame.minY + inset), plotFrame.maxY - bubbleSize.height - inset)

                                            // Convert origin -> CENTER for .position
                                            let centerX = clampedOriginX + bubbleSize.width / 2
                                            let centerY = clampedOriginY + bubbleSize.height / 2

                                            Text(sel.day.formatted(date: .numeric, time: .omitted))
                                                .font(.caption2).fontWeight(.semibold)
                                                .padding(.horizontal, 10).padding(.vertical, 6)
                                                .frame(width: bubbleSize.width, height: bubbleSize.height, alignment: .leading)
                                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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
                                selectedPoint = points.last
                            }
                        }
                    }
                    .frame(height: 260) // for GeometryReader
                }

                Spacer()
            }
            .padding()
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
