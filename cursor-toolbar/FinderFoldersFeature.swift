//
//  FinderFoldersFeature.swift
//  cursor-toolbar
//

import AppKit
import SwiftUI

struct FinderFoldersColumn: View {
    private static let home = FileManager.default.homeDirectoryForCurrentUser

    var body: some View {
        VStack(spacing: 10) {
            FolderAccessRow(
                title: "Documents",
                systemImage: "doc.text",
                url: Self.home.appendingPathComponent("Documents", isDirectory: true)
            )
            FolderAccessRow(
                title: "Downloads",
                systemImage: "arrow.down.circle",
                url: Self.home.appendingPathComponent("Downloads", isDirectory: true)
            )
            FolderAccessRow(
                title: "Library",
                systemImage: "books.vertical",
                url: Self.home.appendingPathComponent("Library", isDirectory: true)
            )
        }
    }
}

private struct FolderAccessRow: View {
    let title: String
    let systemImage: String
    let url: URL

    var body: some View {
        Button {
            NSWorkspace.shared.open(url)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.88))
                    .frame(width: 22, alignment: .center)
                Text(title)
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
