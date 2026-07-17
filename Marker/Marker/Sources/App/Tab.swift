//
//  Tab.swift
//  Marker
//
//  Created by Cillian on 09/07/2026.
//

import Foundation
import Combine
import OSLog

private let saveLog = OSLog(subsystem: "com.marker.app", category: "save")

/// A single open document tab.
final class Tab: ObservableObject, Identifiable {
    let id: String
    let documentId: String
    var path: String?
    @Published var title: String
    @Published var text: String
    @Published var isDirty: Bool = false
    @Published var frontMatter: FrontMatter?
    @Published var tags: [String] = []

    private var savedText: String

    init(path: String?) {
        let uuid = UUID().uuidString
        self.id = uuid
        self.documentId = uuid
        self.path = path
        let loaded: String
        if let path = path, let data = try? String(contentsOfFile: path, encoding: .utf8) {
            loaded = data
        } else {
            loaded = ""
        }
        self.text = loaded
        self.savedText = loaded
        // Parse front matter and tags; use local variable for title so we
        // don't access self before all stored properties are initialised.
        let fm = FrontMatterParser.parse(from: loaded)
        self.frontMatter = fm
        self.tags = TagParser.parseTags(from: loaded)
        if let fmTitle = fm?.title, !fmTitle.isEmpty {
            self.title = fmTitle
        } else {
            self.title = path
                .flatMap { URL(fileURLWithPath: $0).lastPathComponent }
                ?? "Untitled"
        }
    }

    /// Call after the binding reports a change to mark the tab dirty.
    func markEdited() {
        if text != savedText {
            isDirty = true
        }
    }

    /// Replace this tab's contents with a different file (reuses the tab).
    /// Clears dirty state and loads the new file from disk.
    func replaceContents(withFileAt newPath: String) {
        let resolved = (newPath as NSString).standardizingPath
        path = resolved
        if let data = try? String(contentsOfFile: resolved, encoding: .utf8) {
            text = data
        } else {
            text = ""
        }
        savedText = text
        isDirty = false
        frontMatter = FrontMatterParser.parse(from: text)
        tags = TagParser.parseTags(from: text)
        // Prefer front-matter title over filename
        if let fmTitle = frontMatter?.title, !fmTitle.isEmpty {
            title = fmTitle
        } else {
            title = URL(fileURLWithPath: resolved).lastPathComponent
        }
    }

    /// Persist the current text to disk and clear dirty flag.
    /// Returns `false` if the tab has no path (untitled) — the caller should
    /// prompt for a save location via NSSavePanel and call `save(to:)` instead.
    /// - Parameter securityScopedRoot: root directory URL with an active security
    ///   scope, passed to SavePipeline to assert at write time.
    func save(securityScopedRoot: URL? = nil) throws -> Bool {
        guard let path = path else {
            os_log(.debug, log: saveLog, "save: no path — untitled tab")
            return false
        }
        os_log(.debug, log: saveLog, "save: writing %{public}s (%d chars, preview: %{public}s)",
               path, text.count, String(text.prefix(60)))
        try SavePipeline.write(text, to: URL(fileURLWithPath: path), securityScopedRoot: securityScopedRoot)
        savedText = text
        isDirty = false
        reparseMetadata()
        os_log(.debug, log: saveLog, "save: completed %{public}s", path)
        return true
    }

    /// Save the current text to a specific file URL and update the tab's path.
    /// - Parameter securityScopedRoot: root directory URL with an active security
    ///   scope, passed to SavePipeline to assert at write time.
    func save(to url: URL, securityScopedRoot: URL? = nil) throws {
        os_log(.debug, log: saveLog, "save(to:): %{public}s (%d chars, preview: %{public}s)",
               url.path, text.count, String(text.prefix(60)))
        try SavePipeline.write(text, to: url, securityScopedRoot: securityScopedRoot)
        path = url.path
        savedText = text
        isDirty = false
        reparseMetadata()
        os_log(.debug, log: saveLog, "save(to:): completed %{public}s", url.path)
    }

    /// Reload from disk, discarding in-memory edits.
    func reload() throws {
        guard let path = path else { return }
        let loaded = try String(contentsOfFile: path, encoding: .utf8)
        text = loaded
        savedText = loaded
        isDirty = false
        reparseMetadata()
    }

    // MARK: - Metadata

    /// Re-parse front matter and tags from the current text and update
    /// the display title if a front-matter title is present.
    private func reparseMetadata() {
        frontMatter = FrontMatterParser.parse(from: text)
        tags = TagParser.parseTags(from: text)
        if let fmTitle = frontMatter?.title, !fmTitle.isEmpty {
            title = fmTitle
        } else if let path {
            title = URL(fileURLWithPath: path).lastPathComponent
        } else {
            title = "Untitled"
        }
    }
}
