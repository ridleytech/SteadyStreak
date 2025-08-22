//
//  StreakPath.swift
//  SteadyStreak
//
//  Created by Randall Ridley on 8/21/25.
//

import DeviceCheck
import Foundation
import Network
import SwiftData
import SwiftUI

// Replace your existing FlexibleStringList with this:
struct FlexibleStringList: Codable {
    var items: [String] = []

    init(items: [String] = []) { self.items = items }

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let arr = try? c.decode([String].self) {
            items = arr
        } else if let str = try? c.decode(String.self) {
            // Accept a single string and split on bullets/newlines for flexibility
            let t = str.trimmingCharacters(in: .whitespacesAndNewlines)
            let split = t
                .replacingOccurrences(of: "•", with: "\n")
                .replacingOccurrences(of: " - ", with: "\n")
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            items = split.isEmpty ? [t] : split
        } else {
            items = []
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(items)
    }
}

struct FlexibleString: Codable {
    var string: String = ""
    init(_ s: String) { string = s }
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) { string = s }
        else if let i = try? c.decode(Int.self) { string = String(i) }
        else if let d = try? c.decode(Double.self) { string = (d.rounded() == d) ? String(Int(d)) : String(d) }
        else if let b = try? c.decode(Bool.self) { string = b ? "true" : "false" }
        else { string = "" }
    }
}

struct MacroPlan: Codable {
    let estimated_days: Int?
    let estimated_completion_date: String?
    let daily_recommendation: FlexibleString?
    let weekly_notes: FlexibleStringList?
    let assumptions: FlexibleStringList?
}

enum ChatGPTService {
    struct ErrorMsg: LocalizedError { let message: String; var errorDescription: String? { message } }

    static func estimatePlan(exerciseName: String, targetTotal: Int, currentMax: Int) async throws -> String {
        let api = Bundle.main.object(forInfoDictionaryKey: "APIBaseURL") as? String

        if let api {
            // var apiBase: String = "http://localhost:6000/macro"

            var apiBase = "\(api)/macro"

//            print("apiBase: \(apiBase)")

            guard let url = URL(string: apiBase) else { throw ErrorMsg(message: "Invalid API base URL") }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let body: [String: Any] = ["exerciseName": exerciseName, "currentMax": currentMax, "targetTotal": targetTotal]
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, 200 ..< 300 ~= http.statusCode else {
                let txt = String(data: data, encoding: .utf8) ?? ""
                throw ErrorMsg(message: "API error \((resp as? HTTPURLResponse)?.statusCode ?? -1): \(txt)")
            }
            return String(data: data, encoding: .utf8) ?? "{}"
        } else {
            return "" // Fallback if API base URL is not set
        }
    }

    @available(iOS 14.0, *)
    static func estimatePlanProtected(
        exerciseName: String,
        targetTotal: Int,
        currentMax: Int
    ) async throws -> String {
        // Same base URL lookup as estimatePlan()
        guard let api = Bundle.main.object(forInfoDictionaryKey: "APIBaseURL") as? String,
              let baseURL = URL(string: api)
        else {
            throw ErrorMsg(message: "Invalid API base URL")
        }

        // Configure App Attest client (safe to call repeatedly)
        var cfg = AppAttestClient.Config(apiBaseURL: baseURL)
        cfg.noncePath = "/nonce"
        cfg.registerPath = "/register"
        AppAttestClient.shared.configure(cfg)

        // Ensure we have a key registered
        try await AppAttestClient.shared.registerIfNeeded()

        // Build the SAME JSON body as estimatePlan
        let bodyDict: [String: Any] = [
            "exerciseName": exerciseName,
            "currentMax": currentMax,
            "targetTotal": targetTotal
        ]
        let bodyData = try JSONSerialization.data(withJSONObject: bodyDict, options: [])

        // Sign headers for POST /protected with this exact body
        let headers = try await AppAttestClient.shared.signedHeaders(
            method: "POST",
            path: "/protected",
            body: bodyData
        )

        // Create the request to .../protected
        var req = URLRequest(url: baseURL.appendingPathComponent("protected"))
        req.httpMethod = "POST"
        req.httpBody = bodyData
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        headers.forEach { k, v in req.setValue(v, forHTTPHeaderField: k) }

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, 200 ..< 300 ~= http.statusCode else {
            let txt = String(data: data, encoding: .utf8) ?? ""
            throw ErrorMsg(message: "API error \((resp as? HTTPURLResponse)?.statusCode ?? -1): \(txt)")
        }
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}

struct MacroPlannerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let exercise: Exercise
    let palette: ThemePalette
    @State private var targetTotal: Int = 100
    @State private var currentMax: Int = 10
    @State private var isLoading: Bool = false
    @State private var resultJSON: String = ""
    @State private var plan: MacroPlan? = nil
    @State private var parseError: String? = nil
    @State private var didSave: Bool = false
    @State private var showingUpgradeSheet = false
    @State private var showingUpgradeAlert = false
    @State private var showingNetConnectionAlert = false
    @State private var showingAttestAlert = false

    let api = Bundle.main.object(forInfoDictionaryKey: "APIBaseURL") as? String

    private var settings: AppSettings {
        (try? context.fetch(FetchDescriptor<AppSettings>()).first) ?? {
            let s = AppSettings()
            context.insert(s)
            return s
        }()
    }

    func hasInternetConnection() -> Bool {
        let monitor = NWPathMonitor()
        let queue = DispatchQueue(label: "NetworkMonitor")
        var status = false
        let semaphore = DispatchSemaphore(value: 0)

        monitor.pathUpdateHandler = { path in
            status = (path.status == .satisfied)
            semaphore.signal()
            monitor.cancel()
        }
        monitor.start(queue: queue)

        _ = semaphore.wait(timeout: .now() + 2) // wait up to 2 seconds
        return status
    }

    func createStreakPath() {
        guard hasInternetConnection() else {
            print("❌ No internet connection")
            showingNetConnectionAlert = true
            return
        }

        if DCAppAttestService.shared.isSupported {
            if !settings.hasFullUnlock { showingUpgradeAlert = true } else {
                Task { await runEstimate() }
            }
        } else {
            print("❌ App Attest not supported")

            showingAttestAlert = true
            // TODO: remove in production
            // Call the unprotected endpoint or add a “demo mode” header
//            return try await ChatGPTService.estimatePlan(
//                exerciseName: exerciseName, targetTotal: targetTotal, currentMax: currentMax
//            )
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack { Text("Name"); Spacer(); Text(exercise.name).foregroundStyle(.secondary) }
                        .padding(.vertical, 2)

                    HStack { Text("Daily goal reps"); Spacer(); Text("\(exercise.dailyGoal)").foregroundStyle(.secondary).monospacedDigit() }
                        .padding(.bottom, 6)

                    VStack(alignment: .leading, spacing: 10) {
                        Stepper(value: $targetTotal, in: 1 ... 100000, step: 5) {
                            HStack { Text("🎯 Target reps goal"); Spacer(); Text("\(targetTotal)").foregroundStyle(.secondary).monospacedDigit() }
                        }
                        HStack(spacing: 10) {
                            Button("+5") { targetTotal = min(100000, targetTotal + 5) }.buttonStyle(BorderedButtonStyle())
                            Button("+10") { targetTotal = min(100000, targetTotal + 10) }.buttonStyle(BorderedButtonStyle())
                        }
                    }
                    .padding(.vertical, 6)

                    Button {
                        createStreakPath()

                    } label: {
                        HStack(spacing: 8) {
                            if isLoading { ProgressView() }
                            Text(isLoading ? "Creating StreakPath..." : "Create StreakPath")
                        }
                    }
                    .buttonStyle(ThemedProminentButtonStyle(palette: palette))
                    .padding(.top, 8)
                    .padding(.bottom, 14)
                } header: { AppStyle.header("📌 Exercise") }

                if let p = plan {
                    Section {
                        if let days = p.estimated_days {
                            HStack { Text("📅 Estimated days"); Spacer(); Text("\(days)").monospacedDigit() }
                        }
                        if let date = p.estimated_completion_date {
                            HStack { Text("🗓️ Completion date"); Spacer(); Text(date).foregroundStyle(.secondary) }
                        }
                        if let daily = p.daily_recommendation?.string, !daily.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("✅ Daily recommendation")
                                Text(daily).foregroundStyle(.secondary)
                            }
                            .padding(.top, 2)
                        }
                    } header: { AppStyle.header("🧭 Summary") }

                    if let weekly = p.weekly_notes?.items, !weekly.isEmpty {
                        Section {
                            ForEach(weekly.indices, id: \.self) { i in Text(weekly[i]) }
                        } header: { AppStyle.header("📒 Weekly notes") }
                    }
                    if let assumptions = p.assumptions?.items, !assumptions.isEmpty {
                        Section {
                            ForEach(assumptions.indices, id: \.self) { i in Text(assumptions[i]) }
                        } header: { AppStyle.header("⚙️ Assumptions") }
                    }

                    Section {
                        Button { savePlan(p) } label: {
                            Label(didSave ? "Saved" : "Save Plan", systemImage: didSave ? "checkmark.seal.fill" : "square.and.arrow.down")
                        }
                        .buttonStyle(ThemedProminentButtonStyle(palette: palette))
                        .disabled(didSave)
                        .padding(.top, 4)
                        .padding(.bottom, 10)
                    }
                }

//                if let parseError {
//                    Section {
//                        Text(parseError).foregroundStyle(.secondary).font(.footnote)
//                    } header: { AppStyle.header("Parse error") }
//                }
//                if !resultJSON.isEmpty {
//                    Section {
//                        Text(resultJSON).font(.system(.footnote, design: .monospaced)).textSelection(.enabled).lineLimit(10)
//                    } header: { AppStyle.header("Raw (JSON)") }
//                }
            }
            .listSectionSpacing(20)
            .navigationTitle("StreakPath")
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Close") { dismiss() } } }
            .sheet(isPresented: $showingUpgradeSheet) { UpgradeView() }
            .alert("Upgrade required", isPresented: $showingUpgradeAlert) {
                Button("Not now", role: .cancel) {}
                Button("Upgrade") { showingUpgradeSheet = true }
            } message: { Text("Upgrade to create StreakPaths.") }
            .alert("Error processing request", isPresented: $showingNetConnectionAlert) {
                Button("OK", role: .cancel) {}
            } message: { Text("Please check your internet connection.") }
            .alert("Feature not supported on this device", isPresented: $showingAttestAlert) {
                Button("OK", role: .cancel) {}
            } message: { Text("Please make sure you are using a physical iOS device with iOS version 14 or greater.") }
        }
    }

    private func runEstimate() async {
        isLoading = true; defer { isLoading = false }
        parseError = nil; didSave = false; plan = nil
        do {
            let jsonString = try await ChatGPTService.estimatePlanProtected(exerciseName: exercise.name, targetTotal: targetTotal, currentMax: exercise.dailyGoal)
            resultJSON = jsonString

            print("Received StreakPath JSON: \(jsonString)")

            if let data = jsonString.data(using: .utf8) {
                do { plan = try JSONDecoder().decode(MacroPlan.self, from: data) } catch { parseError = "Could not decode response as MacroPlan. Showing raw JSON." }
            }
        } catch { resultJSON = "{\"error\":\"\(error.localizedDescription)\"}"

            print("Error estimating plan: \(error.localizedDescription)")
        }
    }

    private func savePlan(_ p: MacroPlan) {
        let mg = MacroGoal(
            exerciseID: exercise.id,
            exerciseName: exercise.name,
            targetTotal: targetTotal,
            currentMax: currentMax,
            lastResultJSON: resultJSON,
            estimatedDays: p.estimated_days,
            completionDate: p.estimated_completion_date,
            dailyRecommendation: p.daily_recommendation?.string,
            weeklyNotes: p.weekly_notes?.items,
            assumptions: p.assumptions?.items
        )
        context.insert(mg)
        try? context.save()
        didSave = true
    }
}

struct SavedMacrosView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\MacroGoal.createdAt, order: .reverse)]) private var goals: [MacroGoal]
    var body: some View {
        NavigationStack {
            content
                .navigationTitle("StreakPaths")
                .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Close") { dismiss() } } }
        }
    }

    @ViewBuilder private var content: some View {
        if goals.isEmpty {
            ContentUnavailableView("No StreakPaths", systemImage: "bookmark", description: Text("Create a StreakPath from an exercise, then save it."))
        } else {
            List {
                ForEach(goals) { g in
                    NavigationLink(destination: MacroDetailView(goal: g)) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(g.exerciseName).font(.headline)
                            HStack {
                                if let d = g.completionDate { Text("Target: \(d)") }
                                if let days = g.estimatedDays { Text("• \(days) days") }
                            }.font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { idx in for i in idx { if let ctx = goals[i].modelContext { ctx.delete(goals[i]); try? ctx.save() } } }
            }.listStyle(.plain)
        }
    }
}

struct MacroDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let goal: MacroGoal
    var body: some View {
        NavigationStack {
            List {
                Section {
                    if let days = goal.estimatedDays {
                        HStack { Text("Estimated days"); Spacer(); Text("\(days)") }
                    }
                    if let date = goal.completionDate {
                        HStack { Text("Completion date"); Spacer(); Text(date) }
                    }
                    if let rec = goal.dailyRecommendation {
                        VStack(alignment: .leading) {
                            Text("Daily recommendation")
                            Text(rec).foregroundStyle(.secondary)
                        }
                    }
                } header: { AppStyle.header("Summary") }
                if let weekly = goal.weeklyNotes, !weekly.isEmpty {
                    Section { ForEach(weekly, id: \.self) { Text($0) } } header: { AppStyle.header("Weekly notes") }
                }
                if let assumptions = goal.assumptions, !assumptions.isEmpty {
                    Section { ForEach(assumptions, id: \.self) { Text($0) } } header: { AppStyle.header("Assumptions") }
                }
//                Section { Text(goal.lastResultJSON).font(.system(.footnote, design: .monospaced)) } header: { AppStyle.header("Raw JSON") }
            }
            .navigationTitle(goal.exerciseName)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Close") { dismiss() } } }
        }
    }
}
