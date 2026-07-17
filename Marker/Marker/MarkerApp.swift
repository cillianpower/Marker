//
//  MarkerApp.swift
//  Marker
//
//  Created by Cillian on 09/07/2026.
//

import SwiftUI

@main
struct MarkerApp: App {
    @StateObject private var fileExplorer = FileExplorerService()
    @StateObject private var sessionState = SessionStateService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(fileExplorer)
                .environmentObject(sessionState)
                .onAppear {
                    restoreLastDirectory()
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New File") {
                    NotificationCenter.default.post(name: .markerNewFile, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)

                Divider()

                Button("Open Directory…") {
                    openDirectoryPanel()
                }
                .keyboardShortcut("o", modifiers: .command)
            }

            CommandGroup(replacing: .saveItem) {
                Button("Save") {
                    NotificationCenter.default.post(name: .markerSave, object: nil)
                }
                .keyboardShortcut("s", modifiers: .command)

                Button("Close Tab") {
                    NotificationCenter.default.post(name: .markerCloseTab, object: nil)
                }
                .keyboardShortcut("w", modifiers: .command)
            }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)

        // ── Settings ──
        Settings {
            SettingsView()
        }
    }

    /// Attempt to restore the last opened directory from its security-scoped bookmark.
    ///
    /// A persisted bookmark can resolve to a *read-only* scope (for example one
    /// created with `.securityScopeAllowOnlyReadAccess`).  Read access alone is
    /// enough to populate the sidebar, so the defect is invisible until the
    /// first save fails.  To avoid stranding the user on a read-only scope, we
    /// probe write access immediately after restoring and, if it fails, discard
    /// the stale bookmark and ask the user to re-select the folder — which
    /// yields a fresh read-write security scope.
    private func restoreLastDirectory() {
        guard fileExplorer.rootURL == nil else { return }
        guard let url = sessionState.loadDirectoryBookmark() else { return }
        // Wire up sessionState so FileExplorerService can persist future bookmarks.
        fileExplorer.sessionState = sessionState

        guard sessionState.canWriteToDirectory(url) else {
            // Read-only (or otherwise unwritable) restored scope — drop it and
            // let the user pick the folder again to get a proper read-write scope.
            sessionState.clearDirectoryBookmark()
            fileExplorer.stopAccess()
            openDirectoryPanel()
            return
        }

        fileExplorer.openDirectory(url)
    }

    private func openDirectoryPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose a directory containing markdown files"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            // Wire up sessionState before opening so the bookmark gets saved.
            if self.fileExplorer.sessionState == nil {
                self.fileExplorer.sessionState = self.sessionState
            }
            // Security-scoped URL: maintain access across the app's lifetime.
            // Keep the security scope active for the app's lifetime
            // (or until a new directory is opened).
            self.fileExplorer.openDirectory(url)
        }
    }
}

extension Notification.Name {
    static let markerSave = Notification.Name("markerSave")
    static let markerCloseTab = Notification.Name("markerCloseTab")
    static let markerNewFile = Notification.Name("markerNewFile")
    static let markerSaveUntitled = Notification.Name("markerSaveUntitled")
    static let markerOpenDirectory = Notification.Name("markerOpenDirectory")
}
