//
//  CloudSyncService.swift
//  SteadyStreak
//
//  Created by Randall Ridley on 8/29/25.
//

import Foundation
import SwiftData

// MARK: - DTOs (decouple from SwiftData models)

struct ExerciseDTO: Codable {
    let id: UUID
    let name: String
    let dailyGoal: Int
    let scheduledWeekdays: [Int]
    let createdAt: Date
    let isArchived: Bool
}

struct MacroGoalDTO: Codable {
    let id: UUID
    let exerciseID: UUID
    let targetTotal: Int
    let completionDate: String // keeping as stored; backend can parse/normalize
}

struct RepEntryDTO: Codable {
    let id: UUID // ⬅️ CHANGED to UUID
    let exerciseID: UUID // ⬅️ CHANGED to UUID
    let date: Date
    let count: Int
}

struct ExportPayload: Codable {
    let userId: String // UUID string
    let generatedAt: Date
    let exercises: [ExerciseDTO]
    let macroGoals: [MacroGoalDTO]
    let repEntries: [RepEntryDTO]
}

enum CloudSyncError: Error, LocalizedError {
    case missingUserUUID
    case invalidURL
    case encodingFailed
    case server(String)
    case unknown

    var errorDescription: String? {
        switch self {
        case .missingUserUUID: return "Create an account first to get a user ID."
        case .invalidURL: return "Invalid sync endpoint."
        case .encodingFailed: return "Failed to encode payload."
        case .server(let msg): return "Server error: \(msg)"
        case .unknown: return "Unknown sync error."
        }
    }
}

enum CloudSyncService {
    /// Export SwiftData → JSON payload
    static func makeExportPayload(context: ModelContext, userUUID: String) throws -> ExportPayload {
        // Exercises
        let exercises: [Exercise] = try context.fetch(FetchDescriptor<Exercise>())
        let exerciseDTOs: [ExerciseDTO] = exercises.map { ex in
            ExerciseDTO(
                id: ex.id,
                name: ex.name,
                dailyGoal: ex.dailyGoal,
                scheduledWeekdays: ex.scheduledWeekdays,
                createdAt: ex.createdAt,
                isArchived: (ex as AnyObject).value(forKey: "isArchived") as? Bool ?? false // if you've added isArchived
            )
        }

        // MacroGoals
        let macroGoals: [MacroGoal] = (try? context.fetch(FetchDescriptor<MacroGoal>())) ?? []
        let macroDTOs: [MacroGoalDTO] = macroGoals.map { m in
            MacroGoalDTO(
                id: m.id,
                exerciseID: (m as AnyObject).value(forKey: "exerciseID") as? UUID ?? UUID(),
                targetTotal: (m.targetTotal as? Int) ?? (m.targetTotal ?? 0),
                completionDate: (m.completionDate as? String) ?? ""
            )
        }

        // Rep entries (your model: RepEntry { id: UUID, date: Date, currentTotal: Int, exercise: Exercise? })
        let repEntries: [RepEntry] = (try? context.fetch(FetchDescriptor<RepEntry>())) ?? []
        let repDTOs: [RepEntryDTO] = repEntries.compactMap { (r: RepEntry) -> RepEntryDTO? in
            guard let ex = r.exercise else { return nil }
            return RepEntryDTO(
                id: r.id, // ⬅️ Uses your UUID
                exerciseID: ex.id, // ⬅️ Uses Exercise UUID
                date: r.date,
                count: r.currentTotal
            )
        }

        return ExportPayload(
            userId: userUUID,
            generatedAt: Date(),
            exercises: exerciseDTOs,
            macroGoals: macroDTOs,
            repEntries: repDTOs
        )
    }

    /// POST the payload to your Node backend
    static func postExport(_ payload: ExportPayload, to endpoint: String) async throws {
        guard let url = URL(string: endpoint) else { throw CloudSyncError.invalidURL }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Optional: include user ID header too
        req.setValue(payload.userId, forHTTPHeaderField: "X-User-ID")

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        let body = try encoder.encode(payload)
        req.httpBody = body

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw CloudSyncError.unknown }
        guard (200 ..< 300).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? "Status \(http.statusCode)"
            throw CloudSyncError.server(msg)
        }
    }
}
