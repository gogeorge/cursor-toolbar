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
        self.hasShadow = true
    }

    func setContent(_ view: some View) {
        contentView = NSHostingView(rootView: view)
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
        f.size = NSSize(width: max(260, ceil(s.width)), height: max(200, ceil(s.height)))
        setFrame(f, display: true)
    }
}

// MARK: - Toolbar SwiftUI content

struct ToolbarContentView: View {
    @ObservedObject var clipboard: ClipboardManager
    @ObservedObject var notes: NotesManager
    var onDismiss: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: ToolbarGlass.outerRadius, style: .continuous)

        VStack(alignment: .leading, spacing: ToolbarGlass.sectionSpacing) {
            sectionBlock(title: "Clipboard") {
                ClipboardSectionView(clipboard: clipboard, onCopyItem: onDismiss)
            }

            sectionBlock(title: "Notes") {
                NotesSectionView(notes: notes)
            }

            sectionBlock(title: "Folders") {
                FinderFoldersColumn()
            }
        }
        .padding(ToolbarGlass.innerPadding)
        .frame(width: 272)
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
        .shadow(color: .black.opacity(0.28), radius: 22, y: 10)
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
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    override init() {
        super.init()
        panel.setContent(
            ToolbarContentView(
                clipboard: clipboard,
                notes: notes,
                onDismiss: { [weak self] in
                    self?.panel.orderOut(nil)
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
        panel.resizeToFitContent()

        let mouseLoc = NSEvent.mouseLocation
        let x = mouseLoc.x - (panel.frame.width / 2)
        let y = mouseLoc.y - (panel.frame.height / 2)
        panel.setFrameOrigin(NSPoint(x: x, y: y))
        panel.makeKeyAndOrderFront(nil)
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
