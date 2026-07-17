//
//  ContentView.swift
//  Marker
//
//  Created by Cillian on 09/07/2026.
//

import SwiftUI
import UniformTypeIdentifiers
import AppKit
import OSLog

private let shortcutLog = OSLog(subsystem: "com.marker.app", category: "shortcut")

// MARK: - Global key monitor

/// A long-lived event monitor that intercepts Cmd+S and routes it to the
/// tab managers for saving.  NSTextView's responder chain swallows Cmd+S
/// (via `saveDocument:`) before the SwiftUI menu system can respond, so
/// we catch it at the event-monitor level instead.
private final class SaveShortcutMonitor: NSObject {
    private var monitor: Any?

    /// Start monitoring for Cmd+S.
    /// - Parameter handler: Called on the main thread when Cmd+S is pressed.
    ///   Return `true` to consume the event, `false` to pass it through.
    func install(handler: @escaping () -> Bool) {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let chars = event.charactersIgnoringModifiers?.lowercased() ?? ""
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if chars == "s", mods == [.command] {
                let consumed = handler()
                return consumed ? nil : event
            }
            return event
        }
    }

    func uninstall() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }

    deinit {
        uninstall()
    }
}

/// Root content view — NavigationSplitView with sidebar file explorer + editor split.
struct ContentView: View {
    @EnvironmentObject private var fileExplorer: FileExplorerService
    @EnvironmentObject private var sessionState: SessionStateService
    @StateObject private var primaryTabs = TabManager()
    @StateObject private var secondaryTabs = TabManager()
    @State private var isSplit = false
    @State private var hasRestoredTabs = false
    @State private var sidebarWidth: CGFloat = 220
    @State private var saveMonitor = SaveShortcutMonitor()
    @AppStorage("windowMaterial") private var windowMaterial: String = "frosted"
    @AppStorage("backgroundOpacity") private var backgroundOpacity: Double = 0.85

    var body: some View {
        NavigationSplitView {
            FileExplorerView(
                service: fileExplorer,
                activeTabId: $primaryTabs.activeTabId,
                openFile: { path in
                    primaryTabs.openFileSmart(at: path)
                },
                openFileInNewTab: { path in
                    primaryTabs.openFile(at: path)
                }
            )
            .scrollContentBackground(.hidden)
            .paneMaterial(isSidebar: true)
            .navigationSplitViewColumnWidth(min: 180, ideal: sidebarWidth, max: 300)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        openDirectoryPanel()
                    } label: {
                        Image(systemName: "folder")
                    }
                    .help("Open Directory (⌘O)")
                }
            }
        } detail: {
            EditorSplitView(
                primaryTabManager: primaryTabs,
                isSplit: $isSplit,
                secondaryTabManager: secondaryTabs
            )
            .background(Color.clear)
            .paneMaterial()
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    splitButton
                        .disabled(primaryTabs.tabs.isEmpty || (primaryTabs.tabs.count < 2 && !isSplit))
                }
                ToolbarItem(placement: .automatic) {
                    newTabButton
                }
                ToolbarItem(placement: .automatic) {
                    saveButton
                }
            }
        }
        .suppressKeyboardShortcuts([
            ("t", [.command]),  // ⌘T — do nothing
        ])
        // Wire session state into tab managers for persistence
        .onAppear {
            primaryTabs.sessionState = sessionState
            secondaryTabs.sessionState = sessionState
            restoreWindowFrame()

            // Install global Cmd+S handler.
            // NSTextView's responder chain swallows Cmd+S (via `saveDocument:`)
            // before the SwiftUI menu can respond, so we intercept at the
            // event-monitor level.
            saveMonitor.install { [primaryTabs, secondaryTabs, fileExplorer] in
                os_log(.debug, log: shortcutLog, "Cmd+S intercepted — dispatching save")
                // We dispatch to the next run-loop tick so the event monitor
                // returns immediately and doesn't block event processing.
                DispatchQueue.main.async {
                    // Keep the security scope reference while the save runs.
                    fileExplorer.retainSecurityScope()
                    defer { fileExplorer.releaseSecurityScope() }
                    
                    let scopedRoot = fileExplorer.scopedURL
                    do {
                        try primaryTabs.saveActiveTab(securityScopedRoot: scopedRoot)
                        os_log(.debug, log: shortcutLog, "primary save succeeded")
                    } catch {
                        os_log(.fault, log: shortcutLog, "primary save failed: %{public}s",
                               error.localizedDescription)
                        SaveErrorAlert.show(error, filename: primaryTabs.activeTab?.title ?? "unknown", sessionState: sessionState)
                    }
                    do {
                        try secondaryTabs.saveActiveTab(securityScopedRoot: scopedRoot)
                        os_log(.debug, log: shortcutLog, "secondary save succeeded")
                    } catch {
                        os_log(.fault, log: shortcutLog, "secondary save failed: %{public}s",
                               error.localizedDescription)
                        SaveErrorAlert.show(error, filename: secondaryTabs.activeTab?.title ?? "unknown", sessionState: sessionState)
                    }
                }
                return true  // consume the event
            }
        }
        .onDisappear {
            saveMonitor.uninstall()
        }
        // Save sidebar width whenever it changes
        .onChange(of: sidebarWidth) { _, newWidth in
            sessionState.saveSidebarWidth(newWidth)
        }
        // Save window frame when the window closes
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { notification in
            guard let window = notification.object as? NSWindow else { return }
            sessionState.saveWindowFrame(window.frame)
        }
        // Listen for menu-bar-triggered actions via NotificationCenter.
        .onReceive(NotificationCenter.default.publisher(for: .markerSave)) { _ in
            os_log(.debug, log: shortcutLog, "menu Cmd+S received — saving via notification")
            fileExplorer.retainSecurityScope()
            defer { fileExplorer.releaseSecurityScope() }
            let scopedRoot = fileExplorer.scopedURL
            do {
                try primaryTabs.saveActiveTab(securityScopedRoot: scopedRoot)
                os_log(.debug, log: shortcutLog, "menu-triggered save succeeded")
            } catch {
                os_log(.fault, log: shortcutLog, "menu-triggered save failed: %{public}s",
                       error.localizedDescription)
                SaveErrorAlert.show(error, filename: primaryTabs.activeTab?.title ?? "unknown", sessionState: sessionState)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .markerCloseTab)) { _ in
            closeActiveTab()
        }
        .onReceive(NotificationCenter.default.publisher(for: .markerNewFile)) { _ in
            primaryTabs.openUntitled()
        }
        .onReceive(NotificationCenter.default.publisher(for: .markerSaveUntitled)) { notification in
            saveUntitledTab(notification.object as? String)
        }
        // When the file tree is populated on launch, restore saved tabs.
        .onReceive(fileExplorer.$tree) { tree in
            guard !hasRestoredTabs, !tree.isEmpty else { return }
            hasRestoredTabs = true
            restoreTabsAndDrafts()
        }
        // Window-level chrome and blur (glass mode via CGS private API)
        .background(WindowAccessor { window in
            configureWindow(window)
        })
    }

    // MARK: - Actions

    private func openDirectoryPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose a directory containing markdown files"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            self.fileExplorer.openDirectory(url)
        }
    }

    private func closeActiveTab() {
        if let id = primaryTabs.activeTabId {
            primaryTabs.closeTab(id)
        }
    }

    /// Show a save panel for an untitled tab.
    private func saveUntitledTab(_ documentId: String?) {
        guard documentId != nil else { return }
        let panel = NSSavePanel()
        panel.title = "Save File"
        panel.nameFieldStringValue = "untitled.md"
        panel.allowedContentTypes = [.plainText, .text, .init(filenameExtension: "md") ?? .plainText]
        panel.canCreateDirectories = true
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            // NSSavePanel returns a security-scoped URL, so we don't need
            // the directory's scoped URL here — the panel's URL handles it.
            do {
                try self.primaryTabs.saveActiveTab(to: url)
                os_log(.debug, log: shortcutLog, "untitled save succeeded to %{public}s", url.path)
            } catch {
                os_log(.fault, log: shortcutLog, "untitled save failed: %{public}s",
                       error.localizedDescription)
                SaveErrorAlert.show(error, filename: "untitled", sessionState: sessionState)
            }
        }
    }

    // MARK: - Window geometry

    /// Restore the window frame on launch.
    private func restoreWindowFrame() {
        let saved = sessionState.loadWindowFrame()
        if saved != .zero {
            DispatchQueue.main.async {
                NSApp.keyWindow?.setFrame(saved, display: true)
            }
        }
        // Restore sidebar width if saved
        if let width = sessionState.loadSidebarWidth() {
            sidebarWidth = width
        }
    }



    // MARK: - Session restore

    /// Restore open tabs and dirty drafts from the last session.
    private func restoreTabsAndDrafts() {
        guard let rootURL = fileExplorer.rootURL else { return }
        guard let (paths, activeDocumentId) = sessionState.loadTabList() else { return }

        sessionState.rootURL = rootURL
        var restoredIds: Set<String> = []

        for relativePath in paths {
            let absolutePath = rootURL.appendingPathComponent(relativePath).path
            let tab = primaryTabs.openFile(at: absolutePath)
            restoredIds.insert(tab.documentId)

            // Check for a draft newer than the source file
            if let draft = sessionState.loadDraft(for: tab.documentId, newerThan: absolutePath) {
                tab.text = draft
                tab.markEdited()
            }
        }

        // Restore the previously active tab by matching on its stable documentId
        if let activeDocumentId,
           let match = primaryTabs.tabs.first(where: { $0.documentId == activeDocumentId }) {
            primaryTabs.activeTabId = match.id
        }

        // Clean orphaned drafts
        sessionState.pruneOrphanedDrafts(keep: restoredIds)
    }

    // MARK: - Toolbar buttons

    @ViewBuilder
    private var splitButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                isSplit.toggle()
            }
        } label: {
            Image(systemName: isSplit ? "rectangle.split.1x2" : "rectangle.split.2x1")
        }
        .help(isSplit ? "Close Split" : "Split View")
    }

    @ViewBuilder
    private var newTabButton: some View {
        Button {
            primaryTabs.openUntitled()
        } label: {
            Image(systemName: "plus")
        }
        .help("New Tab")
    }

    @ViewBuilder
    private var saveButton: some View {
        Button {
            fileExplorer.retainSecurityScope()
            defer { fileExplorer.releaseSecurityScope() }
            do {
                try primaryTabs.saveActiveTab(securityScopedRoot: fileExplorer.scopedURL)
            } catch {
                SaveErrorAlert.show(error, filename: primaryTabs.activeTab?.title ?? "unknown", sessionState: sessionState)
            }
        } label: {
            Image(systemName: "square.and.arrow.down")
        }
        .help("Save")
        .disabled(primaryTabs.activeTab?.isDirty != true)
    }
    // MARK: - Window chrome

    /// Configure window-level properties: titlebar appearance, material, and blur.
    /// Called every time the window material or opacity changes.
    private func configureWindow(_ window: NSWindow?) {
        guard let window else { return }

        window.titlebarSeparatorStyle = .none
        window.isMovableByWindowBackground = true

        switch windowMaterial {
        case "opaque":
            window.isOpaque = true
            window.backgroundColor = .windowBackgroundColor
            WindowBlur.removeGlassBlur(from: window)

        case "glass":
            window.isOpaque = false
            // Near-transparent white lets the window-server compositor apply
            // the glass blur against content behind the window.
            window.backgroundColor = NSColor.white.withAlphaComponent(0.001)
            WindowBlur.applyGlassBlur(to: window)

        default: // "frosted"
            window.isOpaque = false
            window.backgroundColor = NSColor.white.withAlphaComponent(0.001)
            WindowBlur.removeGlassBlur(from: window)
        }
    }
}

// MARK: - Save error alert helper

/// Shows a non-modal alert when saving a file fails.
/// Used as a visible error indicator since `try?` previously swallowed all errors.
private enum SaveErrorAlert {
    /// Cocoa error code for "You don't have permission to save the file".
    /// A permission denial during a save almost always means the restored
    /// security-scoped bookmark was created read-only — clearing the stored
    /// bookmark lets the user re-open the directory once (Cmd+O) to persist a
    /// proper read-write bookmark, after which saves work on every launch.
    private static let nsFileWriteNoPermissionError = 513

    static func show(_ error: Error, filename: String, sessionState: SessionStateService? = nil) {
        // Build a detailed error description including the NSError chain
        let nsError = error as NSError
        let detail: String
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            detail = "\(error.localizedDescription)\n\nUnderlying: \(underlying.localizedDescription) (\(underlying.domain) error \(underlying.code))"
        } else {
            detail = error.localizedDescription
        }
        os_log(.fault, log: shortcutLog, "SaveErrorAlert: %{public}s — %{public}s | domain=%{public}s code=%ld",
               filename, error.localizedDescription, nsError.domain, nsError.code)

        // Self-heal: if the failure is a sandbox permission denial, drop the
        // stale directory bookmark so a future launch does not restore a
        // read-only (unwritable) security scope.
        let isPermissionDenied = nsError.code == nsFileWriteNoPermissionError
            || (nsError.userInfo[NSUnderlyingErrorKey] as? NSError)?.code == nsFileWriteNoPermissionError
        if isPermissionDenied {
            os_log(.error, log: shortcutLog, "SaveErrorAlert: permission denied — clearing stale directory bookmark")
            sessionState?.clearDirectoryBookmark()
        }

        DispatchQueue.main.async {
            guard let window = NSApp.keyWindow else { return }
            let alert = NSAlert()
            alert.messageText = "Failed to save \"\(filename)\""
            alert.informativeText = detail
            alert.alertStyle = .critical
            alert.addButton(withTitle: "OK")
            alert.beginSheetModal(for: window)
        }
    }
}

// MARK: - Pane material modifier

/// Applies the user's selected window material (frosted/glass/opaque) to a pane.
/// Each pane gets its own `VisualEffectView` with `state: .active` so the blur
/// stays visible even when the window is not the key window (matching Scrap's behavior).
struct PaneMaterialModifier: ViewModifier {
    @AppStorage("windowMaterial") private var windowMaterial: String = "frosted"
    @AppStorage("backgroundOpacity") private var backgroundOpacity: Double = 0.85

    /// If true, this pane is the sidebar (and needs special handling in glass mode
    /// to prevent the NavigationSplitView's column-level effects from dimming).
    var isSidebar: Bool = false

    func body(content: Content) -> some View {
        ZStack {
            Group {
                switch windowMaterial {
                case "glass":
                    if isSidebar {
                        // Sidebar in glass mode: uses VisualEffectView with .active
                        // state so the sidebar never dims when the window loses focus.
                        // The .sidebar material matches the system sidebar appearance
                        // while compositing over the window-level CGS blur.
                        VisualEffectView(
                            material: .sidebar,
                            blending: .behindWindow,
                            state: .active
                        )
                    } else {
                        // Detail/editor in glass mode: transparent with tint overlay.
                        // The window-level CGS blur (set via WindowBlur.applyGlassBlur
                        // in configureWindow) provides the glass effect. No
                        // VisualEffectView here — that would double-blur.
                        Color.clear
                            .overlay(
                                Color(nsColor: .windowBackgroundColor)
                                    .opacity(backgroundOpacity)
                            )
                    }

                case "opaque":
                    Color(nsColor: .windowBackgroundColor)

                default: // "frosted"
                    VisualEffectView(
                        material: .underWindowBackground,
                        blending: .behindWindow,
                        state: .active
                    )
                }
            }
            .ignoresSafeArea()

            content
        }
    }
}

extension View {
    /// Wraps the view in a material-aware pane background matching the current
    /// window material setting. The effect stays active when the window loses focus.
    /// - Parameter isSidebar: Pass `true` for the sidebar pane to get special
    ///   handling in glass mode (prevents NavigationSplitView column dimming).
    func paneMaterial(isSidebar: Bool = false) -> some View {
        modifier(PaneMaterialModifier(isSidebar: isSidebar))
    }
}

#Preview {
    ContentView()
        .environmentObject(FileExplorerService())
}
