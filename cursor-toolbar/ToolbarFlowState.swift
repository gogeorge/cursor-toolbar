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

final class ToolbarFlowState: ObservableObject {
    @Published var sheetMode: ToolbarSheetMode = .collapsed
    @Published var isPanelVisible: Bool = false

    var isGlassActive: Bool { sheetMode != .collapsed }

    func reset() {
        sheetMode = .collapsed
        // isPanelVisible is managed by ToolbarCoordinator.
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
}
