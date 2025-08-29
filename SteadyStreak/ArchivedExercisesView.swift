//
//  ArchivedExercisesView.swift
//  SteadyStreak
//
//  Created by Randall Ridley on 8/28/25.
//

import Foundation
import SwiftData
import SwiftUI

struct ArchivedExercisesView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    // Only archived items
    @Query(
        filter: #Predicate<Exercise> { $0.isArchived == true },
        sort: [SortDescriptor(\Exercise.createdAt, order: .forward)]
    ) private var archived: [Exercise]

    var body: some View {
        NavigationStack {
            Group {
                if archived.isEmpty {
                    ContentUnavailableView(
                        "No Archived Streaks",
                        systemImage: "archivebox",
                        description: Text("When you archive a streak, it’ll show up here.")
                    )
                } else {
                    List {
                        ForEach(archived) { ex in
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(ex.name).font(.headline)
                                    Text("Daily goal: \(ex.dailyGoal)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()

                                Button {
                                    unarchive(ex)
                                } label: {
                                    Label("Unarchive", systemImage: "arrow.uturn.left")
                                }
                                .buttonStyle(.bordered)
                            }
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                Button("Unarchive") { unarchive(ex) }.tint(.green)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    delete(ex)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Archived Streaks")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    // MARK: - Actions

    private func unarchive(_ ex: Exercise) {
        withAnimation {
            ex.isArchived = false
            LocalReminderScheduler.rescheduleAll(using: context)
            try? context.save()
        }
    }

    private func delete(_ ex: Exercise) {
        withAnimation {
            context.delete(ex)
            LocalReminderScheduler.rescheduleAll(using: context)
            try? context.save()
        }
    }
}
