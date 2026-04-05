//
//  PreviousAppTracker.swift
//  cursor-toolbar
//

import AppKit
import ApplicationServices
import Combine

// MARK: - Previous app (active space)

/// Tracks the app you used before the current one. Uses activation notifications (sandbox-safe). When
/// `CGWindowListCopyWindowInfo` lists other apps’ windows, we also prefer candidates on the active space.
@MainActor
final class PreviousAppTracker: ObservableObject {
    @Published private(set) var previousAppBundleIdentifier: String?

    /// Recent activations, newest at end (this app is never stored).
    private var recentBundleIDs: [String] = []
    private let ownBundleID = Bundle.main.bundleIdentifier
    private var activationObserver: NSObjectProtocol?

    init() {
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            self.handleActivation(notification)
        }
        seedFromFrontmostIfEligible()
    }

    deinit {
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
    }

    func refreshForCurrentSpace() {
        recentBundleIDs = recentBundleIDs.filter { bid in
            NSRunningApplication.runningApplications(withBundleIdentifier: bid).contains { !$0.isTerminated }
        }
        seedFromFrontmostIfEligible()
        updatePublishedPrevious()
    }

    private func seedFromFrontmostIfEligible() {
        guard let front = NSWorkspace.shared.frontmostApplication,
              let bid = front.bundleIdentifier,
              bid != ownBundleID
        else { return }
        if recentBundleIDs.last != bid {
            recentBundleIDs.append(bid)
            trimRecent()
        }
    }

    private func handleActivation(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        guard let bid = app.bundleIdentifier, bid != ownBundleID else { return }
        if recentBundleIDs.last == bid { return }
        recentBundleIDs.append(bid)
        trimRecent()
        updatePublishedPrevious()
    }

    private func trimRecent() {
        let max = 24
        if recentBundleIDs.count > max {
            recentBundleIDs.removeFirst(recentBundleIDs.count - max)
        }
    }

    /// When our toolbar is key, treat the last non-self activation as the “current” app for picking “previous”.
    private func effectiveFrontBundleID() -> String? {
        let frontBid = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        if frontBid == ownBundleID {
            return recentBundleIDs.last
        }
        return frontBid
    }

    private func updatePublishedPrevious() {
        guard let anchor = effectiveFrontBundleID(), anchor != ownBundleID else {
            previousAppBundleIdentifier = nil
            return
        }
        guard let anchorIdx = recentBundleIDs.lastIndex(of: anchor), anchorIdx > 0 else {
            previousAppBundleIdentifier = nil
            return
        }
        for i in (0..<anchorIdx).reversed() {
            let bid = recentBundleIDs[i]
            if bid == anchor { continue }
            guard let _ = NSRunningApplication.runningApplications(withBundleIdentifier: bid).first(where: { !$0.isTerminated }) else {
                continue
            }
            previousAppBundleIdentifier = bid
            return
        }
        previousAppBundleIdentifier = nil
    }

    func iconForPreviousApp() -> NSImage? {
        guard let bid = previousAppBundleIdentifier else { return nil }
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid)
            ?? NSRunningApplication.runningApplications(withBundleIdentifier: bid).first?.bundleURL
        guard let url else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.isTemplate = false
        return icon
    }

    func accessibilityLabelForPreviousApp() -> String {
        guard let bid = previousAppBundleIdentifier else {
            return "Previous app"
        }
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: bid).first(where: { !$0.isTerminated }) {
            return running.localizedName.map { "Previous app: \($0)" } ?? "Previous app"
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) {
            let name = FileManager.default.displayName(atPath: url.path)
            return "Previous app: \(name)"
        }
        return "Previous app"
    }

    func activatePreviousApp() {
        guard let bid = previousAppBundleIdentifier else { return }
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bid).first(where: { !$0.isTerminated }) else { return }

        if app.isHidden {
            app.unhide()
        }

        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        if let url = app.bundleURL {
            NSWorkspace.shared.openApplication(at: url, configuration: config, completionHandler: nil)
        } else {
            app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        }

        Self.deminimizeWindowsIfPossible(pid: app.processIdentifier)
    }

    private static func deminimizeWindowsIfPossible(pid: pid_t) {
        guard AXIsProcessTrusted() else { return }
        let appElem = AXUIElementCreateApplication(pid)
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElem, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windowList = windowsRef as? [AXUIElement]
        else { return }
        for window in windowList {
            var minimizedRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimizedRef) == .success,
                  let isMin = minimizedRef as? Bool, isMin
            else { continue }
            AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        }
    }
}
