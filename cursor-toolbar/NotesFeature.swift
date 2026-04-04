//
//  NotesFeature.swift
//  cursor-toolbar
//

import Combine
import SwiftUI

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

// MARK: - Notes section (glass-styled editor)

struct NotesSectionView: View {
    @ObservedObject var notes: NotesManager

    var body: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $notes.text)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Color.white)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 108, idealHeight: 120, maxHeight: 140)

            if notes.text.isEmpty {
                Text("Write something…")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.42))
                    .padding(.top, 6)
                    .padding(.leading, 5)
                    .allowsHitTesting(false)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: ToolbarGlass.innerRadius, style: .continuous)
                .fill(Color.black.opacity(0.22))
        )
        .overlay(
            RoundedRectangle(cornerRadius: ToolbarGlass.innerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
        )
    }
}
