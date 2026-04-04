//
//  NotesFeature.swift
//  cursor-toolbar
//
//  Created by George Valtas on 04/04/2026.
//

import SwiftUI
import Combine

// MARK: - Notes Manager
class NotesManager: ObservableObject {
    @Published var text: String = "" {
        didSet { save() }
    }

    private let saveKey = "toolbar_notes"

    init() {
        text = UserDefaults.standard.string(forKey: saveKey) ?? ""
    }

    private func save() {
        UserDefaults.standard.set(text, forKey: saveKey)
    }
}

// MARK: - Notes Dropdown View
struct NotesDropdownView: View {
    @ObservedObject var notes: NotesManager

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "note.text")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("Quick Notes")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                }

                TextEditor(text: $notes.text)
                    .font(.system(size: 12))
                    .frame(width: 200, height: 120)
                    .scrollContentBackground(.hidden)
                    .background(Color.primary.opacity(0.05))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                    )
                    .overlay(
                        Group {
                            if notes.text.isEmpty {
                                Text("Write something...")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                    .padding(.leading, 5)
                                    .padding(.top, 8)
                                    .allowsHitTesting(false)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            }
                        }
                    )
            }
            .padding(10)
        }
        .frame(width: 220)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}
