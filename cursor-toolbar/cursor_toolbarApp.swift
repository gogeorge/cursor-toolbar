import AppKit
import Carbon
import Combine
import CoreGraphics
import SwiftUI

// MARK: - ToolbarPanel

/// How to position the panel after its content size changes.
fileprivate enum ResizeFitAnchor {
    /// Keep the same midpoint on screen (e.g. glass toggles wider/narrower).
    case frameCenter
    /// Put this screen-space point at the panel’s center (e.g. cursor when opening).
    case screenPoint(NSPoint)
}

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
        contentView = hosting
        DispatchQueue.main.async { [weak self] in
            self?.resizeToFitContent(anchor: .frameCenter)
        }
    }

    fileprivate func resizeToFitContent(anchor: ResizeFitAnchor = .frameCenter) {
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

// MARK: - Toolbar SwiftUI content

struct ToolbarContentView: View {
    @ObservedObject var clipboard: ClipboardManager
    @ObservedObject var notes: NotesManager
    @ObservedObject var flow: ToolbarFlowState
    var onDismiss: () -> Void
    var onLayoutChange: () -> Void

    private let iconDiameter: CGFloat = 44
    private let iconOrbitRadius: CGFloat = 78
    private let iconStackSpacing: CGFloat = 8
    private static let slotCount = 6

    private var linearRail: Bool { flow.sheetMode == .full }

    private var iconColumnWidth: CGFloat { linearRail ? 52 : 2 * iconOrbitRadius + iconDiameter }
    private var iconOrbitFrameHeight: CGFloat { 2 * iconOrbitRadius + iconDiameter }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            iconOrbit
            if flow.isGlassActive {
                glassPanel
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
        }
        .padding(flow.isGlassActive ? EdgeInsets(top: 18, leading: 14, bottom: 22, trailing: 22) : EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
        .animation(.spring(response: 0.38, dampingFraction: 0.82), value: flow.sheetMode)
        .animation(.spring(response: 0.38, dampingFraction: 0.82), value: linearRail)
        .background(Color.clear)
        .onChange(of: flow.sheetMode) { _, _ in
            onLayoutChange()
        }
        .onAppear { onLayoutChange() }
    }

    private var iconOrbit: some View {
        Group {
            if linearRail {
                VStack(spacing: iconStackSpacing) {
                    ForEach(0..<Self.slotCount, id: \.self) { index in
                        iconSlot(index: index)
                    }
                }
                .frame(width: iconColumnWidth)
            } else {
                ZStack {
                    ForEach(0..<Self.slotCount, id: \.self) { index in
                        iconSlot(index: index)
                            .offset(offsetForOrbit(index))
                    }
                }
                .frame(width: iconColumnWidth, height: iconOrbitFrameHeight)
            }
        }
    }

    @ViewBuilder
    private func iconSlot(index: Int) -> some View {
        let folders = Array(FolderShortcut.allCases)
        switch index {
        case let i where (0..<3).contains(i):
            let folder = folders[i]
            circularIconButton(
                isActive: false,
                accessibilityLabel: folder.title,
                action: { folder.openInFinder() }
            ) {
                Image(systemName: folder.systemImage)
                    .font(.system(size: 17, weight: .medium))
            }
        case 3:
            let notesOpen = flow.sheetMode == .notes || flow.sheetMode == .full
            circularIconButton(
                isActive: notesOpen,
                accessibilityLabel: "Notes",
                action: { flow.toggleNotes() }
            ) {
                HStack(spacing: 2) {
                    Image(systemName: "note.text")
                        .font(.system(size: 16, weight: .medium))
                    Image(systemName: notesOpen ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                }
            }
        case 4:
            let clipOpen = flow.sheetMode == .clipboard || flow.sheetMode == .full
            circularIconButton(
                isActive: clipOpen,
                accessibilityLabel: "Clipboard",
                action: { flow.toggleClipboard() }
            ) {
                HStack(spacing: 2) {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 15, weight: .medium))
                    Image(systemName: clipOpen ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                }
            }
        case 5:
            let full = flow.sheetMode == .full
            circularIconButton(
                isActive: full,
                accessibilityLabel: full ? "Collapse all" : "Expand all",
                action: { flow.toggleFullExpand() }
            ) {
                Image(systemName: full ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 12, weight: .semibold))
            }
        default:
            EmptyView()
        }
    }

    private func offsetForOrbit(_ index: Int) -> CGSize {
        let n = Double(Self.slotCount)
        let angle = -Double.pi / 2 + 2 * Double.pi * Double(index) / n
        let x = iconOrbitRadius * cos(angle)
        let y = iconOrbitRadius * sin(angle)
        return CGSize(width: x, height: y)
    }

    private func circularIconButton(
        isActive: Bool,
        accessibilityLabel: String,
        action: @escaping () -> Void,
        @ViewBuilder label: () -> some View
    ) -> some View {
        Button(action: action) {
            label()
                .foregroundStyle(Color.white)
                .frame(width: iconDiameter, height: iconDiameter)
                .background {
                    ZStack {
                        Circle().fill(.ultraThinMaterial)
                        Circle().fill(Color.white.opacity(isActive ? 0.22 : 0.14))
                    }
                }
                .overlay(
                    Circle()
                        .strokeBorder(Color.white.opacity(isActive ? 0.4 : 0.26), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.38), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    private var glassPanel: some View {
        let shape = RoundedRectangle(cornerRadius: ToolbarGlass.outerRadius, style: .continuous)

        let card = VStack(alignment: .leading, spacing: 0) {
            switch flow.sheetMode {
            case .collapsed:
                EmptyView()
            case .notes:
                NotesSectionView(notes: notes)
            case .clipboard:
                ClipboardSectionView(clipboard: clipboard, onCopyItem: onDismiss)
            case .full:
                VStack(alignment: .leading, spacing: ToolbarGlass.sectionSpacing) {
                    sectionBlock(title: "Folders") {
                        FinderFoldersColumn()
                    }
                    sectionBlock(title: "Notes") {
                        NotesSectionView(notes: notes)
                    }
                    sectionBlock(title: "Clipboard") {
                        ClipboardSectionView(clipboard: clipboard, onCopyItem: onDismiss)
                    }
                }
            }
        }
        .frame(width: 272, alignment: .leading)
        .padding(ToolbarGlass.innerPadding)
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

        return ZStack {
            shape
                .fill(Color.black.opacity(0.32))
                .blur(radius: 22)
                .offset(y: 12)
                .allowsHitTesting(false)
            card
        }
    }

    @ViewBuilder
    private func sectionBlock(title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.white)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

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
                flow: flow,
                onDismiss: { [weak self] in
                    self?.panel.orderOut(nil)
                },
                onLayoutChange: { [weak self] in
                    self?.panel.resizeToFitContent(anchor: .frameCenter)
                }
            )
        )
        registerHotKey()

        NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self else { return }
            if let until = self.suppressDismissUntil, Date() < until { return }
            guard self.panel.isVisible else { return }
            let screenLocation = NSEvent.mouseLocation
            if !self.panel.frame.contains(screenLocation) {
                self.panel.orderOut(nil)
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

        let mouseLoc = NSEvent.mouseLocation
        suppressDismissUntil = Date().addingTimeInterval(0.22)

        // First fit + center on cursor. A later async resize must re-anchor the same way;
        // otherwise only the size changes and the origin stays fixed, shifting the panel off the pointer.
        panel.resizeToFitContent(anchor: .screenPoint(mouseLoc))
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.panel.resizeToFitContent(anchor: .screenPoint(NSEvent.mouseLocation))
            self.panel.orderFrontRegardless()
        }
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let eventHandlerRef { RemoveEventHandler(eventHandlerRef) }
    }
}

// MARK: - App entry

@main
struct cursor_toolbarApp: App {
    private let coordinator = ToolbarCoordinator()

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
