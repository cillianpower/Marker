//
//  FileExplorerService.swift
//  Marker
//
//  Created by Cillian on 09/07/2026.
//

import Foundation
import Combine
import OSLog

private let fileExplorerLog = OSLog(subsystem: "com.marker.app", category: "file-explorer")

// MARK: - Tree model

/// A node in the sidebar file tree. Directories have children; files don't.
struct FileNode: Identifiable, Hashable {
    let id: String
    let url: URL
    let name: String
    let isDirectory: Bool
    var children: [FileNode]?

    init(url: URL, isDirectory: Bool, children: [FileNode]?) {
        self.id = url.path
        self.url = url
        self.name = url.lastPathComponent
        self.isDirectory = isDirectory
        self.children = children
    }

    static func == (lhs: FileNode, rhs: FileNode) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Service

/// Watches a directory and publishes a tree of markdown/text files.
final class FileExplorerService: ObservableObject {
    /// The root directory being browsed.
    @Published var rootURL: URL?
    /// Recursive tree of markdown/text files, directories with children.
    @Published var tree: [FileNode] = []

    /// Session state persistence (bookmarks, tabs, etc.).
    /// Injected from the app-level owner to maintain a single instance.
    var sessionState: SessionStateService?

    /// The root directory URL that has a security scope active.
    /// Exposed so `SavePipeline` can assert the scope at write time.
    private(set) var scopedURL: URL?
    /// Tracks extra `startAccessingSecurityScopedResource` calls so we can
    /// balance them correctly in `stopAccessIfNeeded`.
    private var extraScopeReferences: Int = 0
    private var fileDescriptor: Int32?
    private var dispatchSource: DispatchSourceFileSystemObject?

    deinit {
        stopWatching()
        stopAccessIfNeeded()
    }

    /// Set a new root directory to browse. The URL may be security-scoped on macOS.
    func openDirectory(_ url: URL) {
        stopWatching()
        stopAccessIfNeeded()

        // Start the security scope on the ORIGINAL URL (comes from NSOpenPanel
        // or resolved bookmark — only these carry security-scoped data).
        let scopeStarted = url.startAccessingSecurityScopedResource()
        if !scopeStarted {
            os_log(.error, log: fileExplorerLog, "openDirectory: startAccessingSecurityScopedResource FAILED for %{public}s", url.path)
        } else {
            os_log(.debug, log: fileExplorerLog, "openDirectory: security scope started for %{public}s", url.path)
        }

        // Keep the ORIGINAL URL as the scoped URL — it carries the
        // security-scope data from NSOpenPanel or bookmark resolution.
        // Only standardizedFileURL would lose the scope.
        scopedURL = url

        // Use the standardized URL for path-based operations so the path
        // matches the standardized paths stored in Tab.path.
        // The sandbox tracks access at the inode level, so the scope
        // started on the original URL covers operations on the
        // standardized path (same inode).
        let standardURL = url.standardizedFileURL
        rootURL = standardURL

        // Persist the bookmark so we can restore this directory on next launch.
        sessionState?.saveDirectoryBookmark(for: url)

        // Build the tree synchronously.
        let newTree = buildFileTree(at: standardURL)
        DispatchQueue.main.async {
            self.tree = newTree
        }

        startWatching(standardURL)
    }

    // MARK: - Tree building

    /// Recursively build a tree of markdown/text files starting at `url`.
    /// - Parameter depth: Current recursion depth (used to cap at 8 levels).
    private func buildFileTree(at url: URL, depth: Int = 0) -> [FileNode] {
        guard depth < 8 else { return [] }

        let contents: [URL]
        do {
            contents = try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            return []
        }

        let sorted = contents.sorted { lhs, rhs in
            lhs.lastPathComponent.localizedCaseInsensitiveCompare(rhs.lastPathComponent) == .orderedAscending
        }

        return sorted.compactMap { itemURL in
            guard let values = try? itemURL.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey]),
                  let isDir = values.isDirectory
            else { return nil }

            if isDir {
                // Skip packages and bundle directories
                guard !isPackageURL(itemURL) else { return nil }
                let children = buildFileTree(at: itemURL, depth: depth + 1)
                // Prune empty directories
                guard !children.isEmpty else { return nil }
                return FileNode(url: itemURL, isDirectory: true, children: children)
            } else {
                guard values.isRegularFile == true else { return nil }
                let ext = itemURL.pathExtension.lowercased()
                guard ext == "md" || ext == "txt" || ext == "markdown" else { return nil }
                return FileNode(url: itemURL, isDirectory: false, children: nil)
            }
        }
    }

    /// Check whether a URL points to a file-system package (e.g. .rtfd, .playground).
    private func isPackageURL(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            return false
        }
        // Check the package bit via NSURL
        let resourceKey = URLResourceKey.isPackageKey
        guard let values = try? url.resourceValues(forKeys: [resourceKey]),
              let isPkg = values.isPackage
        else { return false }
        return isPkg
    }

    // MARK: - File system watching

    private func startWatching(_ url: URL) {
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else {
            return
        }
        fileDescriptor = fd

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete],
            queue: DispatchQueue.global(qos: .utility)
        )
        dispatchSource = source

        source.setEventHandler { [weak self] in
            guard let self else { return }
            let newTree = self.buildFileTree(at: url)
            DispatchQueue.main.async {
                self.tree = newTree
            }
        }
        source.setCancelHandler {
            close(fd)
        }
        source.resume()
    }

    private func stopWatching() {
        dispatchSource?.cancel()
        dispatchSource = nil
        fileDescriptor = nil
    }

    /// Release the security scope for the current root directory (if any),
    /// balancing any active `startAccessingSecurityScopedResource` calls.
    /// Public so owners can release a scope obtained independently (e.g. one
    /// started by `SessionStateService.loadDirectoryBookmark()`) before
    /// re-acquiring a fresh scope.
    func stopAccess() {
        stopAccessIfNeeded()
    }

    /// Ensure the security scope for the root directory is active.
    /// Safe to call multiple times — each call increments an internal
    /// reference count. Call `releaseSecurityScope()` to balance.
    func retainSecurityScope() {
        guard let url = scopedURL else {
            os_log(.error, log: fileExplorerLog, "retainSecurityScope: scopedURL is nil")
            return
        }
        let ok = url.startAccessingSecurityScopedResource()
        if ok {
            extraScopeReferences += 1
            os_log(.debug, log: fileExplorerLog, "retainSecurityScope: scope retained (count=%d)", extraScopeReferences)
        } else {
            os_log(.error, log: fileExplorerLog, "retainSecurityScope: startAccessingSecurityScopedResource FAILED")
        }
    }

    /// Release one retained security scope reference.
    /// Must be balanced with a prior `retainSecurityScope()` call.
    func releaseSecurityScope() {
        guard extraScopeReferences > 0 else {
            os_log(.debug, log: fileExplorerLog, "releaseSecurityScope: no extra references to release")
            return
        }
        extraScopeReferences -= 1
        scopedURL?.stopAccessingSecurityScopedResource()
        os_log(.debug, log: fileExplorerLog, "releaseSecurityScope: scope released (count=%d)", extraScopeReferences)
    }

    private func stopAccessIfNeeded() {
        // Balance any extra scope references first
        while extraScopeReferences > 0 {
            extraScopeReferences -= 1
            scopedURL?.stopAccessingSecurityScopedResource()
        }
        if let url = scopedURL {
            url.stopAccessingSecurityScopedResource()
            scopedURL = nil
        }
    }
}
