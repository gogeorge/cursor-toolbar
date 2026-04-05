//
//  ToolbarContentView.swift
//  cursor-toolbar
//

import AppKit
import Combine
import SwiftUI

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
                                dashboardAddModulePanel(
                                    gap: iconToPanelSpacing,
                                    cell: Self.dashboardCellSize,
                                    itemCount: flow.dashboardModulesToAdd.count
                                )
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

    /// Vertical size of the “Add to dashboard” palette from layout constants (matches `dashboardAddPaletteList` padding and rows).
    private static func addPanelIdealHeight(itemCount: Int) -> CGFloat {
        let padV = CGFloat(12 + 12)
        let titleLine: CGFloat = 20
        let titleToList: CGFloat = 10
        let rowHeight: CGFloat = 44
        let rowGap: CGFloat = 8
        let listH = CGFloat(itemCount) * rowHeight + CGFloat(max(0, itemCount - 1)) * rowGap
        return padV + titleLine + titleToList + listH
    }

    /// Narrow glass column for modules not yet on the dashboard (smaller than grid cells).
    private func dashboardAddModulePanel(gap: CGFloat, cell: CGFloat, itemCount: Int) -> some View {
        let r = ToolbarGlass.dashboardCellRadius
        let shape = RoundedRectangle(cornerRadius: r, style: .continuous)
        let addPanelWidth: CGFloat = 212
        let pad = EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12)
        let maxPanelHeight = cell * 2 + gap
        let idealContentHeight = Self.addPanelIdealHeight(itemCount: itemCount)
        let list = dashboardAddPaletteList()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(pad)
        return Group {
            if idealContentHeight <= maxPanelHeight {
                list
                    .frame(width: addPanelWidth, alignment: .leading)
            } else {
                ScrollView {
                    list
                }
                .scrollIndicators(.hidden)
                .frame(width: addPanelWidth, height: maxPanelHeight)
            }
        }
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
                                .lineLimit(1)
                                .truncationMode(.tail)
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
