//
//  AIPromptFeature.swift
//  cursor-toolbar
//

import AppKit
import Combine
import SwiftUI

// MARK: - AI prompt

final class AIPromptState: ObservableObject {
    @Published var text: String = ""
}

struct AIPromptSectionView: View {
    @ObservedObject var state: AIPromptState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $state.text)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Color.white)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 120, idealHeight: 140, maxHeight: 160)

                if state.text.isEmpty {
                    Text("Ask anything…")
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

            Button {
                copyToClipboard()
            } label: {
                HStack {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Copy prompt")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: ToolbarGlass.innerRadius, style: .continuous)
                        .fill(Color.white.opacity(0.16))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: ToolbarGlass.innerRadius, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .disabled(state.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .opacity(state.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)
        }
    }

    private func copyToClipboard() {
        let trimmed = state.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(trimmed, forType: .string)
    }
}
