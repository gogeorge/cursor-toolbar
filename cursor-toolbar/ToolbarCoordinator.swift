//
//  ToolbarCoordinator.swift
//  cursor-toolbar
//

import AppKit
import Carbon
import Combine
import SwiftUI

// MARK: - Hotkey handler

private func hotkeyHandler(
    nextHandler: EventHandlerCallRef?,
    event: EventRef?,
    userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let userData else { return OSStatus(eventNotHandledErr) }
    let coordinator = Unmanaged<ToolbarCoordinator>.fromOpaque(userData).takeUnretainedValue()
    coordinator.showMenu()
    return noErr
}

// MARK: - Coordinator

class ToolbarCoordinator: NSObject {
    let panel = ToolbarPanel()
    let clipboard = ClipboardManager()
    let notes = NotesManager()
    let previousApp = PreviousAppTracker()
    let aiPrompt = AIPromptState()
    let flow = ToolbarFlowState()
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    /// Ignores stray global mouse-downs right after opening (resize/cursor timing).
    private var suppressDismissUntil: Date?

    override init() {
        super.init()
        panel.setContent(
            ToolbarContentView(
                clipboard: clipboard,
                notes: notes,
                previousApp: previousApp,
                aiPrompt: aiPrompt,
                flow: flow,
                onDismiss: { [weak self] in
                    self?.hideMenu()
                },
                onLayoutChange: { [weak self] in
                    self?.panel.resizeToFitContent(anchor: .frameCenter)
                }
            )
        )
        registerHotKey()

        NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            guard let self else { return }
            if let until = self.suppressDismissUntil, Date() < until { return }
            guard self.panel.isVisible else { return }
            let screenLocation = NSEvent.mouseLocation
            if !self.panel.frame.contains(screenLocation) {
                self.hideMenu()
            }
        }
    }

    private func registerHotKey() {
        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = OSType(0x68746B31)
        hotKeyID.id = 1

        var eventType = EventTypeSpec()
        eventType.eventClass = OSType(kEventClassKeyboard)
        eventType.eventKind = OSType(kEventHotKeyPressed)

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), hotkeyHandler, 1, &eventType, selfPtr, &eventHandlerRef)
        RegisterEventHotKey(UInt32(kVK_Space), UInt32(cmdKey | shiftKey), hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    func showMenu() {
        flow.reset()
        flow.isPanelVisible = true
        previousApp.refreshForCurrentSpace()

        let mouseLoc = NSEvent.mouseLocation
        suppressDismissUntil = Date().addingTimeInterval(0.22)

        // First fit + center on cursor. A later async resize must re-anchor the same way;
        // otherwise only the size changes and the origin stays fixed, shifting the panel off the pointer.
        panel.resizeToFitContent(anchor: .screenPoint(mouseLoc))
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            // After we become key, recompute “previous” using `recent.last` as the effective front app.
            self.previousApp.refreshForCurrentSpace()
            self.panel.resizeToFitContent(anchor: .screenPoint(NSEvent.mouseLocation))
            self.panel.orderFrontRegardless()
        }
    }

    func hideMenu() {
        flow.isPanelVisible = false
        // Delay dismissing the window so the stagger animation has time to finish
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { [weak self] in
            guard let self else { return }
            if !self.flow.isPanelVisible {
                self.panel.orderOut(nil)
                self.flow.reset()
            }
        }
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let eventHandlerRef { RemoveEventHandler(eventHandlerRef) }
    }
}
