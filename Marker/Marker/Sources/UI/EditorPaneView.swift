//
//  EditorPaneView.swift
//  Marker
//
//  Created by Cillian on 09/07/2026.
//

import SwiftUI
import MarkdownEngine

/// One side of the editor split. Contains a tab bar and the active editor.
struct EditorPaneView: View {
    @ObservedObject var tabManager: TabManager

    private let config: MarkdownEditorConfiguration = {
        var config = MarkdownEditorConfiguration()
        config.theme = .default
        config.textInsets = TextInsets(horizontal: 20, vertical: 8)
        config.safeAreaInsets = SafeAreaInsets(top: 4, leading: 0, trailing: 0, bottom: 4)
        return config
    }()

    var body: some View {
        VStack(spacing: 0) {
            if !tabManager.tabs.isEmpty {
                TabBarView(
                    tabs: tabManager.tabs,
                    activeTabId: $tabManager.activeTabId,
                    closeTab: { tabManager.closeTab($0) }
                )
                .dividerBelow()
            }

            if let tab = tabManager.activeTab {
                EditorTabContentView(tab: tab, config: config)
            } else {
                emptyState
                    // Ensure the empty state doesn't overlap window traffic lights
                    // when no tab bar is visible.
                    .padding(.top, tabManager.tabs.isEmpty ? 8 : 0)
            }
        }
        .background(Color.clear)
        .suppressKeyboardShortcuts([
            ("t", .control)  // Ctrl+T — suppress transpose characters
        ])
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text("No file open")
                .foregroundStyle(.secondary)
            Text("Select a file from the sidebar or press ⌘O")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The actual editor for a single tab. Tracks text edits for dirty state.
/// Each document gets its own NSViewRepresentable via `.id(tab.documentId)`,
/// preventing the engine's coordinator from being recycled across different tabs
/// and avoiding content bleed from stale text bindings.
private struct EditorTabContentView: View {
    @ObservedObject var tab: Tab
    let config: MarkdownEditorConfiguration

    var body: some View {
        NativeTextViewWrapper(
            text: $tab.text,
            configuration: config,
            fontName: "SF Pro",
            fontSize: 16,
            documentId: tab.documentId,
            isEditable: true
        )
        .id(tab.documentId)
        .onChange(of: tab.text) { _, _ in
            tab.markEdited()
        }
    }
}

// MARK: - Divider helper

private struct DividerModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .overlay(
                Rectangle()
                    .frame(height: 1)
                    .foregroundStyle(.separator.opacity(0.5)),
                alignment: .bottom
            )
    }
}

extension View {
    fileprivate func dividerBelow() -> some View {
        modifier(DividerModifier())
    }
}
