//
//  TerminalEngine.swift
//  cursor-toolbar
//
//  Shared shell runner for dev/terminal mode. Runs commands through a login
//  zsh so user PATH entries (Homebrew, miniforge, etc.) resolve, and streams
//  stdout/stderr into an observable line buffer that the console renders.
//

import Combine
import Foundation

final class TerminalEngine: ObservableObject {
    enum LineKind: Equatable {
        case command
        case stdout
        case stderr
        case info
    }

    struct OutputLine: Identifiable, Equatable {
        let id = UUID()
        let text: String
        let kind: LineKind
    }

    @Published private(set) var lines: [OutputLine] = []
    @Published private(set) var isRunning = false

    /// Most recent commands typed into the REPL (newest last), for up-arrow style recall.
    @Published private(set) var history: [String] = []

    private var currentProcess: Process?
    private var stdoutBuffer = ""
    private var stderrBuffer = ""

    private let maxLines = 1200

    // MARK: - Public API

    func run(_ command: String, echo: Bool = true, recordHistory: Bool = false) {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !isRunning else {
            append("A command is already running — stop it first.", kind: .info)
            return
        }

        if recordHistory {
            history.removeAll { $0 == trimmed }
            history.append(trimmed)
            if history.count > 100 { history.removeFirst(history.count - 100) }
        }

        if echo { append(trimmed, kind: .command) }
        isRunning = true
        stdoutBuffer = ""
        stderrBuffer = ""

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        // -l: login shell (loads PATH); -c: run the command string.
        process.arguments = ["-l", "-c", trimmed]

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        outPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async { self?.ingest(chunk, stream: .stdout) }
        }
        errPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async { self?.ingest(chunk, stream: .stderr) }
        }

        process.terminationHandler = { [weak self] proc in
            outPipe.fileHandleForReading.readabilityHandler = nil
            errPipe.fileHandleForReading.readabilityHandler = nil
            DispatchQueue.main.async {
                guard let self else { return }
                self.flushBuffers()
                self.isRunning = false
                self.currentProcess = nil
                let code = proc.terminationStatus
                self.append(code == 0 ? "✔ done" : "✘ exited with code \(code)", kind: .info)
            }
        }

        currentProcess = process
        do {
            try process.run()
        } catch {
            isRunning = false
            currentProcess = nil
            append("Failed to start: \(error.localizedDescription)", kind: .stderr)
        }
    }

    func stop() {
        guard isRunning else { return }
        currentProcess?.terminate()
        append("Stopping…", kind: .info)
    }

    func clear() {
        lines.removeAll()
    }

    // MARK: - Output plumbing

    private enum Stream { case stdout, stderr }

    /// Assembles streamed chunks into whole lines. Carriage returns (progress
    /// bars from yt-dlp/rclone) collapse to the final segment so the console
    /// shows the latest progress rather than thousands of partial lines.
    private func ingest(_ chunk: String, stream: Stream) {
        let kind: LineKind = (stream == .stdout) ? .stdout : .stderr
        if stream == .stdout { stdoutBuffer += chunk } else { stderrBuffer += chunk }

        while true {
            let buffer = (stream == .stdout) ? stdoutBuffer : stderrBuffer
            guard let nl = buffer.firstIndex(of: "\n") else { break }
            var line = String(buffer[..<nl])
            let rest = String(buffer[buffer.index(after: nl)...])
            if stream == .stdout { stdoutBuffer = rest } else { stderrBuffer = rest }

            if let lastCR = line.lastIndex(of: "\r") {
                line = String(line[line.index(after: lastCR)...])
            }
            append(line, kind: kind)
        }
    }

    private func flushBuffers() {
        if !stdoutBuffer.isEmpty {
            append(collapseCarriageReturns(stdoutBuffer), kind: .stdout)
            stdoutBuffer = ""
        }
        if !stderrBuffer.isEmpty {
            append(collapseCarriageReturns(stderrBuffer), kind: .stderr)
            stderrBuffer = ""
        }
    }

    private func collapseCarriageReturns(_ text: String) -> String {
        if let lastCR = text.lastIndex(of: "\r") {
            return String(text[text.index(after: lastCR)...])
        }
        return text
    }

    private func append(_ text: String, kind: LineKind) {
        lines.append(OutputLine(text: text, kind: kind))
        if lines.count > maxLines {
            lines.removeFirst(lines.count - maxLines)
        }
    }
}
