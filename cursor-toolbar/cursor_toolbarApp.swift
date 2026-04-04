import AppKit
import Carbon
import Combine
import SwiftUI

// MARK: - ToolbarPanel

class ToolbarPanel: NSPanel {
    /// Allows `TextEditor` / text fields to receive keyboard input while using a non-activating panel style.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

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
        self.level = .floating
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
            self?.resizeToFitContent()
        }
    }

    func resizeToFitContent() {
        guard let cv = contentView else { return }
        cv.layoutSubtreeIfNeeded()
        let s = cv.fittingSize
        guard s.width > 10, s.height > 10 else { return }
        var f = frame
        f.size = NSSize(width: max(52, ceil(s.width)), height: max(120, ceil(s.height)))
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
                .background(
                    Circle()
                        .fill(Color.white.opacity(isActive ? 0.24 : 0.16))
                )
                .overlay(
                    Circle()
                        .strokeBorder(Color.white.opacity(isActive ? 0.38 : 0.22), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.4), radius: 4, y: 2)
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
                    self?.panel.resizeToFitContent()
                }
            )
        )
        registerHotKey()

        NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self else { return }
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

        panel.resizeToFitContent()

        let mouseLoc = NSEvent.mouseLocation
        let x = mouseLoc.x - (panel.frame.width / 2)
        let y = mouseLoc.y - (panel.frame.height / 2)
        panel.setFrameOrigin(NSPoint(x: x, y: y))
        panel.makeKeyAndOrderFront(nil)

        DispatchQueue.main.async { [weak self] in
            self?.panel.resizeToFitContent()
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
