//
//  ContentViews.swift
//  SteadyStreak
//
//  Created by Randall Ridley on 8/21/25.
//

import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase // ⬅️ ADDED
    @Query(sort: [SortDescriptor(\Exercise.createdAt, order: .forward)]) private var exercises: [Exercise]
    @Query private var settingsArray: [AppSettings]

    @State private var showingAdd = false
    @State private var showingLogFor: Exercise? = nil
    @State private var showingSettings = false
    @State private var showingUpgradeAlert = false
    @State private var showingUpgradeSheet = false
    @State private var editingExercise: Exercise? = nil
    @State private var editingGoal: Exercise? = nil
    @State private var showingMacroFor: Exercise? = nil
    @State private var showingSaved = false
    @State private var showingGraphFor: Exercise? = nil
    @State private var deletingExercise: Exercise? = nil
    @State private var dayAnchor = Calendar.current.startOfDay(for: Date()) // ⬅️ ADDED
    @State private var showingAddEntry = false
    @State private var showingAddEntryFor: Exercise? = nil

//    private var settings: AppSettings? { settingsArray.first }

    private var settings: AppSettings {
        if let s = settingsArray.first { return s }
        let s = AppSettings(); context.insert(s); return s
    }

    private var palette: ThemePalette { ThemeKit.palette(settings) }
    private var isDark: Bool { ThemeKit.isDark(settings) }

    // MARK: - Grouping helpers ⬅️ ADDED (for “Today’s Streaks” vs “Other Streaks”)

    /// Sunday = 1, Monday = 2, ... (matches your scheduledWeekdays indexing)
    private var todayWeekdayIndex: Int {
        Calendar.current.component(.weekday, from: dayAnchor)
    }

    /// Exercises scheduled for *today*
    private var todaysExercises: [Exercise] {
        exercises.filter { $0.scheduledWeekdays.contains(todayWeekdayIndex) }
    }

    /// All other exercises (not scheduled for *today*)
    private var otherExercises: [Exercise] {
        exercises.filter { !$0.scheduledWeekdays.contains(todayWeekdayIndex) }
    }

    private func performDelete(_ ex: Exercise) {
        withAnimation {
            context.delete(ex)
            LocalReminderScheduler.rescheduleAll(using: context)
            try? context.save()
        }
    }

    // Extracted row so we can reuse it in both sections (keeps your Add Entry updates)
    private func row(for ex: Exercise) -> some View {
        ExerciseRow(exercise: ex, palette: palette)
            .contentShape(Rectangle())
            .onTapGesture { showingLogFor = ex }
            .contextMenu {
                Button("Change Daily Goal") { editingGoal = ex }
                Button("Log Today's Reps") { showingLogFor = ex }
                Button("Add Entry") { showingAddEntryFor = ex }
                Button("Edit Schedule") { editingExercise = ex }
                Button("Create StreakPath") { showingMacroFor = ex }
                Button("View Progress Graph") { showingGraphFor = ex }
            }
            .swipeActions(edge: .trailing) { Button("Log") { showingLogFor = ex }.tint(palette.onTint) }
            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                Button("Edit") { editingExercise = ex }.tint(.blue)

                Button(role: .destructive) {
                    deletingExercise = ex
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
            .listRowBackground(Color.clear)
    }

    @ViewBuilder
    private var mainContent: some View {
        if exercises.isEmpty {
            ContentUnavailableView(
                "No Exercises",
                systemImage: "figure.strengthtraining.traditional",
                description: Text("Add an exercise with a daily rep goal to get started.")
            )
        } else {
            List {
                // Top group: today's scheduled streaks
                if !todaysExercises.isEmpty {
                    Section {
                        ForEach(todaysExercises) { ex in
                            row(for: ex)
                        }
                        .onDelete { indexSet in
                            // Map IndexSet (section-local) to concrete models
                            let toDelete = indexSet.map { todaysExercises[$0] }
                            withAnimation {
                                for ex in toDelete { context.delete(ex) }
                                LocalReminderScheduler.rescheduleAll(using: context)
                            }
                        }
                    }
                    header: {
                        Text("Today's Streaks")
                            .font(.subheadline.weight(.semibold))
                            .textCase(.none) // prevent automatic ALL CAPS
                            .foregroundStyle(palette.onTint) // or palette.onTint
                    }
//                    .foregroundStyle(palette.text) // Make section header more prominent
                }

                // Remaining streaks
                if !otherExercises.isEmpty {
                    if !todaysExercises.isEmpty {
                        Section("Other Streaks") {
                            ForEach(otherExercises) { ex in
                                row(for: ex)
                            }
                            .onDelete { indexSet in
                                let toDelete = indexSet.map { otherExercises[$0] }
                                withAnimation {
                                    for ex in toDelete { context.delete(ex) }
                                    LocalReminderScheduler.rescheduleAll(using: context)
                                }
                            }
                        }
                    } else {
                        // If there are no “Today” items, just show a flat list
                        ForEach(otherExercises) { ex in
                            row(for: ex)
                        }
                        .onDelete { indexSet in
                            let toDelete = indexSet.map { otherExercises[$0] }
                            withAnimation {
                                for ex in toDelete { context.delete(ex) }
                                LocalReminderScheduler.rescheduleAll(using: context)
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
        }
    }

    private func handleAddExerciseTapped() {
        print("Add Exercise button tapped", settings.hasFullUnlock)
        if settings.hasFullUnlock == false && exercises.count >= 3 {
            print("Showing upgrade alert")
            showingUpgradeAlert = true
        } else {
            print("Showing add exercise view")
            showingAdd = true
        }
    }

    var body: some View {
        NavigationStack {
            mainContent
                .id(dayAnchor) // ⬅️ ADDED: Rebuild view tree when day flips (updates grouping)
                .navigationTitle("SteadyStreak")
                .toolbar {
//                    ToolbarItem(placement: .topBarLeading) { Button { LocalReminderScheduler.rescheduleAll(using: context) } label: { Image(systemName: "bell.badge") } }
                    ToolbarItem(placement: .topBarTrailing) { Button { showingSaved = true } label: { Image(systemName: "bookmark") } }
                    ToolbarItem(placement: .topBarTrailing) { Button { showingSettings = true } label: { Image(systemName: "gearshape") } }
                    ToolbarItem(placement: .topBarTrailing) { Button { handleAddExerciseTapped() } label: { Image(systemName: "plus") } }
                    ToolbarItem(placement: .topBarTrailing) { Button { showingAddEntry = true } label: { Image(systemName: "square.and.pencil") } }
                }
                .sheet(isPresented: $showingAdd) { AddExerciseView(palette: palette).themed(palette: palette, isDark: isDark) }
                .sheet(isPresented: $showingSettings) { SettingsView().themed(palette: ThemeKit.palette(settings), isDark: ThemeKit.isDark(settings)) }
                .sheet(isPresented: $showingSaved) { SavedMacrosView().themed(palette: palette, isDark: isDark) }
                .sheet(item: $showingLogFor) { ex in LogRepsView(exercise: ex, palette: palette).themed(palette: palette, isDark: isDark) }
                .sheet(item: $editingExercise) { ex in EditExerciseView(exercise: ex, palette: palette).themed(palette: palette, isDark: isDark) }
                .sheet(item: $editingGoal) { ex in GoalEditorView(exercise: ex, palette: palette).themed(palette: palette, isDark: isDark) }
                .sheet(item: $showingMacroFor) { ex in MacroPlannerView(exercise: ex, palette: palette).themed(palette: palette, isDark: isDark) }
                .sheet(item: $showingGraphFor) { ex in ProgressGraphView(exercise: ex, palette: palette).themed(palette: palette, isDark: isDark) }
                .sheet(isPresented: $showingUpgradeSheet) { UpgradeView() }
                .sheet(isPresented: $showingAddEntry) {
                    AddRepEntryView(palette: palette)
                        .themed(palette: palette, isDark: isDark)
                }
                .sheet(item: $showingAddEntryFor) { ex in
                    AddRepEntryView(palette: palette, selectedExerciseID: ex.id).themed(palette: palette, isDark: isDark)
                }
                .alert("Upgrade required", isPresented: $showingUpgradeAlert) {
                    Button("Not now", role: .cancel) {}
                    Button("Upgrade") { showingUpgradeSheet = true }
                } message: { Text("Free plan allows up to 3 goals. Upgrade to unlock more and StreakPaths.") }

                .alert("Delete Exercise?", isPresented: Binding(
                    get: { deletingExercise != nil },
                    set: { if !$0 { deletingExercise = nil } }
                )) {
                    Button("Delete", role: .destructive) {
                        if let ex = deletingExercise {
                            performDelete(ex)
                        }
                        deletingExercise = nil
                    }
                    Button("Cancel", role: .cancel) { deletingExercise = nil }
                } message: {
                    Text("This will remove \"\(deletingExercise?.name ?? "this exercise")\" and all of its logged reps.")
                }
        }
        .themed(palette: palette, isDark: isDark)
        .task { LocalReminderScheduler.rescheduleAll(using: context) }
        .onChange(of: exercises.count) {
            _ in LocalReminderScheduler.rescheduleAll(using: context)

//            print("Exercises count changed to \(exercises.count); rescheduled reminders")
        }
        .onAppear {
//            settings.hasFullUnlock = true
        }
        .onChange(of: scenePhase) { phase in // ⬅️ ADDED: Foreground check
            if phase == .active {
//                print("App became active; checking date")
                let today = Calendar.current.startOfDay(for: Date())
                if today != dayAnchor {
                    dayAnchor = today
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            // ⬅️ ADDED: Handle midnight rollover while app is open
            dayAnchor = Calendar.current.startOfDay(for: Date())
        }
    }
}

struct ExerciseRow: View {
    @Environment(\.modelContext) private var context
    let exercise: Exercise
    let palette: ThemePalette
    @State private var todayTotal: Int = 0

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(exercise.name).font(.headline)
                Text("Daily goal: \(exercise.dailyGoal)").font(.caption).foregroundStyle(.secondary)
                WeekdayStripe(scheduled: exercise.scheduledWeekdays, palette: palette)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                ProgressView(value: Double(todayTotal), total: Double(exercise.dailyGoal)).frame(width: 120)
                Text("\(todayTotal)/\(exercise.dailyGoal)").monospacedDigit()
            }
        }
        .task(id: exercise.id) { await refreshProgress() }
        .onReceive(NotificationCenter.default.publisher(for: .repEntryUpdated)) { note in
            if let id = note.object as? UUID, id == exercise.id { Task { await refreshProgress() } }
        }
        .listRowBackground(Color.clear)
    }

    @MainActor
    private func refreshProgress() async {
        do { todayTotal = try DataService.todaysProgress(for: exercise, context: context) } catch { todayTotal = 0 }
    }
}

struct WeekdayStripe: View {
    let scheduled: [Int]
    let palette: ThemePalette
    private let symbols: [String] = DateFormatter().veryShortWeekdaySymbols ?? ["S", "M", "T", "W", "T", "F", "S"]
    private let indices: [Int] = Array(0 ..< 7)
    var body: some View {
        HStack(spacing: 4) {
            ForEach(indices, id: \.self) { i in
                let on = scheduled.contains(i + 1)
                Text(symbols[i]).font(.caption2).fontWeight(on ? .semibold : .regular).foregroundStyle(on ? palette.onTint : palette.offTint)
            }
        }
    }
}
