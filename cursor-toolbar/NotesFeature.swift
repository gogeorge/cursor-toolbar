//
//  NotesFeature.swift
//  cursor-toolbar
//

import Combine
import SwiftUI

// MARK: - Notes Manager

class NotesManager: ObservableObject {
    @Published var text: String = "" {
        didSet { save() }
    }
    @Published var isStickyOpen: Bool = false

    private let saveKey = "toolbar_notes"
    private var stickyPanel: NSPanel?

    init() {
        text = UserDefaults.standard.string(forKey: saveKey) ?? ""
    }

    private func save() {
        UserDefaults.standard.set(text, forKey: saveKey)
    }
    
    func toggleSticky() {
        if isStickyOpen {
            closeSticky()
        } else {
            openSticky()
        }
    }
    
    private func openSticky() {
        if stickyPanel == nil {
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 280, height: 260),
                styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless, .resizable],
                backing: .buffered,
                defer: false
            )
            panel.isFloatingPanel = true
            panel.level = NSWindow.Level(Int(CGWindowLevelForKey(.maximumWindow)))
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = false
            panel.isMovableByWindowBackground = true
            
            let host = NSHostingView(rootView: StickyNotesContentView(notes: self))
            panel.contentView = host
            
            if let screen = NSScreen.main {
                let f = panel.frame
                let newOrigin = NSPoint(x: screen.visibleFrame.midX - f.width/2, y: screen.visibleFrame.midY - f.height/2)
                panel.setFrameOrigin(newOrigin)
            }
            
            self.stickyPanel = panel
        }
        
        stickyPanel?.makeKeyAndOrderFront(nil)
        stickyPanel?.orderFrontRegardless()
        isStickyOpen = true
    }
    
    func closeSticky() {
        stickyPanel?.orderOut(nil)
        isStickyOpen = false
    }
}

struct StickyNotesContentView: View {
    @ObservedObject var notes: NotesManager

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: ToolbarGlass.outerRadius, style: .continuous)
        
        VStack(spacing: 0) {
            // Drag handle / Header
            HStack {
                Text("Sticky Notes")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.8))
                Spacer()
                Button {
                    notes.closeSticky()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            
            // Notes Editor
            ZStack(alignment: .topLeading) {
                TextEditor(text: $notes.text)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Color.white)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 180)
                
                if notes.text.isEmpty {
                    Text("Write something…")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(Color.white.opacity(0.42))
                        .padding(.top, 6)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
            }
            .padding(10)
        }
        .background {
            ZStack {
                GlassPanelBackground(cornerRadius: ToolbarGlass.outerRadius)
                shape.fill(ToolbarGlass.tint)
            }
        }
        .clipShape(shape)
        .overlay(
            shape.strokeBorder(Color.white.opacity(ToolbarGlass.borderOpacity), lineWidth: 1)
        )
        .padding(14)
        .shadow(color: Color.black.opacity(0.20), radius: 28, x: 0, y: 14)
        .shadow(color: Color.black.opacity(0.07), radius: 6, x: 0, y: 3)
    }
}

// MARK: - Notes section (glass-styled editor)

struct NotesSectionView: View {
    @ObservedObject var notes: NotesManager
    /// Tighter editor for dashboard tiles so the outer cell does not need its own scrollbar.
    var useCompactEditor: Bool = false

    var body: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $notes.text)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Color.white)
                    .scrollContentBackground(.hidden)
                    .frame(
                        minHeight: useCompactEditor ? 96 : 200,
                        idealHeight: useCompactEditor ? 120 : 240,
                        maxHeight: useCompactEditor ? 132 : 240
                    )

                if notes.text.isEmpty {
                    Text("Write something…")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(Color.white.opacity(0.42))
                        .padding(.top, 6)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: ToolbarGlass.innerRadius, style: .continuous)
                    .fill(Color.black.opacity(0.22))
            )
            .overlay(
                RoundedRectangle(cornerRadius: ToolbarGlass.innerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
            )
            
            HStack {
                Spacer()
                Button {
                    notes.toggleSticky()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "pin")
                        Text(notes.isStickyOpen ? "Close sticky" : "Make sticky")
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.8))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.15))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }
}
