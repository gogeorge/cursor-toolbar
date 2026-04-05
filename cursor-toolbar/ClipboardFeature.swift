//
//  ClipboardFeature.swift
//  cursor-toolbar
//

import AppKit
import Combine
import SwiftUI

// MARK: - Clipboard Manager

class ClipboardManager: ObservableObject {
    @Published var recentTexts: [String] = []
    private var lastChangeCount: Int = NSPasteboard.general.changeCount
    private var timer: Timer?

    private let saveKey = "clipboard_history"
    private let maxHistoryCount = 5

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
            if recentTexts.count > maxHistoryCount { recentTexts = Array(recentTexts.prefix(maxHistoryCount)) }
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
        let loaded = UserDefaults.standard.stringArray(forKey: saveKey) ?? []
        recentTexts = Array(loaded.prefix(maxHistoryCount))
    }

    deinit { timer?.invalidate() }
}

// MARK: - Clipboard section

struct ClipboardSectionView: View {
    @ObservedObject var clipboard: ClipboardManager
    var onCopyItem: () -> Void

    var body: some View {
        Group {
            if clipboard.recentTexts.isEmpty {
                Text("No clipboard history yet")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.55))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(clipboard.recentTexts.enumerated()), id: \.offset) { _, text in
                        Button {
                            clipboard.copy(text)
                            onCopyItem()
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "doc.on.clipboard")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(Color.white.opacity(0.55))
                                Text(text)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                    .font(.system(size: 13, weight: .regular))
                                    .foregroundStyle(Color.white.opacity(0.95))
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if text != clipboard.recentTexts.last {
                            Divider()
                                .overlay(Color.white.opacity(0.12))
                                .padding(.leading, 14)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 2)
        .background(
            RoundedRectangle(cornerRadius: ToolbarGlass.innerRadius, style: .continuous)
                .fill(Color.black.opacity(0.2))
        )
        .overlay(
            RoundedRectangle(cornerRadius: ToolbarGlass.innerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
        )
    }
}
