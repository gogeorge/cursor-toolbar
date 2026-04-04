//
//  ClipboardFeature.swift
//  cursor-toolbar
//
//  Created by George Valtas on 04/04/2026.
//

import SwiftUI
import AppKit
import Combine

// MARK: - Clipboard Manager
class ClipboardManager: ObservableObject {
    @Published var recentTexts: [String] = []
    private var lastChangeCount: Int = NSPasteboard.general.changeCount
    private var timer: Timer?

    private let saveKey = "clipboard_history"

    init() {
        load()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkClipboard()
        }
    }

    private func checkClipboard() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChangeCount else { return }
        lastChangeCount = pb.changeCount

        if let str = pb.string(forType: .string), !str.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            recentTexts.removeAll { $0 == str }
            recentTexts.insert(str, at: 0)
            if recentTexts.count > 3 { recentTexts = Array(recentTexts.prefix(3)) }
            save()
        }
    }

    func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        lastChangeCount = NSPasteboard.general.changeCount
    }

    private func save() {
        UserDefaults.standard.set(recentTexts, forKey: saveKey)
    }

    private func load() {
        recentTexts = UserDefaults.standard.stringArray(forKey: saveKey) ?? []
    }

    deinit { timer?.invalidate() }
}

// MARK: - Clipboard Dropdown View
struct ClipboardDropdownView: View {
    @ObservedObject var clipboard: ClipboardManager
    @Binding var isShowing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider()
            if clipboard.recentTexts.isEmpty {
                Text("No clipboard history yet")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
            } else {
                ForEach(Array(clipboard.recentTexts.enumerated()), id: \.offset) { _, text in
                    Button {
                        clipboard.copy(text)
                        isShowing = false
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "doc.on.clipboard")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text(text)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .font(.caption)
                                .foregroundColor(.primary)
                            Spacer()
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(Color.primary.opacity(0.001)) // ensures hit area
                    
                    if text != clipboard.recentTexts.last {
                        Divider().padding(.leading, 10)
                    }
                }
            }
        }
        .frame(width: 220)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}
