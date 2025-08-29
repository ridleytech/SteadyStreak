//
//  StreakPathTipCard.swift
//  SteadyStreak
//
//  Created by Randall Ridley on 8/29/25.
//

import Foundation
import SwiftUI

struct StreakPathTipCard: View {
    let palette: ThemePalette?

    var body: some View {
        GroupBox {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.title2)
                    .foregroundStyle(palette?.onTint ?? .accentColor)

                VStack(alignment: .leading, spacing: 6) {
                    Text("What’s a StreakPath?")
                        .font(.headline)

                    Text("""
                    A StreakPath is a long-term plan to hit a MacroGoal. Set a **Target Total** and \
                    we’ll compute your daily pace and **Completion Date**. Based on your daily goal, \
                    we'll calculate how your **cumulative progress** tracks against the **target** in the progress graph.
                    """)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                    Divider().opacity(0.25)

                    VStack(alignment: .leading, spacing: 4) {
                        Label("Pick a **Target Total**", systemImage: "target")
//                        Label("Choose a **Completion Date**", systemImage: "calendar")
                        Label("We compute your **Daily Pace**", systemImage: "speedometer")
                        Label("Graph shows **ahead/behind** vs. target", systemImage: "chart.xyaxis.line")
                    }
                    .font(.caption)
                }
            }
            .padding(.vertical, 4)
        }
    }
}
