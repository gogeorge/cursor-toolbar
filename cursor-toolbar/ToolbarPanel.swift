//
//  ToolbarPanel.swift
//  cursor-toolbar
//

import AppKit
import CoreGraphics
import SwiftUI

// MARK: - Resize anchor

/// How to position the panel after its content size changes.
enum ResizeFitAnchor {
    /// Keep the same midpoint on screen (e.g. glass toggles wider/narrower).
    case frameCenter
    /// Put this screen-space point at the panel’s center (e.g. cursor when opening).
    case screenPoint(NSPoint)
}

// MARK: - ToolbarPanel

class ToolbarPanel: NSPanel {
    /// Allows `TextEditor` / text fields to receive keyboard input while using a non-activating panel style.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Lower bound for collapsed orbit + padding (`ToolbarContentView`); avoids bogus `fittingSize` after blend/layout quirks.
    private static let minOrbitContent = NSSize(width: 224, height: 224)

    override init(
        contentRect: NSRect,
        styleMask style: NSWindow.StyleMask,
        backing backingStoreType: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 420),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )
        self.isFloatingPanel = true
        // Stay above normal windows, fullscreen content, and most app UI (same idea as max z-index).
        self.level = NSWindow.Level(Int(CGWindowLevelForKey(.maximumWindow)))
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = false
    }

    func setContent(_ view: some View) {
        let hosting = NSHostingView(rootView: view)
        hosting.wantsLayer = true
        hosting.layer?.masksToBounds = false
        hosting.clipsToBounds = false
        contentView = hosting
        DispatchQueue.main.async { [weak self] in
            self?.resizeToFitContent(anchor: .frameCenter)
        }
    }

    func resizeToFitContent(anchor: ResizeFitAnchor = .frameCenter) {
        guard let cv = contentView else { return }
        cv.layoutSubtreeIfNeeded()
        let s = cv.fittingSize
        let old = frame
        // `fittingSize` can briefly report ~0 over some compositing paths (often on light UIs), which
        // would collapse the panel; fall back to last frame or orbit minimum.
        let fitW: CGFloat
        let fitH: CGFloat
        if s.width > 10, s.height > 10 {
            fitW = s.width
            fitH = s.height
        } else {
            fitW = max(Self.minOrbitContent.width, old.width)
            fitH = max(Self.minOrbitContent.height, old.height)
        }
        let w = max(Self.minOrbitContent.width, max(52, ceil(fitW)))
        let h = max(Self.minOrbitContent.height, max(120, ceil(fitH)))
        let anchorPoint: NSPoint
        switch anchor {
        case .frameCenter:
            anchorPoint = NSPoint(x: old.midX, y: old.midY)
        case .screenPoint(let p):
            anchorPoint = p
        }

        var f = old
        f.size = NSSize(width: w, height: h)
        f.origin.x = anchorPoint.x - f.width / 2
        f.origin.y = anchorPoint.y - f.height / 2
        setFrame(f, display: true)
    }
}
