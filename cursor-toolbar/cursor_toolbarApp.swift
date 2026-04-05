import AppKit
import ApplicationServices
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
        hosting.clipsToBounds = false
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

/// Subtle continuous rotation while the dashboard is in “edit” mode (similar to iOS icon jiggle).
private struct DashboardTileWiggleModifier: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        if active {
            TimelineView(.animation(minimumInterval: 1.0 / 32.0)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                let angle = sin(t * 10.8) * 1.65
                content.rotationEffect(.degrees(angle))
            }
        } else {
            content
        }
    }
}

struct ToolbarContentView: View {
    @ObservedObject var clipboard: ClipboardManager
    @ObservedObject var notes: NotesManager
    @ObservedObject var previousApp: PreviousAppTracker
    @ObservedObject var aiPrompt: AIPromptState
    @ObservedObject var flow: ToolbarFlowState
    var onDismiss: () -> Void
    var onLayoutChange: () -> Void

    private let iconDiameter: CGFloat = 44
    private let iconOrbitRadius: CGFloat = 78
    private let iconStackSpacing: CGFloat = 8
    /// Same gap as between the icon rail and the glass panel (`HStack` below).
    private let iconToPanelSpacing: CGFloat = 14
    private static let slotCount = 6
    /// Square dashboard tiles (width and height match).
    private static let dashboardCellSize: CGFloat = 272

    private var linearRail: Bool { flow.sheetMode == .full }

    private var iconColumnWidth: CGFloat { linearRail ? 52 : 2 * iconOrbitRadius + iconDiameter }
    private var iconOrbitFrameHeight: CGFloat { 2 * iconOrbitRadius + iconDiameter }

    private var rootPadding: EdgeInsets {
        if flow.isGlassActive {
            // Extra trailing/bottom room so the panel shadow is not clipped by the window (visible on light backgrounds).
            return EdgeInsets(top: 20, leading: 14, bottom: 40, trailing: 48)
        }
        return EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12)
    }

    var body: some View {
        HStack(alignment: .top, spacing: iconToPanelSpacing) {
            iconOrbit
            if flow.isGlassActive && flow.isPanelVisible {
                Group {
                    if flow.sheetMode == .full {
                        HStack(alignment: .top, spacing: iconToPanelSpacing) {
                            fullDashboardGrid
                            if flow.isEditingDashboard, !flow.dashboardModulesToAdd.isEmpty {
                                dashboardAddModulePanel(gap: iconToPanelSpacing, cell: Self.dashboardCellSize)
                            }
                            fullExpandTrailingColumn
                                .frame(width: iconColumnWidth)
                        }
                    } else {
                        glassPanel
                    }
                }
                .transition(
                    .asymmetric(
                        insertion: .scale(scale: 0.9, anchor: .leading).combined(with: .opacity).combined(with: .offset(x: -16)),
                        removal: .scale(scale: 0.9, anchor: .leading).combined(with: .opacity).combined(with: .offset(x: -16))
                    )
                )
            }
        }
        .padding(rootPadding)
        .animation(.spring(response: 0.38, dampingFraction: 0.82), value: flow.sheetMode)
        .animation(.spring(response: 0.38, dampingFraction: 0.82), value: linearRail)
        .animation(.spring(response: 0.38, dampingFraction: 0.82), value: flow.isPanelVisible)
        .background(Color.clear)
        .onChange(of: flow.sheetMode) { _, newMode in
            if newMode != .full {
                flow.cancelDashboardEdit()
            }
            onLayoutChange()
        }
        .onChange(of: flow.isEditingDashboard) { _, _ in
            onLayoutChange()
        }
        .onChange(of: flow.dashboardModules.map(\.rawValue).joined(separator: "|")) { _, _ in
            onLayoutChange()
        }
        .onAppear { onLayoutChange() }
    }

    private var iconOrbit: some View {
        let railDelayFactor = 0.04
        return ZStack {
            ForEach(0..<Self.slotCount, id: \.self) { index in
                let popDelay = flow.isPanelVisible ? Double(index) * 0.05 : Double(Self.slotCount - 1 - index) * 0.05
                let railDelay = linearRail ? Double(index) * railDelayFactor : Double(Self.slotCount - 1 - index) * railDelayFactor
                iconSlot(index: index)
                    .offset(linearRail ? linearRailOffset(index) : offsetForOrbit(index))
                    .scaleEffect(flow.isPanelVisible ? 1 : 0.4)
                    .opacity(flow.isPanelVisible ? 1 : 0)
                    .animation(.spring(response: 0.38, dampingFraction: 0.72).delay(popDelay), value: flow.isPanelVisible)
                    .animation(.spring(response: 0.45, dampingFraction: 0.75).delay(railDelay), value: linearRail)
            }
        }
        .frame(
            width: iconColumnWidth,
            height: linearRail ? (CGFloat(Self.slotCount) * iconDiameter + CGFloat(Self.slotCount - 1) * iconStackSpacing) : iconOrbitFrameHeight
        )
    }

    private func linearRailOffset(_ index: Int) -> CGSize {
        let totalHeight = CGFloat(Self.slotCount) * iconDiameter + CGFloat(Self.slotCount - 1) * iconStackSpacing
        let startY = -totalHeight / 2 + (iconDiameter / 2)
        let y = startY + CGFloat(index) * (iconDiameter + iconStackSpacing)
        return CGSize(width: 0, height: y)
    }

    @ViewBuilder
    private func iconSlot(index: Int) -> some View {
        switch index {
        case 0:
            circularIconButton(
                isActive: false,
                accessibilityLabel: previousApp.accessibilityLabelForPreviousApp(),
                action: { previousApp.activatePreviousApp() }
            ) {
                Group {
                    if let icon = previousApp.iconForPreviousApp() {
                        Image(nsImage: icon)
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fit)
                    } else {
                        Image(systemName: "app.dashed")
                            .font(.system(size: 18, weight: .medium))
                    }
                }
                .frame(width: 26, height: 26)
            }
        case 1:
            let foldersOpen = flow.sheetMode == .standardFolders || flow.sheetMode == .full
            circularIconButton(
                isActive: flow.sheetMode == .standardFolders,
                accessibilityLabel: "Folders: Documents, Downloads, Applications, and Library",
                action: { flow.toggleStandardFolders() }
            ) {
                HStack(spacing: 2) {
                    Image(systemName: "folder")
                        .font(.system(size: 16, weight: .medium))
                    Image(systemName: foldersOpen ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                }
            }
        case 2:
            let aiOpen = flow.sheetMode == .aiPrompt || flow.sheetMode == .full
            circularIconButton(
                isActive: flow.sheetMode == .aiPrompt,
                accessibilityLabel: "AI prompt",
                action: { flow.toggleAIPrompt() }
            ) {
                HStack(spacing: 2) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 16, weight: .medium))
                    Image(systemName: aiOpen ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                }
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

    private var fullExpandTrailingColumn: some View {
        VStack(spacing: iconStackSpacing) {
            circularIconButton(
                isActive: false,
                accessibilityLabel: "Settings",
                action: { openToolbarSettings() }
            ) {
                Image(systemName: "gearshape")
                    .font(.system(size: 18, weight: .medium))
            }
            if flow.isEditingDashboard {
                circularIconButton(
                    isActive: true,
                    accessibilityLabel: "Done editing dashboard",
                    action: {
                        guard flow.sheetMode == .full else { return }
                        flow.toggleDashboardEditMode()
                    }
                ) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18, weight: .medium))
                }
                circularIconButton(
                    isActive: false,
                    accessibilityLabel: "Cancel dashboard edits",
                    action: {
                        guard flow.sheetMode == .full else { return }
                        flow.cancelDashboardEditDiscardingChanges()
                    }
                ) {
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 18, weight: .medium))
                }
            } else {
                circularIconButton(
                    isActive: false,
                    accessibilityLabel: "Edit dashboard",
                    action: {
                        guard flow.sheetMode == .full else { return }
                        flow.toggleDashboardEditMode()
                    }
                ) {
                    Image(systemName: "pencil")
                        .font(.system(size: 18, weight: .medium))
                }
            }
            circularIconButton(
                isActive: false,
                accessibilityLabel: "Cursor toolbar",
                action: {}
            ) {
                Image("CursorLogoWhite")
                    .renderingMode(.template)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 22, height: 22)
            }
        }
    }

    private func openToolbarSettings() {
        if !NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }

    /// Full dashboard: glass tiles in a 2-column grid; edit mode wiggles tiles and shows remove controls (like iOS home screen).
    private var fullDashboardGrid: some View {
        let gap = iconToPanelSpacing
        let cell = Self.dashboardCellSize
        let columns = [
            GridItem(.fixed(cell), spacing: gap, alignment: .top),
            GridItem(.fixed(cell), spacing: gap, alignment: .top),
        ]
        return VStack(alignment: .leading, spacing: gap + 4) {
            if flow.dashboardModules.isEmpty {
                Text(flow.isEditingDashboard ? "No panels on the dashboard. Add one from the list." : "Dashboard is empty. Tap Edit to add panels.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.55))
                    .frame(width: cell * 2 + gap, alignment: .leading)
                    .padding(.vertical, 8)
            }
            LazyVGrid(columns: columns, alignment: .leading, spacing: gap) {
                ForEach(flow.dashboardModules) { module in
                    ZStack(alignment: .topLeading) {
                        dashboardCell(size: cell, contentLocked: flow.isEditingDashboard) {
                            dashboardModuleContent(module)
                        }
                        if flow.isEditingDashboard {
                            Button {
                                flow.removeDashboardModule(module)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(Color.white, Color.black.opacity(0.45))
                                    .font(.system(size: 24, weight: .semibold))
                                    .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove \(module.panelTitle) from dashboard")
                            .offset(x: -10, y: -10)
                        }
                    }
                    .modifier(DashboardTileWiggleModifier(active: flow.isEditingDashboard))
                }
            }
        }
    }

    /// Narrow glass column for modules not yet on the dashboard (smaller than grid cells).
    private func dashboardAddModulePanel(gap: CGFloat, cell: CGFloat) -> some View {
        let r = ToolbarGlass.dashboardCellRadius
        let shape = RoundedRectangle(cornerRadius: r, style: .continuous)
        let addPanelWidth: CGFloat = 212
        let pad = EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12)
        return ScrollView {
            dashboardAddPaletteList()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(pad)
        }
        .scrollIndicators(.hidden)
        .frame(width: addPanelWidth)
        .frame(maxHeight: cell * 2 + gap)
        .background {
            ZStack {
                GlassPanelBackground(cornerRadius: r)
                shape.fill(ToolbarGlass.tint)
            }
        }
        .clipShape(shape)
        .overlay(
            shape.strokeBorder(Color.white.opacity(ToolbarGlass.borderOpacity), lineWidth: 1)
        )
        .compositingGroup()
        .shadow(color: Color.black.opacity(0.18), radius: 18, x: 0, y: 10)
        .shadow(color: Color.black.opacity(0.06), radius: 5, x: 0, y: 2)
    }

    private func dashboardAddPaletteList() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Add to dashboard")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.9))
            VStack(alignment: .leading, spacing: 8) {
                ForEach(flow.dashboardModulesToAdd) { module in
                    Button {
                        flow.addDashboardModule(module)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(Color.white, Color.white.opacity(0.28))
                            Text(module.panelTitle)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color.white)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: ToolbarGlass.innerRadius, style: .continuous)
                                .fill(Color.black.opacity(0.22))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: ToolbarGlass.innerRadius, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add \(module.panelTitle)")
                }
            }
        }
    }

    @ViewBuilder
    private func dashboardModuleContent(_ module: DashboardModule) -> some View {
        switch module {
        case .folders:
            sectionBlock(title: module.panelTitle) {
                FinderFoldersColumn()
            }
        case .notes:
            sectionBlock(title: module.panelTitle) {
                NotesSectionView(notes: notes, useCompactEditor: true)
            }
        case .aiPrompt:
            sectionBlock(title: module.panelTitle) {
                AIPromptSectionView(state: aiPrompt)
            }
        case .clipboard:
            sectionBlock(title: module.panelTitle) {
                ClipboardSectionView(clipboard: clipboard, onCopyItem: onDismiss)
            }
        case .commands:
            sectionBlock(title: module.panelTitle) {
                CommandsSectionView()
            }
        }
    }

    private func dashboardCell<Content: View>(size: CGFloat, contentLocked: Bool, @ViewBuilder content: () -> Content) -> some View {
        let r = ToolbarGlass.dashboardCellRadius
        let shape = RoundedRectangle(cornerRadius: r, style: .continuous)
        let pad = EdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14)
        return ScrollView {
            content()
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(pad)
        }
        .scrollIndicators(.hidden)
        .allowsHitTesting(!contentLocked)
        .frame(width: size, height: size)
        .background {
            ZStack {
                GlassPanelBackground(cornerRadius: r)
                shape.fill(ToolbarGlass.tint)
            }
        }
        .clipShape(shape)
        .overlay(
            shape.strokeBorder(Color.white.opacity(ToolbarGlass.borderOpacity), lineWidth: 1)
        )
        .compositingGroup()
        .shadow(color: Color.black.opacity(0.18), radius: 18, x: 0, y: 10)
        .shadow(color: Color.black.opacity(0.06), radius: 5, x: 0, y: 2)
    }

    private var glassPanel: some View {
        let shape = RoundedRectangle(cornerRadius: ToolbarGlass.outerRadius, style: .continuous)

        let card = VStack(alignment: .leading, spacing: 0) {
            switch flow.sheetMode {
            case .collapsed, .full:
                EmptyView()
            case .standardFolders:
                sectionBlock(title: "Folders") {
                    FinderFoldersColumn()
                }
            case .aiPrompt:
                sectionBlock(title: "AI prompt") {
                    AIPromptSectionView(state: aiPrompt)
                }
            case .notes:
                NotesSectionView(notes: notes)
            case .clipboard:
                ClipboardSectionView(clipboard: clipboard, onCopyItem: onDismiss)
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

        // CompositingGroup + SwiftUI shadow follows the rounded shape; avoid a blurred rect (clips to a box on white).
        return card
            .compositingGroup()
            .shadow(color: Color.black.opacity(0.20), radius: 28, x: 0, y: 14)
            .shadow(color: Color.black.opacity(0.07), radius: 6, x: 0, y: 3)
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

// MARK: - AI prompt

final class AIPromptState: ObservableObject {
    @Published var text: String = ""
}

struct AIPromptSectionView: View {
    @ObservedObject var state: AIPromptState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $state.text)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Color.white)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 120, idealHeight: 140, maxHeight: 160)

                if state.text.isEmpty {
                    Text("Ask anything…")
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

            Button {
                copyToClipboard()
            } label: {
                HStack {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Copy prompt")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: ToolbarGlass.innerRadius, style: .continuous)
                        .fill(Color.white.opacity(0.16))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: ToolbarGlass.innerRadius, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .disabled(state.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .opacity(state.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)
        }
    }

    private func copyToClipboard() {
        let trimmed = state.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(trimmed, forType: .string)
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

        NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
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
