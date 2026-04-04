//
//  ToolbarWindow.swift
//  cursor-toolbar
//
//  Created by George Valtas on 04/04/2026.
//
//import Cocoa
//import SwiftUI
//
//class ToolbarPanel: NSPanel {
//    init() {
//        super.init(
//            contentRect: NSRect(x: 0, y: 0, width: 350, height: 60),
//            styleMask: [.borderless, .nonactivatingPanel],
//            backing: .buffered,
//            defer: false
//        )
//        
//        self.level = .mainMenu + 1 // Floats above other apps
//        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
//        self.backgroundColor = .clear
//        self.isOpaque = false
//        self.hasShadow = true
//        
//        // Host the SwiftUI View
//        self.contentView = NSHostingView(rootView: ToolbarView())
//    }
//}
//
//struct ToolbarView: View {
//    var body: some View {
//        HStack(spacing: 20) {
//            Image(systemName: "play.fill")
//            Image(systemName: "magnifyingglass")
//            Image(systemName: "face.smiling")
//            Image(systemName: "camera.viewfinder")
//            Image(systemName: "mic.slash.fill")
//        }
//        .font(.system(size: 20))
//        .padding(.horizontal, 25)
//        .padding(.vertical, 12)
//        .background(VisualEffectView().cornerRadius(15))
//        .overlay(RoundedRectangle(cornerRadius: 15).stroke(Color.white.opacity(0.2), lineWidth: 0.5))
//    }
//}
//
//struct VisualEffectView: NSViewRepresentable {
//    func makeNSView(context: Context) -> NSVisualEffectView {
//        let view = NSVisualEffectView()
//        view.material = .hudWindow // Dark glass look
//        view.state = .active
//        return view
//    }
//    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
//}
