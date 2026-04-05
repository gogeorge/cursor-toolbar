//
//  cursor_toolbarApp.swift
//  cursor-toolbar
//

import SwiftUI

@main
struct cursor_toolbarApp: App {
    private let coordinator = ToolbarCoordinator()

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
