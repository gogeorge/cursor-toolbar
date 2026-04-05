//
//  CommandsFeature.swift
//  cursor-toolbar
//

import AppKit
import SwiftUI

// MARK: - Preset shell actions (friendly labels → safe commands)

struct ShellPreset: Identifiable {
    let id: String
    /// Short label shown in the UI.
    let title: String
    /// Plain-language explanation.
    let detail: String
    /// Human-readable description of what runs (for transparency).
    let commandSummary: String
    let executablePath: String
    let arguments: [String]

    static let all: [ShellPreset] = [
        ShellPreset(
            id: "caffeinate_1h",
            title: "Keep Mac awake for 1 hour",
            detail: "Prevents sleep while on battery or lid closed (display may still dim).",
            commandSummary: "caffeinate -t 3600",
            executablePath: "/usr/bin/caffeinate",
            arguments: ["-t", "3600"]
        ),
        ShellPreset(
            id: "caffeinate_15m",
            title: "Keep Mac awake for 15 minutes",
            detail: "Short focus session without the Mac sleeping.",
            commandSummary: "caffeinate -t 900",
            executablePath: "/usr/bin/caffeinate",
            arguments: ["-t", "900"]
        ),
        ShellPreset(
            id: "open_terminal",
            title: "Open Terminal",
            detail: "Launches the Terminal app.",
            commandSummary: "open -a Terminal",
            executablePath: "/usr/bin/open",
            arguments: ["-a", "Terminal"]
        ),
        ShellPreset(
            id: "open_activity_monitor",
            title: "Open Activity Monitor",
            detail: "See which apps are using CPU and memory.",
            commandSummary: "open -a \"Activity Monitor\"",
            executablePath: "/usr/bin/open",
            arguments: ["-a", "Activity Monitor"]
        ),
        ShellPreset(
            id: "open_disk_utility",
            title: "Open Disk Utility",
            detail: "Check or repair disks and volumes.",
            commandSummary: "open -a \"Disk Utility\"",
            executablePath: "/usr/bin/open",
            arguments: ["-a", "Disk Utility"]
        ),
        ShellPreset(
            id: "open_finder_downloads",
            title: "Open Downloads in Finder",
            detail: "Opens your Downloads folder.",
            commandSummary: "open ~/Downloads",
            executablePath: "/usr/bin/open",
            arguments: [NSHomeDirectory() + "/Downloads"]
        ),
    ]
}

enum ShellCommandRunner {
    static func run(preset: ShellPreset) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: preset.executablePath)
        p.arguments = preset.arguments
        do {
            try p.run()
        } catch {
            NSSound.beep()
        }
    }
}

// MARK: - Dashboard section

struct CommandsSectionView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Tap a shortcut to run it. Commands use macOS built-in tools.")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(Color.white.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 8) {
                ForEach(ShellPreset.all) { preset in
                    Button {
                        ShellCommandRunner.run(preset: preset)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(preset.title)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.white)
                            Text(preset.detail)
                                .font(.system(size: 11, weight: .regular))
                                .foregroundStyle(Color.white.opacity(0.55))
                                .fixedSize(horizontal: false, vertical: true)
                            Text(preset.commandSummary)
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundStyle(Color.white.opacity(0.38))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
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
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
