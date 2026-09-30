//
//  DevCommandsFeature.swift
//  cursor-toolbar
//
//  Command palette for dev/terminal mode: curated one-tap actions (YouTube
//  downloads, caffeinate, kill localhost ports, rclone Drive sync, key gen)
//  plus user-defined custom commands. Everything runs through TerminalEngine
//  so output streams into the shared console.
//

import AppKit
import Combine
import SwiftUI

// MARK: - Model

struct DevCommand: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var detail: String
    /// Shell command. May contain a single `{{arg}}` placeholder; when present
    /// the tile shows an input field before running.
    var template: String
    /// Placeholder shown in the argument field (e.g. "Playlist URL").
    var argPlaceholder: String?
    var isBuiltIn: Bool = false

    var needsArgument: Bool { template.contains("{{arg}}") }

    func resolved(with arg: String) -> String {
        guard needsArgument else { return template }
        return template.replacingOccurrences(of: "{{arg}}", with: arg)
    }
}

// MARK: - Built-in commands

enum DevCommandLibrary {
    /// yt-dlp lives in miniforge on this machine; a login shell resolves it on PATH.
    static let builtIns: [DevCommand] = [
        DevCommand(
            title: "Download YouTube playlist (all)",
            detail: "Downloads every video into ~/Downloads/<playlist>.",
            template: #"yt-dlp -o "$HOME/Downloads/%(playlist_title)s/%(title)s.%(ext)s" "{{arg}}""#,
            argPlaceholder: "Playlist URL",
            isBuiltIn: true
        ),
        DevCommand(
            title: "Download YouTube playlist (audio only)",
            detail: "Extracts MP3 audio for each video in the playlist.",
            template: #"yt-dlp -x --audio-format mp3 -o "$HOME/Downloads/%(playlist_title)s/%(title)s.%(ext)s" "{{arg}}""#,
            argPlaceholder: "Playlist URL",
            isBuiltIn: true
        ),
        DevCommand(
            title: "Download single YouTube video",
            detail: "Saves one video to ~/Downloads at best quality.",
            template: #"yt-dlp -o "$HOME/Downloads/%(title)s.%(ext)s" "{{arg}}""#,
            argPlaceholder: "Video URL",
            isBuiltIn: true
        ),
        DevCommand(
            title: "Keep Mac awake (until stopped)",
            detail: "Prevents idle sleep. Use “Stop caffeinate” to end.",
            template: "caffeinate -dimsu &",
            isBuiltIn: true
        ),
        DevCommand(
            title: "Keep Mac awake for 1 hour",
            detail: "Prevents sleep for 3600 seconds.",
            template: "caffeinate -t 3600 &",
            isBuiltIn: true
        ),
        DevCommand(
            title: "Stop caffeinate",
            detail: "Ends any running caffeinate session.",
            template: "pkill caffeinate && echo 'caffeinate stopped' || echo 'no caffeinate running'",
            isBuiltIn: true
        ),
        DevCommand(
            title: "Kill process on a port",
            detail: "Frees a stuck localhost port (e.g. 3000, 5173, 8080).",
            template: "lsof -ti tcp:{{arg}} | xargs kill -9 && echo 'killed port {{arg}}' || echo 'nothing on port {{arg}}'",
            argPlaceholder: "Port number",
            isBuiltIn: true
        ),
        DevCommand(
            title: "Kill common dev ports",
            detail: "Kills anything on 3000, 5173, 8080, 8000.",
            template: "for p in 3000 5173 8080 8000; do lsof -ti tcp:$p | xargs kill -9 2>/dev/null && echo \"killed $p\"; done; echo done",
            isBuiltIn: true
        ),
        DevCommand(
            title: "Google Drive sync (rclone)",
            detail: "Backs up ~/Desktop/everything to gdrive: in the background. Progress goes to ~/rclone_upload.log.",
            template: #"nohup rclone copy "$HOME/Desktop/everything" gdrive: --transfers 4 --checkers 8 --drive-chunk-size 128M --low-level-retries 20 --retries 10 --log-file ~/rclone_upload.log --log-level INFO --exclude ".DS_Store" &"#,
            isBuiltIn: true
        ),
        DevCommand(
            title: "Tail rclone upload log",
            detail: "Follows ~/rclone_upload.log live. Press Stop to end it.",
            template: "tail -f ~/rclone_upload.log",
            isBuiltIn: true
        ),
        DevCommand(
            title: "List rclone remotes",
            detail: "Shows configured rclone remotes (Google Drive, etc.).",
            template: "rclone listremotes",
            isBuiltIn: true
        ),
        DevCommand(
            title: "Random key — 32 bytes (hex)",
            detail: "Generates a hex key and copies it to the clipboard.",
            template: "openssl rand -hex 32 | tee >(pbcopy)",
            isBuiltIn: true
        ),
        DevCommand(
            title: "Random key — 32 bytes (base64)",
            detail: "Generates a base64 key and copies it to the clipboard.",
            template: "openssl rand -base64 32 | tee >(pbcopy)",
            isBuiltIn: true
        ),
    ]
}

// MARK: - State (custom commands persistence)

@MainActor
final class DevCommandsState: ObservableObject {
    @Published var customCommands: [DevCommand] = []

    private let key = "toolbar_dev_custom_commands_v1"

    init() { load() }

    func add(_ command: DevCommand) {
        customCommands.append(command)
        save()
    }

    func remove(_ command: DevCommand) {
        customCommands.removeAll { $0.id == command.id }
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([DevCommand].self, from: data)
        else { return }
        customCommands = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(customCommands) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

// MARK: - View

struct DevCommandsSectionView: View {
    @ObservedObject var engine: TerminalEngine
    @ObservedObject var state: DevCommandsState

    @State private var showAddForm = false
    @State private var newTitle = ""
    @State private var newCommand = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(DevCommandLibrary.builtIns) { command in
                CommandRow(command: command, engine: engine, onDelete: nil)
            }

            if !state.customCommands.isEmpty {
                Text("Custom")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.5))
                    .padding(.top, 4)
                ForEach(state.customCommands) { command in
                    CommandRow(command: command, engine: engine) {
                        state.remove(command)
                    }
                }
            }

            addSection
        }
    }

    private var addSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showAddForm {
                TextField("Name", text: $newTitle)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.black.opacity(0.22)))

                TextField("Shell command (use {{arg}} for input)", text: $newCommand)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Color.white)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.black.opacity(0.22)))

                HStack(spacing: 8) {
                    Button("Save") {
                        let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                        let cmd = newCommand.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !title.isEmpty, !cmd.isEmpty else { return }
                        state.add(DevCommand(
                            title: title,
                            detail: cmd,
                            template: cmd,
                            argPlaceholder: cmd.contains("{{arg}}") ? "Argument" : nil
                        ))
                        newTitle = ""; newCommand = ""; showAddForm = false
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.18)))

                    Button("Cancel") {
                        newTitle = ""; newCommand = ""; showAddForm = false
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.white.opacity(0.7))
                    .padding(.horizontal, 14).padding(.vertical, 7)
                }
            } else {
                Button {
                    showAddForm = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Add command")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(Color.white.opacity(0.85))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: ToolbarGlass.innerRadius, style: .continuous).fill(Color.white.opacity(0.10)))
                    .overlay(RoundedRectangle(cornerRadius: ToolbarGlass.innerRadius, style: .continuous).strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 4)
    }
}

// MARK: - Command row

private struct CommandRow: View {
    let command: DevCommand
    @ObservedObject var engine: TerminalEngine
    let onDelete: (() -> Void)?

    @State private var arg = ""
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(command.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(command.detail)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(Color.white.opacity(0.5))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)

                if let onDelete {
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.red.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                    .help("Delete command")
                }

                Button {
                    if command.needsArgument {
                        expanded.toggle()
                    } else {
                        engine.run(command.resolved(with: ""))
                    }
                } label: {
                    Image(systemName: command.needsArgument ? (expanded ? "chevron.up" : "play.circle.fill") : "play.circle.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Color.white, Color.white.opacity(0.28))
                }
                .buttonStyle(.plain)
                .disabled(engine.isRunning)
                .opacity(engine.isRunning ? 0.4 : 1)
            }

            if command.needsArgument && expanded {
                HStack(spacing: 8) {
                    TextField(command.argPlaceholder ?? "Argument", text: $arg)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Color.white)
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.black.opacity(0.28)))
                        .onSubmit(runWithArg)

                    Button(action: runWithArg) {
                        Text("Run")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.white)
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.18)))
                    }
                    .buttonStyle(.plain)
                    .disabled(engine.isRunning || arg.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: ToolbarGlass.innerRadius, style: .continuous)
                .fill(Color.black.opacity(0.22))
        )
        .overlay(
            RoundedRectangle(cornerRadius: ToolbarGlass.innerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
        )
    }

    private func runWithArg() {
        let value = arg.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !engine.isRunning else { return }
        engine.run(command.resolved(with: value))
        expanded = false
    }
}
