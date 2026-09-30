//
//  LaunchAtLogin.swift
//  cursor-toolbar
//
//  A hotkey utility that has to be relaunched by hand after every reboot mostly
//  stops getting used, so expose the login-item registration as a toggle.
//

import Combine
import ServiceManagement

@MainActor
final class LaunchAtLogin: ObservableObject {
    /// Mirrors `SMAppService.mainApp.status`. Setting it registers or unregisters
    /// the login item; the getter is re-read from the service rather than cached,
    /// because the user can revoke it in System Settings > General > Login Items.
    @Published var isEnabled: Bool

    init() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    /// Re-reads the live status. Call when the menu opens so a change made in
    /// System Settings is reflected rather than showing a stale checkmark.
    func refresh() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    func toggle() {
        setEnabled(!isEnabled)
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                // `register` throws if it is already registered; treat that as success.
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Registration can legitimately fail — most often because the app is
            // running from a location the service cannot vouch for (a DerivedData
            // build, a quarantined download, or the Trash). Fall back to the
            // System Settings pane so the user is not left with a dead toggle.
            SMAppService.openSystemSettingsLoginItems()
        }
        refresh()
    }
}
