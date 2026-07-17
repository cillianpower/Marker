//
//  SessionStateService.swift
//  Marker
//
//  Created by Cillian on 09/07/2026.
//

import Foundation
import Combine
import AppKit

// MARK: - Tab serialization model

/// Codable representation of an open tab for persistence.
private struct PersistedTab: Codable {
    let path: String        // relative to root directory
    let title: String
    let documentId: String
}

/// Top-level structure stored in UserDefaults.
/// Stores the active tab's **documentId** (stable) rather than its ephemeral `id`.
private struct PersistedTabList: Codable {
    /// The `documentId` of the previously active tab, for restore matching.
    let activeDocumentId: String?
    let tabs: [PersistedTab]
}

/// Manages session persistence for the Marker app.
///
/// Handles saving and restoring security-scoped bookmarks, tab lists,
/// scroll positions, dirty draft snapshots, and window geometry.
/// All methods are designed to work within App Sandbox constraints.
final class SessionStateService: ObservableObject {
    /// Placeholder to satisfy ObservableObject conformance.
    /// Future phases will add @Published properties for tab/draft state.
    @Published private var _ready: Bool = true

    private let defaults: UserDefaults
    private let bookmarkKey = "lastDirectoryBookmark"

    private let fileManager: FileManager

    /// The root URL used to resolve relative tab paths.
    /// Set before calling saveTabList / loadTabList.
    var rootURL: URL?

    /// The application support directory where drafts are stored.
    private lazy var draftsDirectory: URL? = {
        guard let support = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }
        let dir = support.appendingPathComponent(Bundle.main.bundleIdentifier ?? "Marker")
            .appendingPathComponent("drafts")
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    init(defaults: UserDefaults = .standard, fileManager: FileManager = .default) {
        self.defaults = defaults
        self.fileManager = fileManager
    }

    //
    // MARK: - Tab List Persistence

    /// Storable keys for tab-related UserDefaults entries.
    private let tabListKey = "openTabs"
    private let scrollOffsetsKey = "scrollOffsets"

    /// Save the current set of open tabs and the active tab ID.
    /// Tab paths are stored relative to `rootURL`.
    func saveTabList(_ tabs: [Tab], activeId: String?) {
        guard let root = rootURL else { return }
        let rootPath = root.path

        // Find the documentId of the active tab (stable across restarts).
        let activeDocumentId = activeId.flatMap { id in
            tabs.first { $0.id == id }?.documentId
        }

        let persisted = tabs.map { tab -> PersistedTab in
            let relative: String
            if let tabPath = tab.path, tabPath.hasPrefix(rootPath) {
                relative = String(tabPath.dropFirst(rootPath.count + 1))  // +1 for trailing /
            } else {
                relative = tab.title  // fallback: use title for untitled tabs
            }
            return PersistedTab(path: relative, title: tab.title, documentId: tab.documentId)
        }

        let list = PersistedTabList(activeDocumentId: activeDocumentId, tabs: persisted)
        if let encoded = try? JSONEncoder().encode(list) {
            defaults.set(encoded, forKey: tabListKey)
        }
    }

    /// Load the persisted tab list.
    /// Returns paths relative to root, plus the active tab's documentId.
    func loadTabList() -> (paths: [String], activeDocumentId: String?)? {
        guard let data = defaults.data(forKey: tabListKey) else { return nil }
        guard let list = try? JSONDecoder().decode(PersistedTabList.self, from: data) else {
            return nil
        }
        // Paths were stored relative to rootURL; return them as-is.
        // The caller prepends rootURL when opening.
        let paths = list.tabs.map { $0.path }
        return (paths, list.activeDocumentId)
    }

    /// Save a scroll offset for a specific document.
    func saveScrollOffset(_ offset: CGFloat, for documentId: String) {
        var offsets = loadScrollOffsets()
        offsets[documentId] = offset
        if let encoded = try? JSONEncoder().encode(offsets) {
            defaults.set(encoded, forKey: scrollOffsetsKey)
        }
    }

    /// Load all saved scroll offsets.
    func loadScrollOffsets() -> [String: CGFloat] {
        guard let data = defaults.data(forKey: scrollOffsetsKey) else { return [:] }
        return (try? JSONDecoder().decode([String: CGFloat].self, from: data)) ?? [:]
    }

    /// Clear all persisted tab state.
    func clearTabState() {
        defaults.removeObject(forKey: tabListKey)
        defaults.removeObject(forKey: scrollOffsetsKey)
    }

    //
    // MARK: - Draft Snapshots

    /// Save a draft snapshot for a document.
    func saveDraft(_ text: String, for documentId: String) {
        guard let dir = draftsDirectory else { return }
        let url = dir.appendingPathComponent("\(documentId).md")
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Load a draft snapshot for a document, if it exists and is newer than the source file.
    /// - Parameters:
    ///   - documentId: The tab's document ID.
    ///   - sourcePath: The on-disk path of the source file, for modification-date comparison.
    /// - Returns: Draft text if a draft exists and is newer than the source, else nil.
    func loadDraft(for documentId: String, newerThan sourcePath: String?) -> String? {
        guard let dir = draftsDirectory else { return nil }
        let url = dir.appendingPathComponent("\(documentId).md")
        guard fileManager.fileExists(atPath: url.path) else { return nil }

        // If we have a source file, only use draft if it's newer
        if let sourcePath {
            let draftDate = (try? fileManager.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
            let sourceDate = (try? fileManager.attributesOfItem(atPath: sourcePath))?[.modificationDate] as? Date
            if let draftDate, let sourceDate, draftDate <= sourceDate {
                // Draft is not newer than source — discard stale draft
                try? fileManager.removeItem(at: url)
                return nil
            }
        }

        return try? String(contentsOf: url, encoding: .utf8)
    }

    /// Delete a draft snapshot for a document.
    func deleteDraft(for documentId: String) {
        guard let dir = draftsDirectory else { return }
        let url = dir.appendingPathComponent("\(documentId).md")
        try? fileManager.removeItem(at: url)
    }

    /// Remove draft files whose document IDs are not in the keep set.
    func pruneOrphanedDrafts(keep: Set<String>) {
        guard let dir = draftsDirectory else { return }
        guard let contents = try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            return
        }
        for url in contents {
            let docId = url.deletingPathExtension().lastPathComponent
            if !keep.contains(docId) {
                try? fileManager.removeItem(at: url)
            }
        }
    }

    // MARK: - Directory Bookmark

    /// Save a security-scoped bookmark for the given directory URL.
    ///
    /// Call this *after* `url.startAccessingSecurityScopedResource()` has succeeded,
    /// so the bookmark captures the active security scope.
    func saveDirectoryBookmark(for url: URL) {
        do {
            let bookmark = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            defaults.set(bookmark, forKey: bookmarkKey)
        } catch {
            // If bookmark creation fails, clear any stale bookmark.
            defaults.removeObject(forKey: bookmarkKey)
        }
    }

    /// Clear the stored directory bookmark.
    func clearDirectoryBookmark() {
        defaults.removeObject(forKey: bookmarkKey)
    }

    /// Load and resolve the last saved directory bookmark.
    ///
    /// Returns `nil` if no bookmark exists, it is stale, or the security scope
    /// cannot be started (e.g. the external drive was disconnected).
    ///
    /// When a valid URL is returned, the caller **must** balance this with
    /// a matching `url.stopAccessingSecurityScopedResource()` call.
    func loadDirectoryBookmark() -> URL? {
        guard let data = defaults.data(forKey: bookmarkKey) else {
            return nil
        }

        var isStale = false
        let url: URL
        do {
            url = try URL(
                resolvingBookmarkData: data,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
        } catch {
            // Bookmark data is corrupt or invalid — clear it.
            clearDirectoryBookmark()
            return nil
        }

        if isStale {
            // The bookmark is stale (file was moved / permissions changed).
            // Attempt to re-create it if the URL is still reachable.
            clearDirectoryBookmark()
            return nil
        }

        // Start security-scoped access. If this fails (e.g. the external drive
        // was disconnected), return nil without storing anything.
        guard url.startAccessingSecurityScopedResource() else {
            return nil
        }

        return url
    }

    /// Verify that the security-scoped access granted by `url` actually
    /// permits *writing* into the directory, not just reading it.
    ///
    /// A bookmark can resolve to a scope that only allows reads (e.g. one
    /// created with `.securityScopeAllowOnlyReadAccess`).  The sandbox grants
    /// read access for directory listing even then, so a read-only scope is
    /// indistinguishable from a read-write one until an actual write is
    /// attempted.  We probe by creating and immediately removing a zero-byte
    /// file inside the directory; if that fails with a permission error the
    /// scope is read-only and the caller should discard the bookmark and ask
    /// the user to re-select the folder.
    ///
    /// - Important: `url` must already have an active security scope
    ///   (i.e. `startAccessingSecurityScopedResource()` returned true) before
    ///   this is called.
    /// - Returns: `true` if a write into the directory succeeds.
    func canWriteToDirectory(_ url: URL) -> Bool {
        let probe = url.appendingPathComponent(".marker-write-probe-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: probe) }
        do {
            try Data().write(to: probe, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    //
    // MARK: - Window Geometry

    private let windowFrameKey = "windowFrame"
    private let sidebarWidthKey = "sidebarWidth"

    /// Save the window frame (x, y, width, height).
    func saveWindowFrame(_ rect: NSRect) {
        let encoded = "\(rect.origin.x),\(rect.origin.y),\(rect.size.width),\(rect.size.height)"
        defaults.set(encoded, forKey: windowFrameKey)
    }

    /// Load a previously saved window frame.
    /// Returns the zero rect (which NSWindow ignores) when not yet saved.
    func loadWindowFrame() -> NSRect {
        guard let string = defaults.string(forKey: windowFrameKey) else {
            return .zero
        }
        let parts = string.split(separator: ",").compactMap { Double($0) }
        guard parts.count == 4 else { return .zero }
        return NSRect(x: parts[0], y: parts[1], width: parts[2], height: parts[3])
    }

    /// Save the sidebar column width.
    func saveSidebarWidth(_ width: CGFloat) {
        defaults.set(Double(width), forKey: sidebarWidthKey)
    }

    /// Load a previously saved sidebar width.
    /// Returns nil when not yet saved.
    func loadSidebarWidth() -> CGFloat? {
        let value = defaults.double(forKey: sidebarWidthKey)
        return value > 0 ? CGFloat(value) : nil
    }

    /// Clear all window geometry state.
    func clearWindowGeometry() {
        defaults.removeObject(forKey: windowFrameKey)
        defaults.removeObject(forKey: sidebarWidthKey)
    }
}