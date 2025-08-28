//
//  RepEntryView.swift
//  SteadyStreak
//
//  Created by Randall Ridley on 8/26/25.
//

import Foundation
import SwiftData
import SwiftUI

struct AddRepEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let palette: ThemePalette

    // Load saved exercises
    @Query(sort: [SortDescriptor(\Exercise.createdAt, order: .forward)])
    private var exercises: [Exercise]

//    let selectedExerciseID: UUID?
    @State var selectedExerciseID: UUID?

    // UI state
//    @State private var selectedExerciseID: UUID?
    @State private var entryDate: Date = .init()
    @State private var repsText: String = ""
    @State private var showingEntryAlert = false

    @State private var repTotal: Int = 0
    @State private var exerciseName: String = ""
    @State private var lastRepsValue: Int = 0

    // Simple validation
    private var selectedExercise: Exercise? {
        guard let id = selectedExerciseID else { return nil }
        return exercises.first { $0.id == id }
    }

    private var repsValue: Int? {
        Int(repsText.trimmingCharacters(in: .whitespaces))
    }

    private var canSave: Bool {
        selectedExercise != nil && (repsValue ?? 0) > 0
    }

    func formatDate(date: Date) -> String {
        let today = date
        let formatter1 = DateFormatter()
        formatter1.dateStyle = .short
        print(formatter1.string(from: today))

        return formatter1.string(from: today)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Exercise")) {
                    if exercises.isEmpty {
                        ContentUnavailableView("No Exercises",
                                               systemImage: "figure.strengthtraining.traditional",
                                               description: Text("Add an exercise first, then log reps."))
                    } else {
                        Picker("Choose Exercise", selection: $selectedExerciseID) {
                            ForEach(exercises) { ex in
                                Text(ex.name).tag(ex.id as UUID?)
                            }
                        }
                    }
                }

                Section(header: Text("Date")) {
                    DatePicker("When", selection: $entryDate, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .labelsHidden()
                }

                Section(header: Text("Reps")) {
                    HStack {
                        TextField("e.g. 100", text: $repsText)
                            .keyboardType(.numberPad)
                            .textInputAutocapitalization(.never)
                            .disableAutocorrection(true)
                        Spacer()
                        Text("reps").foregroundStyle(.secondary)
                    }
                }

                Section {
                    Button {
                        if let selectedExercise {
                            exerciseName = selectedExercise.name
                            save()
                        }

                    } label: {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                            Text("Save Entry")
                        }
                    }
                    .disabled(!canSave)
                    .buttonStyle(ThemedProminentButtonStyle(palette: palette, enabled: canSave))
                    .padding(.top, 4)
                    .padding(.bottom, 10)
                }
            }
            .navigationTitle("Add Rep Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .alert("\(exerciseName) entry saved", isPresented: $showingEntryAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("\(lastRepsValue) reps saved for date \(formatDate(date: entryDate)).")
            }
            .onAppear {
                // Preselect first exercise if none chosen
                if selectedExerciseID == nil {
                    selectedExerciseID = exercises.first?.id

                    print("Default selected exercise ID: \(selectedExerciseID!)")

                } else {
                    print("Selected exercise ID: \(selectedExerciseID!)")
                }
            }
        }
    }

    // MARK: - Save

    @MainActor
    private func save() {
        guard let ex = selectedExercise, let reps = repsValue, reps > 0 else { return }

        // Normalize to start-of-day so your daily aggregations line up
        let day = Calendar.current.startOfDay(for: entryDate)

        // ======= CHOOSE YOUR MODEL VARIANT & UNCOMMENT IT =======
        // Variant A: RepEntry(date: Date, count: Int, exercise: Exercise)
        /*
         let entry = RepEntry(date: day, count: reps, exercise: ex)
         context.insert(entry)
         */

        let entry = RepEntry(currentTotal: reps, date: entryDate, exercise: ex)
        context.insert(entry)

        // If your type/initializer differs, set properties manually:
        /*
         var entry = RepEntry()
         entry.date = day
         entry.count = reps
         entry.exercise = ex
         context.insert(entry)
         */

        do {
            try context.save()
            // Let rows/graphs know this exercise’s entries changed
            NotificationCenter.default.post(name: .repEntryUpdated, object: ex.id)
            lastRepsValue = reps
            repsText = ""
            showingEntryAlert = true
//            dismiss()
        } catch {
            // You can present an alert if you like
            print("❌ Failed to save rep entry: \(error)")
        }
    }
}
