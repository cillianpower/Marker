//
//  FSTag.swift
//  Marker
//
//  Created by Cillian on 13/07/2026.
//

import Foundation

/// A tree node representing a tag with an optional parent and zero or more
/// children. Supports nested tags via the `a/b/c` path convention.
///
/// Based on FSNotes `FSTag.swift`.
final class FSTag {
    public var name: String
    public var parent: FSTag?

    public var child = [FSTag]()
    public var isExpanded = false

    init(name: String, parent: FSTag? = nil) {
        self.name = name
        self.parent = parent

        let tags = name.components(separatedBy: "/")
        if tags.count > 1, let parentName = tags.first {
            addChild(name: tags.dropFirst().joined(separator: "/")) { _, _, _ in }
            self.name = parentName
        }
    }

    /// Re-initialise the node with a new name path.
    public func load(name: String) {
        self.name = name

        let tags = name.components(separatedBy: "/")
        if tags.count > 1, let parentName = tags.first {
            addChild(name: tags.dropFirst().joined(separator: "/")) { _, _, _ in }
            self.name = parentName
        }
    }

    public func isExpandable() -> Bool {
        child.count > 0
    }

    /// Add a child tag, inserting it in alphabetical order if new.
    ///
    /// - Parameters:
    ///   - completion: Called with the child (existing or newly created), a
    ///     boolean indicating whether it already existed, and its insertion
    ///     index.
    public func addChild(
        name: String,
        completion: (_ tag: FSTag, _ isExist: Bool, _ position: Int) -> Void
    ) {
        let tags = name.components(separatedBy: "/")

        if let index = child.firstIndex(where: { $0.name == tags.first }) {
            completion(child[index], true, index)
        } else {
            let newTag = FSTag(name: name, parent: self)
            let index = getChildPosition(for: newTag)
            child.insert(newTag, at: index)
            completion(newTag, false, index)
        }
    }

    /// Return the sorted insertion index for `tag`.
    public func getChildPosition(for tag: FSTag) -> Int {
        var tags = child
        tags.append(tag)

        let sorted = tags.sorted(by: { $0.name.lowercased() < $1.name.lowercased() })
        if let index = sorted.firstIndex(where: { $0 === tag }) {
            return index
        }
        return 0
    }

    public func indexOf(child tag: FSTag) -> Int? {
        child.firstIndex(where: { $0 === tag })
    }

    public func remove(by index: Int) {
        child.remove(at: index)
    }

    public func removeChild(tag: FSTag) {
        child.removeAll(where: { $0 === tag })
    }

    public func removeParent() {
        parent = nil
    }

    public func get(name: String) -> FSTag? {
        var lookup = name
        let tags = name.components(separatedBy: "/")

        if tags.count > 1, let first = tags.first {
            lookup = first
        }

        return child.first(where: { $0.name == lookup })
    }

    public func getName() -> String {
        name
    }

    /// The full path from root, e.g. `"work/project/feature"`.
    public func getFullName() -> String {
        if let parentTag = parent?.getFullName(), !parentTag.isEmpty {
            return "\(parentTag)/\(name)"
        }

        if name == "Tags" {
            return ""
        }

        return name
    }

    /// Walk the tree to find a tag by its full (or relative) path.
    ///
    /// Example: from a root `FSTag`, `find(name: "work/project")` returns the
    /// child `project` nested under `work`.
    public func find(name: String) -> FSTag? {
        let tags = name.components(separatedBy: "/")
        guard let first = tags.first else { return nil }
        guard let child = get(name: first) else { return nil }

        let rest = tags.dropFirst().joined(separator: "/")
        if rest.isEmpty {
            return child
        }
        return child.find(name: rest)
    }

    public func isAlone() -> Bool {
        guard let parent else { return false }
        return parent.child.count == 1
    }

    public func getParent() -> FSTag? {
        parent
    }

    public func hasOneChild() -> Bool {
        child.count < 2
    }

    public func removeAllChild() {
        if child.count < 2 {
            child.removeAll()
        }
    }

    /// Breadth-first traversal returning the full name of every descendant.
    public func getAllChild() -> [String] {
        var tags = [String]()
        tags.append(getFullName())

        var queue = [FSTag]()
        queue.append(contentsOf: child)

        while !queue.isEmpty {
            for item in queue {
                tags.append(item.getFullName())
                if item.child.count > 0 {
                    queue.append(contentsOf: item.child)
                }
                queue.removeAll(where: { $0 === item })
            }

            if queue.isEmpty {
                break
            }
        }

        return tags
    }
}
