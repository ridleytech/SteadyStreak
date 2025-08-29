//
//  SettingsView.swift
//  SteadyStreak
//
//  Created by Randall Ridley on 8/21/25.
//

import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var settingsArray: [AppSettings]
    @State private var showingArchived = false
    @State private var showingAccount = false
    @State private var isSyncing = false
    @State private var syncMessage: String? = nil

    private var settings: AppSettings {
        if let s = settingsArray.first { return s }
        let s = AppSettings(); context.insert(s); return s
    }

    private let hours = Array(0 ..< 24)
    private let columns: [GridItem] = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)

    private var modeBinding: Binding<Int> { Binding(get: { settings.modeRaw }, set: { settings.modeRaw = $0 }) }
    private var intervalBinding: Binding<Int> { Binding(get: { settings.intervalHours }, set: { settings.intervalHours = $0 }) }
    private var startHourBinding: Binding<Int> { Binding(get: { settings.startHour }, set: { settings.startHour = $0 }) }
    private var palette: ThemePalette { ThemeOption(rawValue: settings.themeRaw)?.palette ?? ThemeOption.system.palette }
    private var isDark: Bool { (ThemeOption(rawValue: settings.themeRaw) ?? .system).isDark }

    @ViewBuilder private var reminderModeSection: some View {
        Section {
            Picker("Mode", selection: modeBinding) {
                Text("Every X hours").tag(0)
                Text("Specific times").tag(1)
            }.pickerStyle(.segmented)
        } header: { AppStyle.header("Reminder Mode") }
    }

    @ViewBuilder private var intervalSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Stepper(value: intervalBinding, in: 1 ... 12) {
                    HStack { Text("Interval"); Spacer(); Text("Every \(settings.intervalHours) hr").monospacedDigit().foregroundStyle(.secondary) }
                }
                HStack {
                    Button("+1") { settings.intervalHours = min(12, settings.intervalHours + 1) }.buttonStyle(BorderedButtonStyle())
                    Button("+2") { settings.intervalHours = min(12, settings.intervalHours + 2) }.buttonStyle(BorderedButtonStyle())
                }
            }
            Picker("Start hour", selection: startHourBinding) {
                ForEach(hours, id: \.self) { h in Text(hourLabel(h)).tag(h) }
            }
        } header: { AppStyle.header("Every N hours") }
    }

    @ViewBuilder private var customTimesSection: some View {
        Section {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(hours, id: \.self) { h in
                    let isOn = settings.customHours.contains(h)
                    Button(action: { toggleHour(h) }) { Text(hourLabel(h)).frame(maxWidth: .infinity) }
                        .buttonStyle(BorderedButtonStyle())
                        .tint(isOn ? palette.onTint : palette.offTint)
                }
            }
            if settings.customHours.isEmpty {
                Text("Select at least one time.").font(.footnote).foregroundStyle(.secondary)
            }
        } header: { AppStyle.header("Notification times") }
    }

    @ViewBuilder private var applySection: some View {
        Section {
            Button {
                BackgroundScheduler.rescheduleAfterSettingsChange()
                LocalReminderScheduler.rescheduleAll(using: context)
            } label: {
                HStack { Spacer(); Text("Apply & Reschedule Reminders"); Spacer() }
            }
            .buttonStyle(ThemedProminentButtonStyle(palette: palette, enabled: true))
        } header: { AppStyle.header("Apply & Reschedule Reminders") }
    }

    @ViewBuilder private var themeSection: some View {
        Section {
            ForEach(ThemeOption.allCases) { opt in
                Button { settings.themeRaw = opt.rawValue

                    print("Theme changed to \(opt.name) (\(opt.rawValue))")

                    try? context.save()

                } label: {
                    HStack(alignment: .center, spacing: 12) {
                        Text(opt.name)
                        Spacer(minLength: 8)
                        SwatchRow(colors: opt.swatch)
                            .frame(height: 22)
                            .frame(maxHeight: .infinity, alignment: .center)
                        Group {
                            if settings.themeRaw == opt.rawValue {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(opt.palette.onTint)
                            } else { Image(systemName: "circle").opacity(0) }
                        }.frame(width: 22, alignment: .trailing)
                    }
                    .contentShape(Rectangle())
                }
                .tint((ThemeOption(rawValue: settings.themeRaw) ?? .system).palette.text)
                .listRowBackground(Color.clear)
            }
        } header: { AppStyle.header("Theme") }
    }

    @ViewBuilder private var archivedSection: some View {
        Section {
            Button {
                showingArchived = true
            } label: {
                Label("Archived Streaks", systemImage: "archivebox")
                    .font(.body.weight(.semibold))
            }
        }
//        .footer {
//            // keeps the button visually anchored at the bottom
//            EmptyView()
//        }
    }

    @ViewBuilder private var accountSection: some View {
        Section(header: Text("Cloud")) {
            Button {
                if (settings.userUUID ?? "").isEmpty {
                    showingAccount = true
                } else {
                    print("start sync")
//                    Task { await syncNow() }
                }
            } label: {
                Label("Sync to Cloud", systemImage: "icloud.and.arrow.up")
            }
            .disabled(isSyncing || (settings.userUUID ?? "").isEmpty)

            Button {
                showingAccount = true
            } label: {
                Label(settings.userUUID == nil ? "Create Account" : "Manage Account", systemImage: "person.badge.key")
            }

            if let last = settings.lastCloudSync {
                Text("Last sync: \(last.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                reminderModeSection
                if settings.mode == .interval { intervalSection } else { customTimesSection }
                applySection
                themeSection
                archivedSection
//                accountSection
            }
            .themed(palette: palette, isDark: isDark)
            .navigationTitle("Settings")
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Close") { dismiss() } } }
            .sheet(isPresented: $showingArchived) {
                ArchivedExercisesView()
                    // If you theme Settings children, apply your theming helper:
                    .themed(palette: ThemeKit.palette(settings), isDark: ThemeKit.isDark(settings))
            }
            .sheet(isPresented: $showingAccount) {
                CreateAccountView()
                    .themed(palette: ThemeKit.palette(settings), isDark: ThemeKit.isDark(settings))
            }
        }
    }

    private func toggleHour(_ h: Int) {
        var set = Set(settings.customHours)
        if set.contains(h) { set.remove(h) } else { set.insert(h) }
        settings.customHours = Array(set).sorted()
    }

    private func hourLabel(_ h: Int) -> String {
        let date = Calendar.current.date(from: DateComponents(hour: h)) ?? Date()
        let fmt = DateFormatter(); fmt.dateFormat = "h a"; fmt.locale = .current
        return fmt.string(from: date)
    }

    @MainActor
    private func syncNow() async {
        guard let uid = settings.userUUID, !uid.isEmpty else {
            showingAccount = true
            return
        }

        isSyncing = true
        defer { isSyncing = false }

        do {
            let payload = try CloudSyncService.makeExportPayload(context: context, userUUID: uid)

            // 🔧 Replace with your real API endpoint:
            let endpoint = "https://your-backend.example.com/api/sync"

            try await CloudSyncService.postExport(payload, to: endpoint)
            settings.lastCloudSync = Date()
            try? context.save()
            syncMessage = "Sync complete."
        } catch {
            syncMessage = error.localizedDescription
        }
    }
}

struct SwatchRow: View {
    let colors: [Color]
    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(colors.enumerated()), id: \.0) { _, c in
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(c)
                    .frame(width: 18, height: 18)
            }
        }
        .frame(height: 22)
        .padding(.vertical, 2)
    }
}
