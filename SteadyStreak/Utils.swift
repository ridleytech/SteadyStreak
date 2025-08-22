//
//  Utils.swift
//  SteadyStreak
//
//  Created by Randall Ridley on 8/21/25.
//

import DeviceCheck
import Foundation
import SwiftUI
import UIKit

extension Color {
    init(hex: String) {
        let scanner = Scanner(string: hex)
        _ = scanner.scanString("#") // skip the # if it's there

        var rgb: UInt64 = 0
        scanner.scanHexInt64(&rgb)

        let r = Double((rgb >> 16) & 0xFF) / 255
        let g = Double((rgb >> 8) & 0xFF) / 255
        let b = Double(rgb & 0xFF) / 255

        self.init(red: r, green: g, blue: b)
    }
}

extension String {
    func trim() -> String {
        return self.trimmingCharacters(in: .whitespaces)
    }
}

enum Utils {
    static func iconForExerciseType(_ type: String) -> Image {
        switch type {
        case "Basic":
            return Image(systemName: "dumbbell.fill")

        case "Conditioning":
            return Image(systemName: "figure.run")
        default:
            return Image(systemName: "questionmark.circle.fill")
        }
    }

    static func iconForExerciseType2(_ type: String) -> Text {
        switch type {
        case "Basic":
            return Text("B")
        case "Conditioning":
            return Text("C")
        case "Supporting":
            return Text("S")
        case "Supporting":
            return Text("S")
        case "Plyometric":
            return Text("P")
        case "Sprint":
            return Text("SP")
        default:
            return Text("A")
        }
    }

    static func roundToNearestMultipleOfFive(_ number: Double) -> Double {
        let val = 5 * round(Double(number) / 5.0)

        return val
    }
}

extension UIApplication {
    func endEditing() {
        sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

func logDeviceInfo() {
    #if targetEnvironment(simulator)
    print("Running on Simulator")
    #else
    print("Running on Device")
    #endif
    print("System: \(UIDevice.current.systemName) \(UIDevice.current.systemVersion)")
    print("Model: \(UIDevice.current.model)")
    print("AppAttest supported: \(DCAppAttestService.shared.isSupported)")
}
