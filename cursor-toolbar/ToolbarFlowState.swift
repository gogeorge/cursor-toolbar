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

    var id: String { rawValue }

    var panelTitle: String {
        switch self {
        case .folders: "Folders"
        case .notes: "Notes"
        case .aiPrompt: "AI prompt"
        case .clipboard: "Clipboard"
        case .commands: "Commands"
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

    private let dashboardKey = "toolbar_dashboard_modules_v1"

    var isGlassActive: Bool { sheetMode != .collapsed }

    init() {
        loadDashboardModules()
    }

    func reset() {
        sheetMode = .collapsed
        isEditingDashboard = false
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
        isEditingDashboard.toggle()
        if !isEditingDashboard {
            saveDashboardModules()
        }
    }

    /// Leaving full layout (e.g. opening a single panel) exits jiggle mode.
    func cancelDashboardEdit() {
        guard isEditingDashboard else { return }
        isEditingDashboard = false
        saveDashboardModules()
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

    var dashboardModulesToAdd: [DashboardModule] {
        DashboardModule.allCases.filter { !dashboardModules.contains($0) }
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
}
