//
//  FinderFoldersFeature.swift
//  cursor-toolbar
//

import AppKit
import SwiftUI

enum FolderShortcut: String, CaseIterable, Identifiable {
    case documents
    case downloads
    case library

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .documents: "doc.text"
        case .downloads: "arrow.down.circle"
        case .library: "books.vertical"
        }
    }

    var title: String {
        switch self {
        case .documents: "Documents"
        case .downloads: "Downloads"
        case .library: "Library"
        }
    }

    var url: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        switch self {
        case .documents:
            return home.appendingPathComponent("Documents", isDirectory: true)
        case .downloads:
            return home.appendingPathComponent("Downloads", isDirectory: true)
        case .library:
            return home.appendingPathComponent("Library", isDirectory: true)
        }
    }

    func openInFinder() {
        NSWorkspace.shared.open(url)
    }
}

struct FinderFoldersColumn: View {
    var body: some View {
        VStack(spacing: 10) {
            ForEach(FolderShortcut.allCases) { folder in
                FolderAccessRow(folder: folder)
            }
        }
    }
}

private struct FolderAccessRow: View {
    let folder: FolderShortcut

    var body: some View {
        Button {
            folder.openInFinder()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: folder.systemImage)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.88))
                    .frame(width: 22, alignment: .center)
                Text(folder.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.white)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.42))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: ToolbarGlass.innerRadius, style: .continuous)
                    .fill(Color.black.opacity(0.24))
            )
            .overlay(
                RoundedRectangle(cornerRadius: ToolbarGlass.innerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
