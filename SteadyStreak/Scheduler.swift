//
//  Scheduler.swift
//  SteadyStreak
//
//  Created by Randall Ridley on 8/21/25.
//

import BackgroundTasks
import Foundation
import SwiftData
import UserNotifications

enum BackgroundScheduler {
    static let taskIdentifier = "com.example.repgoal.check"
    static let defaultSlots: [Int] = [7, 10, 13, 16, 19, 22]

    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
            guard let task = task as? BGAppRefreshTask else { return }
            handle(task: task)
        }
    }

    static func scheduleNextCheck(now: Date = Date()) {
        let next = nextCheckDate(after: now)
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = next
        do { try BGTaskScheduler.shared.submit(request) } catch { print("⚠️ BG submit error: \(error)") }
    }

    static func nextCheckDate(after now: Date) -> Date {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: now)
        let slots = loadSlots()
        for h in slots {
            var dc = DateComponents()
            dc.year = comps.year; dc.month = comps.month; dc.day = comps.day
            dc.hour = h; dc.minute = 0; dc.second = 0
            if let d = cal.date(from: dc), d > now { return d }
        }
        let tomorrow = cal.date(byAdding: .day, value: 1, to: now)!
        var dc = DateComponents()
        let t = cal.dateComponents([.year, .month, .day], from: tomorrow)
        dc.year = t.year; dc.month = t.month; dc.day = t.day
        dc.hour = (loadSlots().first ?? 7); dc.minute = 0; dc.second = 0
        return cal.date(from: dc)!
    }

    static func rescheduleAfterSettingsChange() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskIdentifier)
        scheduleNextCheck()
    }

    static func loadSlots() -> [Int] {
        do {
            let config = ModelConfiguration("SteadyStreak")
            let container = try ModelContainer(for: Exercise.self, RepEntry.self, AppSettings.self, MacroGoal.self, configurations: config)
            let context = ModelContext(container)
            if let s = try context.fetch(FetchDescriptor<AppSettings>()).first {
                return computeSlots(from: s)
            }
        } catch { print("⚠️ loadSlots error: \(error)") }
        return defaultSlots
    }

    static func computeSlots(from s: AppSettings) -> [Int] {
        switch s.mode {
        case .interval:
            let step = max(1, min(12, s.intervalHours))
            var hours: [Int] = []
            var h = max(0, min(23, s.startHour))
            while h < 24 { hours.append(h); h += step }
            return hours
        case .custom:
            let set = Set(s.customHours.filter { (0 ... 23).contains($0) })
            return Array(set).sorted()
        }
    }

    static func handle(task: BGAppRefreshTask) {
        scheduleNextCheck()
        let queue = OperationQueue(); queue.maxConcurrentOperationCount = 1
        task.expirationHandler = { queue.cancelAllOperations() }
        queue.addOperation {
            do {
                let config = ModelConfiguration("SteadyStreak")
                let container = try ModelContainer(for: Exercise.self, RepEntry.self, AppSettings.self, MacroGoal.self, configurations: config)
                let context = ModelContext(container)
                try sendNotificationsIfNeeded(using: context)
                task.setTaskCompleted(success: true)
            } catch { print("❌ BG task failed: \(error)"); task.setTaskCompleted(success: false) }
        }
    }

    static func sendNotificationsIfNeeded(using context: ModelContext) throws {
        LocalReminderScheduler.rescheduleAll(using: context)
    }
}

enum LocalReminderScheduler {
    private static let idPrefix = "steady.reminder."

    private static func id(for exercise: Exercise, weekday: Int) -> String {
        "\(idPrefix)\(exercise.id.uuidString).w\(weekday)"
    }

    static func rescheduleAll(using context: ModelContext) {
        let center = UNUserNotificationCenter.current()

        center.getPendingNotificationRequests { requests in
            let ids = requests.map(\.identifier).filter { $0.hasPrefix(idPrefix) }
            if !ids.isEmpty { center.removePendingNotificationRequests(withIdentifiers: ids) }

            Task { @MainActor in
                let fetch = FetchDescriptor<Exercise>() // fetch all
                let all = (try? context.fetch(fetch)) ?? []
                let active = all.filter { !$0.isArchived } // typed filter

                for ex in active {
                    scheduleReminders(for: ex, center: center)
                }
            }
        }
    }

    static func cancelAll(for exercise: Exercise) {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            let prefix = "\(idPrefix)\(exercise.id.uuidString)."
            let ids = requests.map(\.identifier).filter { $0.hasPrefix(prefix) }
            if !ids.isEmpty { center.removePendingNotificationRequests(withIdentifiers: ids) }
        }
    }

    private static func scheduleReminders(for exercise: Exercise, center: UNUserNotificationCenter) {
        guard !exercise.isArchived else { return } // typed check

        // Example scheduling (adjust time/content as you already had)
        let hour = 9, minute = 0
        for weekday in exercise.scheduledWeekdays {
            var comps = DateComponents()
            comps.weekday = weekday
            comps.hour = hour
            comps.minute = minute

            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)

            let content = UNMutableNotificationContent()
            content.title = "SteadyStreak"
            content.body = "Time to work on \(exercise.name)."
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: id(for: exercise, weekday: weekday),
                content: content,
                trigger: trigger
            )
            center.add(request)
        }
    }
}
