//
//  GlassChrome.swift
//  cursor-toolbar
//

import AppKit
import SwiftUI

/// Frosted panel material (blur + HUD-style glass) clipped to a continuous rounded rect.
struct GlassPanelBackground: NSViewRepresentable {
    var cornerRadius: CGFloat

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .hudWindow
        v.blendingMode = .behindWindow
        v.state = .active
        v.wantsLayer = true
        v.layer?.cornerRadius = cornerRadius
        v.layer?.cornerCurve = .continuous
        return v
    }

    func updateNSView(_ v: NSVisualEffectView, context: Context) {
        v.layer?.cornerRadius = cornerRadius
        v.layer?.cornerCurve = .continuous
    }
}

enum ToolbarGlass {
    static let outerRadius: CGFloat = 26
    /// Smaller chrome for each cell in the full-dashboard 2×2 grid.
    static let dashboardCellRadius: CGFloat = 20
    static let innerRadius: CGFloat = 18
    static let sectionSpacing: CGFloat = 14
    static let innerPadding = EdgeInsets(top: 18, leading: 18, bottom: 18, trailing: 18)
    static let borderOpacity: CGFloat = 0.22
    /// Slight warm tint over the material (harmonizes with desktop wallpaper bleed-through).
    static let tint = Color(red: 0.82, green: 0.78, blue: 0.68).opacity(0.14)
}
