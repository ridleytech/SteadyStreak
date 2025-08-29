//
//  CreateAccountView.swift
//  SteadyStreak
//
//  Created by Randall Ridley on 8/29/25.
//

import Foundation
import SwiftData
import SwiftUI

struct CreateAccountView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    // You already have AppSettings in SwiftData
    @Query private var settingsArray: [AppSettings]

    @State private var userUUID: String = ""
    @State private var errorText: String? = nil

    private var settings: AppSettings {
        if let s = settingsArray.first { return s }
        let s = AppSettings(); context.insert(s); return s
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Account")) {
                    HStack {
                        TextField("User ID (UUID)", text: $userUUID)
                            .textInputAutocapitalization(.never)
                            .disableAutocorrection(true)
                            .font(.system(.body, design: .monospaced))
                        Button("New") { userUUID = UUID().uuidString }
                    }
                    if let err = errorText {
                        Text(err).foregroundStyle(.red).font(.caption)
                    }
                }

                Section {
                    Button {
                        save()
                    } label: {
                        Label("Save Account", systemImage: "person.crop.circle.badge.checkmark")
                    }
                    .disabled(!isValidUUID(userUUID))
                }

                if let existing = settings.userUUID, !existing.isEmpty {
                    Section {
                        Button(role: .destructive) {
                            userUUID = ""
                            settings.userUUID = nil
                            try? context.save()
                        } label: {
                            Label("Remove Account", systemImage: "person.crop.circle.badge.xmark")
                        }
                    } footer: {
                        Text("Removing the account locally does not delete your cloud data.")
                    }
                }
            }
            .navigationTitle("Account")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
            .onAppear {
                userUUID = settings.userUUID ?? UUID().uuidString
            }
        }
    }

    private func isValidUUID(_ s: String) -> Bool { UUID(uuidString: s) != nil }

    private func save() {
        guard isValidUUID(userUUID) else {
            errorText = "Please enter a valid UUID."
            return
        }
        settings.userUUID = userUUID
        try? context.save()
        dismiss()
    }
}
