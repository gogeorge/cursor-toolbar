//
//  ToolbarFlowState.swift
//  cursor-toolbar
//

import Combine
import Foundation

enum ToolbarSheetMode: Equatable {
    case collapsed
    case notes
    case clipboard
    case full
}

final class ToolbarFlowState: ObservableObject {
    @Published var sheetMode: ToolbarSheetMode = .collapsed

    var isGlassActive: Bool { sheetMode != .collapsed }

    func reset() {
        sheetMode = .collapsed
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
