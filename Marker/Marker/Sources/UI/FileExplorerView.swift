//
//  FileExplorerView.swift
//  Marker
//
//  Created by Cillian on 09/07/2026.
//

import SwiftUI

/// Sidebar that lists markdown/text files in a folder tree.
struct FileExplorerView: View {
    @ObservedObject var service: FileExplorerService
    @Binding var activeTabId: String?
    var openFile: (String) -> Void
    var openFileInNewTab: ((String) -> Void)?

    @State private var selectedFileId: String?
    @State private var expandedNodeIDs: Set<String> = []

    var body: some View {
        List(selection: $selectedFileId) {
            if service.tree.isEmpty {
                emptyState
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } else {
                ForEach(service.tree) { node in
                    FileNodeRow(
                        node: node,
                        expandedIDs: $expandedNodeIDs,
                        selectedID: $selectedFileId,
                        openFile: openFile
                    )
                }
            }
        }
        .listStyle(.sidebar)
        .onChange(of: selectedFileId) { _, newId in
            guard let id = newId, !id.isEmpty else { return }
            // Cmd+Click → always open in a new tab
            if NSApp.currentEvent?.modifierFlags.contains(.command) == true {
                (openFileInNewTab ?? openFile)(id)
            } else {
                openFile(id)
            }
        }
        // Show the root directory name as the sidebar header when available.
        .safeAreaInset(edge: .top, spacing: 0) {
            if let root = service.rootURL {
                HStack {
                    Image(systemName: "folder")
                        .foregroundStyle(.secondary)
                    Text(root.lastPathComponent)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial)
            }
        }
    }

    // MARK: - Empty state

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 24))
                .foregroundStyle(.tertiary)
            Text(service.rootURL == nil
                ? "Open a directory to start"
                : "No markdown files found"
            )
            .foregroundStyle(.secondary)
            .font(.subheadline)
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 40)
    }
}

// MARK: - Tree row

/// Recursive row: shows a `DisclosureGroup` for directories, a plain row for files.
private struct FileNodeRow: View {
    let node: FileNode
    @Binding var expandedIDs: Set<String>
    @Binding var selectedID: String?
    let openFile: (String) -> Void

    var body: some View {
        if node.isDirectory {
            DisclosureGroup(
                isExpanded: Binding(
                    get: { expandedIDs.contains(node.id) },
                    set: { isExpanded in
                        if isExpanded { expandedIDs.insert(node.id) } else { expandedIDs.remove(node.id) }
                    }
                ),
                content: {
                    ForEach(node.children ?? []) { child in
                        FileNodeRow(
                            node: child,
                            expandedIDs: $expandedIDs,
                            selectedID: $selectedID,
                            openFile: openFile
                        )
                    }
                },
                label: {
                    HStack(spacing: 4) {
                        Image(systemName: "folder")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                        Text(node.name)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            )
        } else {
            // File row
            HStack(spacing: 6) {
                Image(systemName: iconName(for: node))
                    .foregroundStyle(iconColor(for: node))
                    .font(.caption)
                Text(node.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .font(.subheadline)
            }
            .padding(.vertical, 2)
            .tag(node.id)
            .listRowSeparator(.hidden)
        }
    }

    private func iconName(for node: FileNode) -> String {
        switch node.url.pathExtension.lowercased() {
        case "md", "markdown": return "doc.text"
        case "txt": return "doc.plaintext"
        default: return "doc"
        }
    }

    private func iconColor(for node: FileNode) -> Color {
        switch node.url.pathExtension.lowercased() {
        case "md", "markdown": return .blue
        case "txt": return .secondary
        default: return .secondary
        }
    }
}
