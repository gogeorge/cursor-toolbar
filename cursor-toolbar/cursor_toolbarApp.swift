import SwiftUI
import AppKit
import Carbon
import Combine

// MARK: - ToolbarPanel
class ToolbarPanel: NSPanel {
    override init(
        contentRect: NSRect,
        styleMask style: NSWindow.StyleMask,
        backing backingStoreType: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 220, height: 50),
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
        self.contentView = NSHostingView(rootView: view)
    }
}

// MARK: - Toolbar SwiftUI Content
struct ToolbarContentView: View {
    @ObservedObject var clipboard: ClipboardManager
    @ObservedObject var notes: NotesManager
    @State private var showClipboard = false
    @State private var showNotes = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Main toolbar row
            HStack(spacing: 12) {
                Button("✂️") {}

                Button("📋") {
                    withAnimation(.spring(response: 0.3)) {
                        showClipboard.toggle()
                        if showClipboard { showNotes = false }
                    }
                }

                Button("🗒️") {
                    withAnimation(.spring(response: 0.3)) {
                        showNotes.toggle()
                        if showNotes { showClipboard = false }
                    }
                }

                Button("🔍") {}
            }
            .padding(8)

            if showClipboard {
                ClipboardDropdownView(clipboard: clipboard, isShowing: $showClipboard)
            }

            if showNotes {
                NotesDropdownView(notes: notes)
            }
        }
        .background(.ultraThinMaterial)
        .cornerRadius(10)
        .fixedSize()
    }
}

// MARK: - Hotkey Handler
private func hotkeyHandler(
    nextHandler: EventHandlerCallRef?,
    event: EventRef?,
    userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let userData = userData else { return OSStatus(eventNotHandledErr) }
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
        panel.setContent(ToolbarContentView(clipboard: clipboard, notes: notes))
        registerHotKey()

        NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            return event
        }

        NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self = self else { return }
            let clickLocation = event.locationInWindow
            let screenLocation = NSEvent.mouseLocation
            
            // Only dismiss if the click is outside the panel's frame
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
        let mouseLoc = NSEvent.mouseLocation
        let x = mouseLoc.x - (panel.frame.width / 2)
        let y = mouseLoc.y - (panel.frame.height / 2)
        panel.setFrameOrigin(NSPoint(x: x, y: y))
        panel.makeKeyAndOrderFront(nil)
    }

    deinit {
        if let hotKeyRef = hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let eventHandlerRef = eventHandlerRef { RemoveEventHandler(eventHandlerRef) }
    }
}

// MARK: - App Entry Point
@main
struct cursor_toolbarApp: App {
    private let coordinator = ToolbarCoordinator()

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
