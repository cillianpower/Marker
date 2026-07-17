//
//  TabManager.swift
//  Marker
//
//  Created by Cillian on 09/07/2026.
//

import Foundation
import Combine
import OSLog

private let tabManagerLog = OSLog(subsystem: "com.marker.app", category: "tab-manager")

/// Manages the open-editor-tab lifecycle.
final class TabManager: ObservableObject {
    @Published var tabs: [Tab] = []
    @Published var activeTabId: String?

    /// The currently active tab, if any.
    var activeTab: Tab? {
        activeTabId.flatMap { id in tabs.first { $0.id == id } }
    }

    /// Session state persistence (tab list, drafts).
    /// Injected from the app-level owner.
    weak var sessionState: SessionStateService?

    /// Debounce timer for draft snapshots.
    private var draftDebounceTimer: DispatchSourceTimer?
    private let draftDebounceQueue = DispatchQueue(label: "com.marker.draft-debounce", qos: .utility)

    // MARK: - Initialization

    init(sessionState: SessionStateService? = nil) {
        self.sessionState = sessionState
    }

    deinit {
        draftDebounceTimer?.cancel()
    }

    // MARK: - Tab lifecycle

    /// Open a file, reusing the active tab if it has no unsaved edits.
    /// Creates a new tab only when the active tab has dirty changes.
    @discardableResult
    func openFileSmart(at path: String) -> Tab {
        let resolved = (path as NSString).standardizingPath

        // Already open in a tab — just switch to it
        if let existing = tabs.first(where: { $0.path == resolved }) {
            activeTabId = existing.id
            return existing
        }

        // Active tab has no unsaved edits — reuse it with the new file
        if let active = activeTab, !active.isDirty {
            active.replaceContents(withFileAt: resolved)
            return active
        }

        // Otherwise create a new tab
        let tab = Tab(path: resolved)
        tabs.append(tab)
        activeTabId = tab.id
        persistTabList()
        return tab
    }

    /// Open a file in a tab. If already open, switch to it.
    @discardableResult
    func openFile(at path: String) -> Tab {
        let resolved = (path as NSString).standardizingPath
        // Reuse existing tab for this path
        if let existing = tabs.first(where: { $0.path == resolved }) {
            activeTabId = existing.id
            return existing
        }
        let tab = Tab(path: resolved)
        tabs.append(tab)
        activeTabId = tab.id
        persistTabList()
        return tab
    }

    /// Open an untitled scratch tab.
    @discardableResult
    func openUntitled() -> Tab {
        let tab = Tab(path: nil)
        tabs.append(tab)
        activeTabId = tab.id
        persistTabList()
        return tab
    }

    /// Close a tab by id.
    func closeTab(_ id: String) {
        guard let idx = tabs.firstIndex(where: { $0.id == id }) else { return }
        let wasActive = activeTabId == id
        let tab = tabs[idx]

        // Save draft before removing if dirty
        if tab.isDirty {
            sessionState?.saveDraft(tab.text, for: tab.documentId)
        }

        tabs.remove(at: idx)
        if wasActive {
            if idx < tabs.count {
                activeTabId = tabs[idx].id
            } else {
                activeTabId = tabs.last?.id
            }
        }

        // Persist updated tab list
        persistTabList()
    }

    /// Close all tabs.
    func closeAll() {
        // Save drafts for any dirty tabs before removing
        for tab in tabs where tab.isDirty {
            sessionState?.saveDraft(tab.text, for: tab.documentId)
        }
        tabs.removeAll()
        activeTabId = nil
        sessionState?.clearTabState()
    }

    /// Save the active tab.
    /// - Parameters:
    ///   - securityScopedRoot: Root directory URL with an active security scope.
    ///     Passed through to SavePipeline so the scope is asserted at write time.
    /// - Throws: File write errors.
    /// - Returns: `true` if saved, `false` if the tab has no path (caller should present save panel).
    @discardableResult
    func saveActiveTab(securityScopedRoot: URL? = nil) throws -> Bool {
        guard let tab = activeTab else {
            os_log(.debug, log: tabManagerLog, "saveActiveTab: no active tab")
            return true
        }
        os_log(.debug, log: tabManagerLog, "saveActiveTab: title=%{public}s path=%{public}s dirty=%{public}s",
               tab.title, tab.path ?? "nil", "\(tab.isDirty)")
        guard try tab.save(securityScopedRoot: securityScopedRoot) else {
            // Untitled tab — post notification so the view layer shows a save panel
            NotificationCenter.default.post(name: .markerSaveUntitled, object: tab.documentId)
            return false
        }
        // Delete draft on successful save
        sessionState?.deleteDraft(for: tab.documentId)
        persistTabList()
        return true
    }

    /// Save the active tab to a specific URL (used after save panel).
    func saveActiveTab(to url: URL, securityScopedRoot: URL? = nil) throws {
        guard let tab = activeTab else { return }
        try tab.save(to: url, securityScopedRoot: securityScopedRoot)
        sessionState?.deleteDraft(for: tab.documentId)
        persistTabList()
    }

    /// Mark the active tab as having been edited.
    func markActiveTabEdited() {
        activeTab?.markEdited()
    }

    // MARK: - Debounced draft snapshot

    /// Schedule a debounced draft snapshot for the given tab.
    /// Call this when a tab's text changes and it's dirty.
    func scheduleDraftSnapshot(for tab: Tab) {
        draftDebounceTimer?.cancel()

        let timer = DispatchSource.makeTimerSource(queue: draftDebounceQueue)
        timer.schedule(deadline: .now() + 0.5, repeating: .never, leeway: .milliseconds(100))
        timer.setEventHandler { [weak self, weak tab] in
            guard let self, let tab, tab.isDirty else { return }
            self.sessionState?.saveDraft(tab.text, for: tab.documentId)
        }
        timer.resume()
        draftDebounceTimer = timer
    }

    // MARK: - Tab list persistence

    /// Persist the current tab list and active tab ID.
    func persistTabList() {
        sessionState?.saveTabList(tabs, activeId: activeTabId)
    }
}
