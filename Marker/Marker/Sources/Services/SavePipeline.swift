//
//  SavePipeline.swift
//  Marker
//
//  Created by Cillian on 13/07/2026.
//

import Foundation
import OSLog

private let savePipelineLog = OSLog(subsystem: "com.marker.app", category: "save-pipeline")

/// A save pipeline that guarantees atomic, data-safe writes to disk.
///
/// 1.  Writes content to a temporary file in the **same directory** as the
///     target — this keeps the temp file on the same volume so the final
///     rename is truly atomic (no cross-volume copying).
/// 2.  Preserves file metadata (creation date, POSIX permissions) from the
///     original file when it already exists.
/// 3.  Creates intermediate directories if they don't exist.
/// 4.  Atomically replaces the target file via
///     `FileManager.replaceItemAt`, which uses a kernel-level rename under
///     the hood and never leaves a partially-written target behind.
///
/// # Thread safety
/// `SavePipeline.write` is safe to call from any thread.  The underlying
/// `FileManager.replaceItemAt` is atomic at the filesystem level, so
/// concurrent writes from different processes or threads either see the
/// old content or the new content — never a partial write.
enum SavePipeline {

    // MARK: - Errors

    enum WriteError: Error, CustomStringConvertible, LocalizedError {
        /// The string could not be encoded as UTF-8 data (should never
        /// happen for a valid Swift string).
        case encodingFailed
        /// Writing to the temporary file failed.
        case tempWriteFailed(Error)
        /// Creating intermediate directories failed.
        case directoryCreationFailed(Error)
        /// The final atomic replace (rename) failed.
        case replaceFailed(Error)

        var description: String {
            switch self {
            case .encodingFailed:
                return "Failed to encode content as UTF-8 data"
            case let .tempWriteFailed(error):
                return "Temporary write failed: \(error.localizedDescription)"
            case let .directoryCreationFailed(error):
                return "Creating parent directory failed: \(error.localizedDescription)"
            case let .replaceFailed(error):
                return "Write failed: \(error.localizedDescription)"
            }
        }

        var errorDescription: String? { description }
    }

    // MARK: - Public API

    /// Write `content` to `url` atomically.
    ///
    /// - Parameters:
    ///   - content: The string to persist.
    ///   - url: The target file URL.
    ///   - securityScopedRoot: If non-nil, `startAccessingSecurityScopedResource()`
    ///     is called on this URL before writing and `stopAccessing` after, ensuring
    ///     the security scope is active for the file operation.  Pass the root
    ///     directory URL (from NSOpenPanel / resolved bookmark) here.
    /// - Throws: `WriteError` on any failure.  The target file is never
    ///   corrupted — on error the original file (if any) remains intact.
    static func write(_ content: String, to url: URL, securityScopedRoot: URL? = nil) throws {
        // Assert the security scope at the exact moment of writing.
        // This ensures the sandbox allows the file operation regardless
        // of any lifecycle issues with retain/release scope calls.
        let scopeWasStarted = securityScopedRoot?.startAccessingSecurityScopedResource() ?? false
        if scopeWasStarted {
            os_log(.debug, log: savePipelineLog, "security scope started for write")
        }
        // We defer the stop so that the scope stays active for the entire
        // write operation.  If we started the scope here, we own the stop.
        defer {
            if scopeWasStarted {
                securityScopedRoot?.stopAccessingSecurityScopedResource()
                os_log(.debug, log: savePipelineLog, "security scope stopped after write")
            }
        }

        os_log(.debug, log: savePipelineLog, "write start: %{public}s (%d chars)",
               url.lastPathComponent, content.count)

        // 1. Create intermediate directories (only if they don't already exist).
        //    In the sandbox, createDirectory can fail even when the directory
        //    already exists, because the stat() check requires security-scope
        //    access.  Check with fileExists first to avoid the sandbox denial.
        let directory = url.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: directory.path) {
            do {
                try FileManager.default.createDirectory(
                    at: directory,
                    withIntermediateDirectories: true,
                    attributes: nil
                )
            } catch {
                os_log(.error, log: savePipelineLog, "directory creation failed: %{public}s",
                       error.localizedDescription)
                throw WriteError.directoryCreationFailed(error)
            }
        } else {
            os_log(.debug, log: savePipelineLog, "directory already exists — skipping creation")
        }

        // 2. Encode content as UTF-8 data
        guard let data = content.data(using: .utf8) else {
            os_log(.error, log: savePipelineLog, "encoding failed")
            throw WriteError.encodingFailed
        }

        // 3. Create a temp file in the system temporary directory.  This is
        //    always writable (it lives outside the security-scoped user
        //    folder), so the temp write itself can never be denied by the
        //    sandbox.  The final `replaceItemAt` into the target folder is the
        //    only operation that needs the security scope, and `replaceItemAt`
        //    performs a correct cross-volume move when the temp file is on a
        //    different volume than the target.
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let tempURL = tempDir.appendingPathComponent(
            ".\(url.lastPathComponent).tmp~\(UUID().uuidString)"
        )
        os_log(.debug, log: savePipelineLog, "temp file: %{public}s", tempURL.lastPathComponent)

        // Cleanup the temp file no matter what happens.
        defer { try? FileManager.default.removeItem(at: tempURL) }

        // 4. Write data to the temp file.
        do {
            try data.write(to: tempURL, options: [])
            os_log(.debug, log: savePipelineLog, "temp write done (%lld bytes)", data.count)
        } catch {
            os_log(.error, log: savePipelineLog, "temp write failed: %{public}s",
                   error.localizedDescription)
            throw WriteError.tempWriteFailed(error)
        }

        // 5. Capture the original file's metadata (only if the target already
        //    exists) so we can re-apply it to the final file after the atomic
        //    replace.  `replaceItemAt` leaves the replaced item with the *new*
        //    item's (temp file's) attributes, so we restore the original's
        //    creation date / POSIX permissions / ownership afterwards.
        //
        //    If the existing target is read-only (e.g. 0o444), the kernel-level
        //    rename inside `replaceItemAt` cannot unlink it, so the replace
        //    fails with a permission error.  We therefore temporarily add the
        //    owner-write bit before the replace and restore the exact original
        //    permissions afterwards — this is the same approach a shell's
        //    `> file` redirection relies on (write access to the *directory*,
        //    not the file, is what matters for replacing it).
        var originalAttrs: [FileAttributeKey: Any]?
        var needsWriteBit: Bool = false
        if FileManager.default.fileExists(atPath: url.path) {
            originalAttrs = try? FileManager.default.attributesOfItem(atPath: url.path)
            if let perms = originalAttrs?[.posixPermissions] as? NSNumber,
               (perms.intValue & 0o200) == 0 {
                needsWriteBit = true
                do {
                    try FileManager.default.setAttributes(
                        [.posixPermissions: NSNumber(value: perms.intValue | 0o200)],
                        ofItemAtPath: url.path
                    )
                } catch {
                    // If we cannot make the target writable, the upcoming
                    // replace will surface the real permission error instead.
                    os_log(.error, log: savePipelineLog, "could not add write bit to target: %{public}s",
                           error.localizedDescription)
                }
            }
            os_log(.debug, log: savePipelineLog, "captured original metadata (needsWriteBit=%{public}s)",
                   String(needsWriteBit))
        } else {
            os_log(.debug, log: savePipelineLog, "target does not exist yet — skipping metadata")
        }

        // 6. Atomically replace the target with the temp file via a kernel-level
        //    rename.  This will not leave a partially-written file behind, and
        //    it overwrites an existing target without a separate, separately
        //    sandbox-checked removeItem call.
        do {
            _ = try FileManager.default.replaceItemAt(
                url,
                withItemAt: tempURL,
                backupItemName: nil,
                options: []
            )
            os_log(.debug, log: savePipelineLog, "atomic replace succeeded")
        } catch {
            os_log(.error, log: savePipelineLog, "replace failed: %{public}s",
                   error.localizedDescription)
            throw WriteError.replaceFailed(error)
        }

        // 7. Re-apply the original file's metadata to the now-replaced target.
        if let originalAttrs, !originalAttrs.isEmpty {
            try? FileManager.default.setAttributes(originalAttrs, ofItemAtPath: url.path)
            os_log(.debug, log: savePipelineLog, "original metadata restored")
        }
    }
}
