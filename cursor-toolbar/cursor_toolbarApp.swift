//
//  cursor_toolbarApp.swift
//  cursor-toolbar
//

import AppKit
import SwiftUI

@main
struct cursor_toolbarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var launchAtLogin = LaunchAtLogin()

    var body: some Scene {
        // The app is an accessory (no Dock icon), so this is the only always-visible
        // affordance: it advertises the hotkey and provides a way to quit.
        MenuBarExtra("Janus", systemImage: "theatermasks.fill") {
            Button("Show Toolbar") { appDelegate.coordinator?.showMenu() }
                .keyboardShortcut(.space, modifiers: [.command, .shift])
            Toggle("Launch at Login", isOn: Binding(
                get: { launchAtLogin.isEnabled },
                set: { launchAtLogin.setEnabled($0) }
            ))
            Divider()
            Button("Grant Accessibility Access…") {
                guard let tracker = appDelegate.coordinator?.previousApp else { return }
                // The system prompt only ever appears once; fall back to opening the
                // settings pane so this menu item is never a dead end.
                if tracker.hasAccessibilityAccess {
                    tracker.openAccessibilitySettings()
                } else {
                    tracker.requestAccessibilityAccess()
                    tracker.openAccessibilitySettings()
                }
            }
            Divider()
            SettingsLink { Text("Settings…") }
                .keyboardShortcut(",", modifiers: .command)
            Button("Quit Janus") { NSApp.terminate(nil) }
                .keyboardShortcut("q", modifiers: .command)
        }

        Settings {
            EmptyView()
        }
    }
}

/// Owns the coordinator so it is built exactly once, after AppKit has finished
/// launching. Constructing it in the `App` struct registered the global hotkey
/// before `NSApplication` was ready, and SwiftUI is free to re-create the `App`
/// value — a second `RegisterEventHotKey` for the same combo fails silently and
/// leaves the hotkey dead.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var coordinator: ToolbarCoordinator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Redundant with LSUIElement, but keeps the policy correct if the
        // Info.plist key is ever dropped.
        NSApp.setActivationPolicy(.accessory)
        coordinator = ToolbarCoordinator()
    }
}
