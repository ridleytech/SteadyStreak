//
//  App.swift
//  SteadyStreak
//
//  Created by Randall Ridley on 8/21/25.
//

import BackgroundTasks
import Sentry

import SwiftData
import SwiftUI
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        SentrySDK.start { options in
            options.dsn = "https://c36d9f8a0245edfb1bdefe14a04cf4f8@o427372.ingest.us.sentry.io/4509930054549504"
            options.debug = true // Enabled debug when first installing is always helpful

            // Adds IP for users.
            // For more information, visit: https://docs.sentry.io/platforms/apple/data-management/data-collected/
            options.sendDefaultPii = true

            // Set tracesSampleRate to 1.0 to capture 100% of transactions for performance monitoring.
            // We recommend adjusting this value in production.
            options.tracesSampleRate = 1.0

            // Configure profiling. Visit https://docs.sentry.io/platforms/apple/profiling/ to learn more.
            options.configureProfiling = {
                $0.sessionSampleRate = 1.0 // We recommend adjusting this value in production.
                $0.lifecycle = .trace
            }

            // Uncomment the following lines to add more data to your events
            // options.attachScreenshot = true // This adds a screenshot to the error events
            // options.attachViewHierarchy = true // This adds the view hierarchy to the error events

            // Enable experimental logging features
            options.experimental.enableLogs = true
        }
        // Remove the next line after confirming that your Sentry integration is working.
//        SentrySDK.capture(message: "This app uses Sentry! :)")

        UNUserNotificationCenter.current().delegate = self
        AppStyle.applyNavigationTitleSizing()
        BackgroundScheduler.register()
        requestNotificationAuthorization()
        BackgroundScheduler.scheduleNextCheck()
        do {
            let config = ModelConfiguration("SteadyStreak")
            let container = try ModelContainer(for: Exercise.self, RepEntry.self, AppSettings.self, MacroGoal.self, configurations: config)
            let context = ModelContext(container)
            LocalReminderScheduler.rescheduleAll(using: context)
        } catch { print("⚠️ initial reschedule error: \(error)") }

//        if #available(iOS 14.0, *) {
//            Task {
//                await testProtectedEndpoint()
//            }
//        }

        return true
    }

    func requestNotificationAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error { print("Notification auth error: \(error)") }
            print("Notifications granted: \(granted)")
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.badge, .sound, .banner, .list])
    }

    @available(iOS 14.0, *)
    func testProtectedEndpoint() async {
        do {
            // Point to your SAM local API
            // let base = URL(string: "http://127.0.0.1:3000")!

            let base = URL(string: "https://rv0am18e5a.execute-api.us-west-2.amazonaws.com/prod")!
            var cfg = AppAttestClient.Config(apiBaseURL: base)
            cfg.noncePath = "/nonce" // default
            cfg.registerPath = "/register" // default
            AppAttestClient.shared.configure(cfg)

            // Register if needed (generates key + attestation)
            try await AppAttestClient.shared.registerIfNeeded()

            // Prepare request body
            let bodyData = Data("{\"hello\":\"world\"}".utf8)

            // Get signed headers
            let headers = try await AppAttestClient.shared.signedHeaders(
                method: "POST",
                path: "/protected",
                body: bodyData
            )

            // Build HTTP request
            var req = URLRequest(url: base.appendingPathComponent("protected"))
            req.httpMethod = "POST"
            req.httpBody = bodyData
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")

            // Attach signed headers
            headers.forEach { key, value in
                req.setValue(value, forHTTPHeaderField: key)
            }

            // Send request
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse else {
                print("❌ No HTTP response")
                return
            }

            print("Status:", http.statusCode)

            if let str = String(data: data, encoding: .utf8) {
                print("Body:", str)
            }
        } catch {
            print("❌ App Attest test failed:", error)
        }
    }
}

@main
struct RepGoalApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    private let container: ModelContainer = {
        do {
            let config = ModelConfiguration("SteadyStreak")
            return try ModelContainer(for: Exercise.self, RepEntry.self, AppSettings.self, MacroGoal.self, configurations: config)
        } catch { fatalError("💥 Failed to create ModelContainer: \(error)") }
    }()

    var body: some Scene {
        WindowGroup { ContentView()
            .onAppear {}

        }.modelContainer(container)
    }
}
