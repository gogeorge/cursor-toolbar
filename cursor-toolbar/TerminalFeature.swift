//
//  TerminalFeature.swift
//  cursor-toolbar
//
//  Console + free-text REPL for dev/terminal mode. Renders the shared
//  TerminalEngine's output and lets the user type arbitrary shell commands.
//

import AppKit
import SwiftUI

struct TerminalSectionView: View {
    @ObservedObject var engine: TerminalEngine
    @State private var input: String = ""
    @State private var historyIndex: Int? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            consoleView
            inputRow
        }
    }

    // MARK: - Console

    private var consoleView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if engine.lines.isEmpty {
                        Text("Output appears here. Type a command below or tap a command tile.")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(Color.white.opacity(0.4))
                            .padding(.vertical, 2)
                    }
                    ForEach(engine.lines) { line in
                        Text(displayText(for: line))
                            .font(.system(size: 11, weight: line.kind == .command ? .semibold : .regular, design: .monospaced))
                            .foregroundStyle(color(for: line.kind))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .id(line.id)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(10)
            }
            .frame(minHeight: 150, maxHeight: 220)
            .background(
                RoundedRectangle(cornerRadius: ToolbarGlass.innerRadius, style: .continuous)
                    .fill(Color.black.opacity(0.32))
            )
            .overlay(
                RoundedRectangle(cornerRadius: ToolbarGlass.innerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
            )
            .onChange(of: engine.lines.count) { _, _ in
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
    }

    private func displayText(for line: TerminalEngine.OutputLine) -> String {
        line.kind == .command ? "$ \(line.text)" : line.text
    }

    private func color(for kind: TerminalEngine.LineKind) -> Color {
        switch kind {
        case .command: return Color(red: 0.55, green: 0.85, blue: 1.0)
        case .stdout: return Color.white.opacity(0.85)
        case .stderr: return Color(red: 1.0, green: 0.6, blue: 0.55)
        case .info: return Color.white.opacity(0.5)
        }
    }

    // MARK: - Input

    private var inputRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.55))

            TextField("Type a command…", text: $input)
                .textFieldStyle(.plain)
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundStyle(Color.white)
                .onSubmit(runInput)
                .onKeyPress(.upArrow) { recallHistory(offset: -1); return .handled }
                .onKeyPress(.downArrow) { recallHistory(offset: 1); return .handled }

            if engine.isRunning {
                Button(action: engine.stop) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.white)
                        .frame(width: 30, height: 26)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.red.opacity(0.55)))
                }
                .buttonStyle(.plain)
                .help("Stop running command")
            } else {
                Button(action: runInput) {
                    Image(systemName: "return")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.white)
                        .frame(width: 30, height: 26)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.16)))
                }
                .buttonStyle(.plain)
                .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            Button(action: engine.clear) {
                Image(systemName: "trash")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.6))
                    .frame(width: 30, height: 26)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.08)))
            }
            .buttonStyle(.plain)
            .help("Clear console")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: ToolbarGlass.innerRadius, style: .continuous)
                .fill(Color.black.opacity(0.22))
        )
        .overlay(
            RoundedRectangle(cornerRadius: ToolbarGlass.innerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
        )
    }

    private func runInput() {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !engine.isRunning else { return }
        engine.run(trimmed, recordHistory: true)
        input = ""
        historyIndex = nil
    }

    private func recallHistory(offset: Int) {
        guard !engine.history.isEmpty else { return }
        let newIndex: Int
        if let current = historyIndex {
            newIndex = current + offset
        } else {
            newIndex = offset < 0 ? engine.history.count - 1 : engine.history.count
        }
        if newIndex < 0 {
            historyIndex = 0
        } else if newIndex >= engine.history.count {
            historyIndex = nil
            input = ""
        } else {
            historyIndex = newIndex
            input = engine.history[newIndex]
        }
    }
}
