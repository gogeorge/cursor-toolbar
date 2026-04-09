//
//  ToolbarFlowState.swift
//  cursor-toolbar
//

import Combine
import Foundation

enum ToolbarSheetMode: Equatable {
    case collapsed
    case standardFolders
    case aiPrompt
    case notes
    case clipboard
    case full
}

/// Tiles that can appear on the full dashboard (order is preserved).
enum DashboardModule: String, CaseIterable, Codable, Identifiable {
    case folders
    case notes
    case aiPrompt
    case clipboard
    case commands
    case aiWidgetBuilder

    var id: String { rawValue }

    var panelTitle: String {
        switch self {
        case .folders: "Folders"
        case .notes: "Notes"
        case .aiPrompt: "AI prompt"
        case .clipboard: "Clipboard"
        case .commands: "Commands"
        case .aiWidgetBuilder: "AI widget builder"
        }
    }
}

// MARK: - Widget Blueprint (JSON-based runtime rendering)

struct WidgetStyle: Codable, Equatable {
    var fontSize: CGFloat?
    var fontWeight: String?      // "regular", "medium", "semibold", "bold", "heavy"
    var opacity: Double?
    var alignment: String?       // "leading", "center", "trailing"
    var spacing: CGFloat?
    var monospacedDigits: Bool?
    var color: String?           // "white", "secondary", "accent"
}

struct WidgetElement: Codable, Equatable, Identifiable {
    var id: String?
    var type: String             // "text","liveTime","liveDate","spacer","divider","vstack","hstack","systemInfo","progressRing","image","apiText"
    var content: String?         // static text, date format, SF Symbol name, system info key
    var style: WidgetStyle?
    var children: [WidgetElement]?

    // apiText-specific fields
    var dataSourceId: String?
    var keyPath: String?         // dot-path into JSON response
    var prefix: String?
    var suffix: String?
    var fallback: String?
}

struct WidgetDataSource: Codable, Equatable {
    let id: String
    let url: String
    var method: String?          // "GET" (default)
    var headers: [String: String]?
    var refreshIntervalSeconds: Double?
}

struct WidgetBlueprint: Codable, Equatable {
    var dataSources: [WidgetDataSource]?
    var elements: [WidgetElement]
}

struct GeneratedWidgetDefinition: Codable, Identifiable, Equatable {
    let id: String
    let title: String
    let requestText: String
    let generatedSummary: String
    var blueprint: WidgetBlueprint?
}

enum DashboardDisplayItem: Identifiable, Equatable {
    case builtIn(DashboardModule)
    case generated(GeneratedWidgetDefinition)

    var id: String {
        switch self {
        case .builtIn(let module): return "builtin:\(module.rawValue)"
        case .generated(let widget): return "generated:\(widget.id)"
        }
    }

    var panelTitle: String {
        switch self {
        case .builtIn(let module): return module.panelTitle
        case .generated(let widget): return widget.title
        }
    }
}

final class ToolbarFlowState: ObservableObject {
    @Published var sheetMode: ToolbarSheetMode = .collapsed
    @Published var isPanelVisible: Bool = false
    /// Home-screen style: tiles wiggle and show remove badges.
    @Published var isEditingDashboard: Bool = false
    /// Shown modules in left-to-right, top-to-bottom order. Commands is omitted by default.
    @Published var dashboardModules: [DashboardModule] = [.folders, .notes, .aiPrompt, .clipboard]
    /// Runtime-generated widgets that can be added without app restart.
    @Published var generatedWidgets: [GeneratedWidgetDefinition] = []
    @Published var dashboardGeneratedWidgetIDs: [String] = []

    private let dashboardKey = "toolbar_dashboard_modules_v1"
    private let generatedWidgetsKey = "toolbar_generated_widgets_v1"
    private let dashboardGeneratedWidgetIDsKey = "toolbar_dashboard_generated_widget_ids_v1"
    /// Snapshot when entering dashboard edit mode; used to discard changes on cancel.
    private var dashboardModulesSnapshot: [DashboardModule]?
    private var dashboardGeneratedWidgetIDsSnapshot: [String]?

    var isGlassActive: Bool { sheetMode != .collapsed }

    init() {
        loadDashboardModules()
        loadGeneratedWidgets()
        loadDashboardGeneratedWidgetIDs()
    }

    func reset() {
        sheetMode = .collapsed
        isEditingDashboard = false
        dashboardModulesSnapshot = nil
        dashboardGeneratedWidgetIDsSnapshot = nil
    }

    func toggleStandardFolders() {
        switch sheetMode {
        case .standardFolders: sheetMode = .collapsed
        case .full: sheetMode = .standardFolders
        default: sheetMode = .standardFolders
        }
    }

    func toggleAIPrompt() {
        switch sheetMode {
        case .aiPrompt: sheetMode = .collapsed
        case .full: sheetMode = .aiPrompt
        default: sheetMode = .aiPrompt
        }
    }

    func toggleNotes() {
        switch sheetMode {
        case .notes: sheetMode = .collapsed
        case .full: sheetMode = .notes
        default: sheetMode = .notes
        }
    }

    func toggleClipboard() {
        switch sheetMode {
        case .clipboard: sheetMode = .collapsed
        case .full: sheetMode = .clipboard
        default: sheetMode = .clipboard
        }
    }

    func toggleFullExpand() {
        switch sheetMode {
        case .full: sheetMode = .collapsed
        default: sheetMode = .full
        }
    }

    func toggleDashboardEditMode() {
        if isEditingDashboard {
            dashboardModulesSnapshot = nil
            dashboardGeneratedWidgetIDsSnapshot = nil
            isEditingDashboard = false
            saveDashboardModules()
            saveDashboardGeneratedWidgetIDs()
        } else {
            dashboardModulesSnapshot = dashboardModules
            dashboardGeneratedWidgetIDsSnapshot = dashboardGeneratedWidgetIDs
            isEditingDashboard = true
        }
    }

    /// Reverts dashboard layout to when edit mode started and exits edit mode.
    func cancelDashboardEditDiscardingChanges() {
        guard isEditingDashboard else { return }
        if let snap = dashboardModulesSnapshot {
            dashboardModules = snap
        }
        if let snap = dashboardGeneratedWidgetIDsSnapshot {
            dashboardGeneratedWidgetIDs = snap
        }
        dashboardModulesSnapshot = nil
        dashboardGeneratedWidgetIDsSnapshot = nil
        isEditingDashboard = false
        saveDashboardModules()
        saveDashboardGeneratedWidgetIDs()
    }

    /// Leaving full layout (e.g. opening a single panel) exits jiggle mode.
    func cancelDashboardEdit() {
        guard isEditingDashboard else { return }
        if let snap = dashboardModulesSnapshot {
            dashboardModules = snap
        }
        if let snap = dashboardGeneratedWidgetIDsSnapshot {
            dashboardGeneratedWidgetIDs = snap
        }
        dashboardModulesSnapshot = nil
        dashboardGeneratedWidgetIDsSnapshot = nil
        isEditingDashboard = false
        saveDashboardModules()
        saveDashboardGeneratedWidgetIDs()
    }

    func removeDashboardModule(_ module: DashboardModule) {
        dashboardModules.removeAll { $0 == module }
        saveDashboardModules()
    }

    func addDashboardModule(_ module: DashboardModule) {
        guard !dashboardModules.contains(module) else { return }
        dashboardModules.append(module)
        saveDashboardModules()
    }

    func removeGeneratedWidgetFromDashboard(_ widgetID: String) {
        dashboardGeneratedWidgetIDs.removeAll { $0 == widgetID }
        saveDashboardGeneratedWidgetIDs()
    }

    func addGeneratedWidgetToDashboard(_ widgetID: String) {
        guard generatedWidgets.contains(where: { $0.id == widgetID }) else { return }
        guard !dashboardGeneratedWidgetIDs.contains(widgetID) else { return }
        dashboardGeneratedWidgetIDs.append(widgetID)
        saveDashboardGeneratedWidgetIDs()
    }

    func registerGeneratedWidget(_ widget: GeneratedWidgetDefinition) {
        generatedWidgets.removeAll { $0.id == widget.id }
        generatedWidgets.append(widget)
        saveGeneratedWidgets()
    }

    func deleteGeneratedWidget(_ widgetID: String) {
        removeGeneratedWidgetFromDashboard(widgetID)
        generatedWidgets.removeAll { $0.id == widgetID }
        saveGeneratedWidgets()
    }

    var dashboardModulesToAdd: [DashboardModule] {
        DashboardModule.allCases.filter { !dashboardModules.contains($0) }
    }

    var dashboardGeneratedWidgetsToAdd: [GeneratedWidgetDefinition] {
        generatedWidgets.filter { !dashboardGeneratedWidgetIDs.contains($0.id) }
    }

    var dashboardDisplayItems: [DashboardDisplayItem] {
        var items = dashboardModules.map { DashboardDisplayItem.builtIn($0) }
        let generatedShown = generatedWidgets.filter { dashboardGeneratedWidgetIDs.contains($0.id) }
        items.append(contentsOf: generatedShown.map { DashboardDisplayItem.generated($0) })
        return items
    }

    private func loadDashboardModules() {
        guard let data = UserDefaults.standard.data(forKey: dashboardKey),
              let decoded = try? JSONDecoder().decode([DashboardModule].self, from: data)
        else { return }
        let allowed = Set(DashboardModule.allCases)
        dashboardModules = decoded.filter { allowed.contains($0) }
    }

    private func saveDashboardModules() {
        guard let data = try? JSONEncoder().encode(dashboardModules) else { return }
        UserDefaults.standard.set(data, forKey: dashboardKey)
    }

    private func loadGeneratedWidgets() {
        guard let data = UserDefaults.standard.data(forKey: generatedWidgetsKey),
              let decoded = try? JSONDecoder().decode([GeneratedWidgetDefinition].self, from: data)
        else { return }
        generatedWidgets = decoded
    }

    private func saveGeneratedWidgets() {
        guard let data = try? JSONEncoder().encode(generatedWidgets) else { return }
        UserDefaults.standard.set(data, forKey: generatedWidgetsKey)
    }

    private func loadDashboardGeneratedWidgetIDs() {
        guard let data = UserDefaults.standard.data(forKey: dashboardGeneratedWidgetIDsKey),
              let decoded = try? JSONDecoder().decode([String].self, from: data)
        else { return }
        dashboardGeneratedWidgetIDs = decoded
    }

    private func saveDashboardGeneratedWidgetIDs() {
        guard let data = try? JSONEncoder().encode(dashboardGeneratedWidgetIDs) else { return }
        UserDefaults.standard.set(data, forKey: dashboardGeneratedWidgetIDsKey)
    }
}
