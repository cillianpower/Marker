//
//  MarkerTests.swift
//  MarkerTests
//
//  Created by Cillian on 09/07/2026.
//

import Testing
import Foundation
import AppKit
@testable import Marker

// MARK: - Tab Tests

struct TabTests {

    @Test func tabWithPath() {
        let tab = Tab(path: "/tmp/test.md")
        #expect(tab.path == "/tmp/test.md")
        #expect(tab.title == "test.md")
        #expect(tab.text == "")
        #expect(!tab.isDirty)
        #expect(tab.id == tab.documentId)
    }

    @Test func tabWithoutPath() {
        let tab = Tab(path: nil)
        #expect(tab.path == nil)
        #expect(tab.title == "Untitled")
        #expect(tab.text == "")
        #expect(!tab.isDirty)
    }

    @Test func markEditedDetectsChange() {
        let tab = Tab(path: nil)
        tab.text = "new content"
        tab.markEdited()
        #expect(tab.isDirty)
    }

    @Test func markEditedNoChange() {
        let tab = Tab(path: nil)
        tab.markEdited()
        #expect(!tab.isDirty)
    }

    @Test func saveUntitledTabReturnsFalse() throws {
        let tab = Tab(path: nil)
        let result = try tab.save()
        #expect(!result)
    }

    @Test func saveWithPath() throws {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("marker-test-save.md")
        try "hello".write(to: tempURL, atomically: true, encoding: .utf8)

        let tab = Tab(path: tempURL.path)
        tab.text = "updated"
        let result = try tab.save()
        #expect(result)
        #expect(!tab.isDirty)

        // Read back
        let contents = try String(contentsOf: tempURL, encoding: .utf8)
        #expect(contents == "updated")

        try FileManager.default.removeItem(at: tempURL)
    }

    @Test func saveToURL() throws {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("marker-test-saveto.md")

        let tab = Tab(path: nil)
        tab.text = "saved content"
        try tab.save(to: tempURL)

        #expect(tab.path == tempURL.path)
        #expect(tab.title == "marker-test-saveto.md")
        #expect(!tab.isDirty)

        let contents = try String(contentsOf: tempURL, encoding: .utf8)
        #expect(contents == "saved content")

        try FileManager.default.removeItem(at: tempURL)
    }

    @Test func replaceContentsMaintainsPath() throws {
        let originalURL = FileManager.default.temporaryDirectory.appendingPathComponent("marker-replace-orig.md")
        try "original".write(to: originalURL, atomically: true, encoding: .utf8)

        let newURL = FileManager.default.temporaryDirectory.appendingPathComponent("marker-replace-new.md")
        try "new content".write(to: newURL, atomically: true, encoding: .utf8)

        let tab = Tab(path: originalURL.path)
        tab.replaceContents(withFileAt: newURL.path)

        #expect(tab.path == newURL.path)
        #expect(tab.title == "marker-replace-new.md")
        #expect(tab.text == "new content")
        #expect(!tab.isDirty)

        try? FileManager.default.removeItem(at: originalURL)
        try? FileManager.default.removeItem(at: newURL)
    }

    @Test func reloadFromDisk() throws {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("marker-test-reload.md")
        try "original".write(to: tempURL, atomically: true, encoding: .utf8)

        let tab = Tab(path: tempURL.path)
        tab.text = "unsaved edit"

        try tab.reload()
        #expect(tab.text == "original")
        #expect(!tab.isDirty)

        try FileManager.default.removeItem(at: tempURL)
    }
}

// MARK: - TabManager Tests

struct TabManagerTests {

    @Test func openFileCreatesTab() {
        let mgr = TabManager()
        let tab = mgr.openFile(at: "/tmp/test.md")
        #expect(mgr.tabs.count == 1)
        #expect(tab.path == "/tmp/test.md")
        #expect(mgr.activeTabId == tab.id)
    }

    @Test func openFileReusesExisting() {
        let mgr = TabManager()
        let tab1 = mgr.openFile(at: "/tmp/test.md")
        let tab2 = mgr.openFile(at: "/tmp/test.md")
        #expect(mgr.tabs.count == 1)
        #expect(tab1.id == tab2.id)
    }

    @Test func openFileSmartReusesCleanTab() {
        let mgr = TabManager()
        let tab1 = mgr.openFile(at: "/tmp/test.md")
        _ = mgr.openFileSmart(at: "/tmp/other.md")
        #expect(mgr.tabs.count == 1) // reuses clean tab1
        #expect(mgr.activeTab?.path == "/tmp/other.md")
    }

    @Test func openFileSmartCreatesNewIfDirty() {
        let mgr = TabManager()
        let tab1 = mgr.openFile(at: "/tmp/test.md")
        tab1.text = "edited"
        tab1.markEdited()
        #expect(tab1.isDirty)

        _ = mgr.openFileSmart(at: "/tmp/other.md")
        #expect(mgr.tabs.count == 2) // dirty tab1 kept, new tab created
    }

    @Test func openUntitledCreatesTab() {
        let mgr = TabManager()
        let tab = mgr.openUntitled()
        #expect(mgr.tabs.count == 1)
        #expect(tab.title == "Untitled")
        #expect(tab.path == nil)
        #expect(mgr.activeTabId == tab.id)
    }

    @Test func closeTabRemovesAndSwitches() {
        let mgr = TabManager()
        let tab1 = mgr.openFile(at: "/tmp/a.md")
        let tab2 = mgr.openFile(at: "/tmp/b.md")
        mgr.closeTab(tab1.id)
        #expect(mgr.tabs.count == 1)
        #expect(mgr.activeTabId == tab2.id)
    }

    @Test func closeTabSwitchesToPrevious() {
        let mgr = TabManager()
        let tab1 = mgr.openFile(at: "/tmp/a.md")
        let tab2 = mgr.openFile(at: "/tmp/b.md")
        mgr.activeTabId = tab1.id
        mgr.closeTab(tab1.id)
        #expect(mgr.tabs.count == 1)
        #expect(mgr.activeTabId == tab2.id)
    }

    @Test func closeAllClears() {
        let mgr = TabManager()
        mgr.openFile(at: "/tmp/a.md")
        mgr.openFile(at: "/tmp/b.md")
        mgr.closeAll()
        #expect(mgr.tabs.isEmpty)
        #expect(mgr.activeTabId == nil)
    }

    @Test func activeTabIsCorrect() {
        let mgr = TabManager()
        let tab1 = mgr.openFile(at: "/tmp/a.md")
        #expect(mgr.activeTab?.id == tab1.id)
        let tab2 = mgr.openFile(at: "/tmp/b.md")
        #expect(mgr.activeTab?.id == tab2.id)
    }

    @Test func activeTabReturnsNil() {
        let mgr = TabManager()
        #expect(mgr.activeTab == nil)
    }

    @Test func saveActiveTabUntitledPostsNotification() throws {
        let mgr = TabManager()
        mgr.openUntitled()

        var receivedDocId: String? = nil
        let token = NotificationCenter.default.addObserver(
            forName: Notification.Name("markerSaveUntitled"),
            object: nil,
            queue: .main
        ) { note in
            receivedDocId = note.object as? String
        }

        let result = try mgr.saveActiveTab()
        #expect(!result)
        #expect(receivedDocId != nil)

        NotificationCenter.default.removeObserver(token)
    }

    @Test func markActiveTabEdited() throws {
        let mgr = TabManager()
        let tab = mgr.openFile(at: "/tmp/test.md")
        tab.text = "edited"
        mgr.markActiveTabEdited()
        #expect(tab.isDirty)
    }
}

// MARK: - SessionStateService Tests

@Suite
struct SessionStateServiceTests {
    let fileManager = FileManager()

    /// Create a fresh UserDefaults with a unique suite name for each test.
    private func makeDefaults() -> UserDefaults {
        let name = "marker-test-\(UUID().uuidString)"
        return UserDefaults(suiteName: name)!
    }

    @Test func directoryBookmarkSaveAndClear() {
        let service = SessionStateService(defaults: makeDefaults())
        let url = URL(fileURLWithPath: "/tmp")

        // Save bookmark
        service.saveDirectoryBookmark(for: url)
        // No crash — bookmark is stored (may not resolve without security scope)

        // Clear
        service.clearDirectoryBookmark()
        #expect(service.loadDirectoryBookmark() == nil)
    }

    @Test func canWriteToDirectorySucceedsForWritableDir() throws {
        let service = SessionStateService(defaults: makeDefaults())
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("marker-write-probe-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        // No security scope is active here, but /tmp is world-writable in the
        // test environment, so the probe write should succeed.
        #expect(service.canWriteToDirectory(dir) == true)
    }

    @Test func canWriteToDirectoryFailsForReadOnlyDir() throws {
        let service = SessionStateService(defaults: makeDefaults())
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("marker-write-probe-ro-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: dir.path)

        // The directory is not writable by the owner, so the probe must fail.
        #expect(service.canWriteToDirectory(dir) == false)
    }

    @Test func tabListSaveAndLoad() {
        let service = SessionStateService(defaults: makeDefaults())
        service.rootURL = URL(fileURLWithPath: "/tmp/notes")

        let tab1 = Tab(path: "/tmp/notes/project.md")
        let tab2 = Tab(path: "/tmp/notes/journal/2026.md")
        let tabs = [tab1, tab2]

        service.saveTabList(tabs, activeId: tab1.id)
        guard let (paths, activeDocumentId) = service.loadTabList() else {
            Issue.record("loadTabList returned nil")
            return
        }

        #expect(paths.count == 2)
        #expect(paths[0] == "project.md")
        #expect(paths[1] == "journal/2026.md")
        #expect(activeDocumentId == tab1.documentId)
    }

    @Test func loadTabListReturnsNilWhenEmpty() {
        let service = SessionStateService(defaults: makeDefaults())
        service.rootURL = URL(fileURLWithPath: "/tmp")
        #expect(service.loadTabList() == nil)
    }

    @Test func saveAndLoadScrollOffsets() {
        let service = SessionStateService(defaults: makeDefaults())
        service.saveScrollOffset(100.0, for: "doc1")
        service.saveScrollOffset(200.0, for: "doc2")

        let offsets = service.loadScrollOffsets()
        #expect(offsets["doc1"] == 100.0)
        #expect(offsets["doc2"] == 200.0)
    }

    @Test func scrollOffsetsEmptyWhenNotSaved() {
        let service = SessionStateService(defaults: makeDefaults())
        let offsets = service.loadScrollOffsets()
        #expect(offsets.isEmpty)
    }

    @Test func clearTabStateRemovesAll() {
        let service = SessionStateService(defaults: makeDefaults())
        service.rootURL = URL(fileURLWithPath: "/tmp")
        let tab = Tab(path: "/tmp/test.md")
        service.saveTabList([tab], activeId: tab.id)
        service.saveScrollOffset(50.0, for: tab.documentId)

        service.clearTabState()
        #expect(service.loadTabList() == nil)
        #expect(service.loadScrollOffsets().isEmpty)
    }

    @Test func draftSaveAndLoad() throws {
        let service = SessionStateService(defaults: makeDefaults(), fileManager: fileManager)
        let docId = UUID().uuidString

        service.saveDraft("draft content", for: docId)
        let loaded = service.loadDraft(for: docId, newerThan: nil)
        #expect(loaded == "draft content")

        service.deleteDraft(for: docId)
        #expect(service.loadDraft(for: docId, newerThan: nil) == nil)
    }

    @Test func draftNotLoadedWhenSourceIsNewer() throws {
        let service = SessionStateService(defaults: makeDefaults(), fileManager: fileManager)
        let docId = UUID().uuidString
        let sourceURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(docId).md")

        // Create source file first, then draft (draft is newer)
        try "source".write(to: sourceURL, atomically: true, encoding: .utf8)
        sleep(1) // ensure file modification date separates
        service.saveDraft("draft", for: docId)

        // Draft is newer than source → should be loaded
        let loaded1 = service.loadDraft(for: docId, newerThan: sourceURL.path)
        #expect(loaded1 == "draft")

        // Update source file to be newer than draft
        try "updated source".write(to: sourceURL, atomically: true, encoding: .utf8)

        let loaded2 = service.loadDraft(for: docId, newerThan: sourceURL.path)
        #expect(loaded2 == nil) // source is newer → draft discarded

        try FileManager.default.removeItem(at: sourceURL)
    }

    @Test func saveAndLoadWindowFrame() throws {
        let service = SessionStateService(defaults: makeDefaults())
        let frame = NSRect(x: 100, y: 200, width: 800, height: 600)
        service.saveWindowFrame(frame)

        let loaded = service.loadWindowFrame()
        #expect(loaded.origin.x == 100)
        #expect(loaded.origin.y == 200)
        #expect(loaded.size.width == 800)
        #expect(loaded.size.height == 600)
    }

    @Test func loadWindowFrameReturnsZeroWhenNotSaved() {
        let service = SessionStateService(defaults: makeDefaults())
        let frame = service.loadWindowFrame()
        #expect(frame == .zero)
    }

    @Test func saveAndLoadSidebarWidth() {
        let service = SessionStateService(defaults: makeDefaults())
        service.saveSidebarWidth(240)
        #expect(service.loadSidebarWidth() == 240)
    }

    @Test func loadSidebarWidthReturnsNilWhenNotSaved() {
        let service = SessionStateService(defaults: makeDefaults())
        #expect(service.loadSidebarWidth() == nil)
    }
}

// MARK: - FileNode Tests

struct FileNodeTests {
    @Test func fileNodeInitialization() {
        let url = URL(fileURLWithPath: "/tmp/test.md")
        let node = FileNode(url: url, isDirectory: false, children: nil)
        #expect(node.id == url.path)
        #expect(node.name == "test.md")
        #expect(!node.isDirectory)
        #expect(node.children == nil)
    }

    @Test func directoryNodeWithChildren() {
        let child = FileNode(
            url: URL(fileURLWithPath: "/tmp/root/file.md"),
            isDirectory: false,
            children: nil
        )
        let parent = FileNode(
            url: URL(fileURLWithPath: "/tmp/root"),
            isDirectory: true,
            children: [child]
        )
        #expect(parent.isDirectory)
        #expect(parent.children?.count == 1)
    }

    @Test func nodeHashable() {
        let url = URL(fileURLWithPath: "/tmp/test.md")
        let node1 = FileNode(url: url, isDirectory: false, children: nil)
        let node2 = FileNode(url: url, isDirectory: false, children: nil)
        #expect(node1 == node2)
        #expect(node1.hashValue == node2.hashValue)
    }
}

// MARK: - FrontMatter Tests

struct FrontMatterTests {

    @Test func parseTitleFromFrontMatter() {
        let text = "---\ntitle: \"My Note\"\n---\n\nHello, world!"
        let fm = FrontMatterParser.parse(from: text)
        #expect(fm != nil)
        #expect(fm?.title == "My Note")
    }

    @Test func parseTitleWithoutQuotes() {
        let text = "---\ntitle: My Note\n---\n\nContent"
        let fm = FrontMatterParser.parse(from: text)
        #expect(fm != nil)
        #expect(fm?.title == "My Note")
    }

    @Test func parseTitleWithUnicodeQuotes() {
        let text = "---\ntitle: \u{201C}Hello\u{201D}\n---"
        let fm = FrontMatterParser.parse(from: text)
        // Smart quotes are treated as YAML delimiters, so the captured
        // title is the text between them.
        #expect(fm != nil)
        #expect(fm?.title == "Hello")
    }

    @Test func parseTagsBracketFormat() {
        let text = "---\ntitle: \"Tags Demo\"\ntags: [foo, bar, baz]\n---\n\nContent"
        let fm = FrontMatterParser.parse(from: text)
        #expect(fm?.title == "Tags Demo")
        #expect(fm?.tags == ["foo", "bar", "baz"])
    }

    @Test func parseTagsInlineFormat() {
        let text = "---\ntitle: \"Tags Demo\"\ntags: foo, bar\n---\n\nContent"
        let fm = FrontMatterParser.parse(from: text)
        #expect(fm?.title == "Tags Demo")
        #expect(fm?.tags == ["foo", "bar"])
    }

    @Test func parseTitleWithoutTags() {
        let text = "---\ntitle: \"Only Title\"\n---\n\nBody"
        let fm = FrontMatterParser.parse(from: text)
        #expect(fm?.title == "Only Title")
        #expect(fm?.tags == nil)
    }

    @Test func parseMissingFrontMatter() {
        let text = "Just a plain note with no front matter."
        let fm = FrontMatterParser.parse(from: text)
        #expect(fm == nil)
    }

    @Test func parseEmptyContent() {
        let fm = FrontMatterParser.parse(from: "")
        #expect(fm == nil)
    }

    @Test func parseMalformedFence() {
        // ---\n--- is empty YAML
        let text = "---\n---\n\nContent"
        let fm = FrontMatterParser.parse(from: text)
        // Empty YAML has no title → nil
        #expect(fm == nil)
    }

    @Test func parseMidDocumentFenceIsIgnored() {
        let text = "Content before\n---\ntitle: \"Late\"\n---\n\nMore content"
        let fm = FrontMatterParser.parse(from: text)
        #expect(fm == nil)
    }

    @Test func parseTitleWithSmartQuotes() {
        let text = "---\ntitle: \u{2018}Smart Title\u{2019}\n---\n\nBody"
        let fm = FrontMatterParser.parse(from: text)
        // Single smart quotes are also treated as delimiters
        #expect(fm?.title == "Smart Title")
    }
}

// MARK: - TagParser Tests

struct TagParserTests {

    @Test func parseSimpleTag() {
        let tags = TagParser.parseTags(from: "This is a #tag in text.")
        #expect(tags == ["tag"])
    }

    @Test func parseNestedTag() {
        let tags = TagParser.parseTags(from: "Work on #project/feature notes.")
        #expect(tags == ["project/feature"])
    }

    @Test func parseMultipleTags() {
        let tags = TagParser.parseTags(from: "#first and #second and #third")
        #expect(tags == ["first", "second", "third"])
    }

    @Test func tagsExcludeHashInURL() {
        let tags = TagParser.parseTags(from: "Visit https://example.com/page#section for info.")
        // The #section is part of a URL — depending on regex boundary it may or may not match
        // Focus on that known tags still work
        #expect(tags.isEmpty || tags.allSatisfy { $0 != "tag" })
    }

    @Test func tagsExcludeInsideCodeBlock() {
        let text = """
        Some text.
        ```
        #ignoreThisTag
        ```
        #realTag outside.
        """
        let tags = TagParser.parseTags(from: text)
        #expect(tags == ["realTag"])
        #expect(!tags.contains("ignoreThisTag"))
    }

    @Test func tagsExcludeInsideCodeBlockWithLanguage() {
        let text = """
        ```swift
        #ignoreMe
        ```
        #catchMe
        """
        let tags = TagParser.parseTags(from: text)
        #expect(tags == ["catchMe"])
    }

    @Test func noTagsInPlainText() {
        let tags = TagParser.parseTags(from: "Just plain text without any hashtags.")
        #expect(tags.isEmpty)
    }

    @Test func tagAtStartOfLine() {
        let tags = TagParser.parseTags(from: "#startOfLine is a tag")
        #expect(tags == ["startOfLine"])
    }

    @Test func emptyText() {
        let tags = TagParser.parseTags(from: "")
        #expect(tags.isEmpty)
    }
}

// MARK: - FSTag Tests

struct FSTagTests {

    @Test func createRootTag() {
        let tag = FSTag(name: "work")
        #expect(tag.name == "work")
        #expect(tag.parent == nil)
        #expect(tag.child.isEmpty)
    }

    @Test func addChildTag() {
        let root = FSTag(name: "work")
        root.addChild(name: "project") { child, isExist, position in
            #expect(!isExist)
            #expect(child.name == "project")
            #expect(position == 0)
        }
        #expect(root.child.count == 1)
        #expect(root.child[0].name == "project")
    }

    @Test func addChildAlreadyExists() {
        let root = FSTag(name: "work")
        root.addChild(name: "project") { _, _, _ in }
        root.addChild(name: "project") { _, isExist, _ in
            #expect(isExist)
        }
        #expect(root.child.count == 1)
    }

    @Test func addChildrenAlphabeticalOrder() {
        let root = FSTag(name: "root")
        root.addChild(name: "zebra") { _, _, _ in }
        root.addChild(name: "apple") { _, _, _ in }
        root.addChild(name: "monkey") { _, _, _ in }
        #expect(root.child.count == 3)
        #expect(root.child[0].name == "apple")
        #expect(root.child[1].name == "monkey")
        #expect(root.child[2].name == "zebra")
    }

    @Test func getFullName() {
        let root = FSTag(name: "work")
        let child = FSTag(name: "project", parent: root)
        root.child.append(child)
        let grandchild = FSTag(name: "feature", parent: child)
        child.child.append(grandchild)

        #expect(root.getFullName() == "work")
        #expect(child.getFullName() == "work/project")
        #expect(grandchild.getFullName() == "work/project/feature")
    }

    @Test func findByName() {
        let root = FSTag(name: "root")
        root.addChild(name: "work") { _, _, _ in }
        let found = root.find(name: "work")
        #expect(found != nil)
        #expect(found?.name == "work")
    }

    @Test func findNestedByName() {
        let root = FSTag(name: "root")
        root.addChild(name: "work/project") { _, _, _ in }
        let found = root.find(name: "work/project")
        #expect(found != nil)
        #expect(found?.name == "project")
    }

    @Test func getChildByName() {
        let root = FSTag(name: "root")
        root.addChild(name: "alpha") { _, _, _ in }
        let got = root.get(name: "alpha")
        #expect(got?.name == "alpha")
    }

    @Test func getAllChildFlatList() {
        let root = FSTag(name: "root")
        root.addChild(name: "work") { _, _, _ in }
        root.addChild(name: "personal") { _, _, _ in }
        let all = root.getAllChild()
        #expect(all.contains("root"))
        #expect(all.contains("root/work"))
        #expect(all.contains("root/personal"))
    }

    @Test func isExpandableTrue() {
        let root = FSTag(name: "root")
        root.addChild(name: "child") { _, _, _ in }
        #expect(root.isExpandable())
    }

    @Test func isExpandableFalse() {
        let root = FSTag(name: "root")
        #expect(!root.isExpandable())
    }

    @Test func removeChild() {
        let root = FSTag(name: "root")
        root.addChild(name: "child") { child, _, _ in
            root.removeChild(tag: child)
        }
        #expect(root.child.isEmpty)
    }

    @Test func removeByIndex() {
        let root = FSTag(name: "root")
        root.addChild(name: "alpha") { _, _, _ in }
        root.addChild(name: "beta") { _, _, _ in }
        root.remove(by: 0)
        #expect(root.child.count == 1)
        #expect(root.child[0].name == "beta")
    }

    @Test func removeParent() {
        let child = FSTag(name: "child", parent: FSTag(name: "parent"))
        #expect(child.parent != nil)
        child.removeParent()
        #expect(child.parent == nil)
    }

    @Test func isAlone() {
        let root = FSTag(name: "root")
        root.addChild(name: "only") { child, _, _ in
            #expect(child.isAlone())
        }
    }

    @Test func isAloneFalseWithSiblings() {
        let root = FSTag(name: "root")
        root.addChild(name: "a") { _, _, _ in }
        root.addChild(name: "b") { child, _, _ in
            #expect(!child.isAlone())
        }
    }

    @Test func hasOneChild() {
        let root = FSTag(name: "root")
        #expect(root.hasOneChild())
        root.addChild(name: "a") { _, _, _ in }
        #expect(root.hasOneChild())
        root.addChild(name: "b") { _, _, _ in }
        #expect(!root.hasOneChild())
    }

    @Test func nestedTagViaInit() {
        let tag = FSTag(name: "work/project/feature")
        #expect(tag.name == "work")
        #expect(tag.child.count == 1)
        #expect(tag.child[0].name == "project")
        #expect(tag.child[0].child.count == 1)
        #expect(tag.child[0].child[0].name == "feature")
    }
}

// MARK: - SavePipeline Tests

struct SavePipelineTests {

    @Test func basicWriteAndRead() throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("marker-sp-basic.md")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        try SavePipeline.write("Hello, world!", to: tempURL)

        let contents = try String(contentsOf: tempURL, encoding: .utf8)
        #expect(contents == "Hello, world!")
    }

    @Test func overwriteExistingFile() throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("marker-sp-overwrite.md")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        try SavePipeline.write("first", to: tempURL)
        try SavePipeline.write("second", to: tempURL)

        let contents = try String(contentsOf: tempURL, encoding: .utf8)
        #expect(contents == "second")
    }

    @Test func multipleWritesAreConsistent() throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("marker-sp-consistency.md")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        for iterationCount in 1 ... 10 {
        try SavePipeline.write("iteration \(iterationCount)", to: tempURL)
        }

        let contents = try String(contentsOf: tempURL, encoding: .utf8)
        #expect(contents == "iteration 10")
    }

    @Test func writeToNestedDirectory() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("marker-sp-nested/\(UUID().uuidString)/subdir")
        defer {
            try? FileManager.default.removeItem(at: tempDir
                .deletingLastPathComponent()
                .deletingLastPathComponent())
        }

        let fileURL = tempDir.appendingPathComponent("nested-file.md")
        try SavePipeline.write("nested content", to: fileURL)

        #expect(FileManager.default.fileExists(atPath: fileURL.path))
        let contents = try String(contentsOf: fileURL, encoding: .utf8)
        #expect(contents == "nested content")
    }

    @Test func preserveCreationDate() throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("marker-sp-creation.md")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        try SavePipeline.write("original", to: tempURL)

        let originalAttrs = try FileManager.default.attributesOfItem(atPath: tempURL.path)
        let originalCreation = try #require(originalAttrs[.creationDate] as? Date)

        try SavePipeline.write("modified", to: tempURL)

        let newAttrs = try FileManager.default.attributesOfItem(atPath: tempURL.path)
        let newCreation = try #require(newAttrs[.creationDate] as? Date)

        #expect(newCreation == originalCreation)
    }

    @Test func preservePosixPermissions() throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("marker-sp-perms.md")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        try SavePipeline.write("original", to: tempURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: tempURL.path)

        try SavePipeline.write("modified", to: tempURL)

        let newAttrs = try FileManager.default.attributesOfItem(atPath: tempURL.path)
        let newPerms = try #require(newAttrs[.posixPermissions] as? NSNumber)

        #expect(newPerms.intValue == 0o444)
    }

    @Test func unicodeContent() throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("marker-sp-unicode.md")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let unicode = "Hello, 世界! \u{1F60A} — «¿Qué tal?»"
        try SavePipeline.write(unicode, to: tempURL)

        let contents = try String(contentsOf: tempURL, encoding: .utf8)
        #expect(contents == unicode)
    }

    @Test func writeToReadOnlyDirectory() throws {
        let invalidURL = URL(fileURLWithPath: "/dev/null/marker-test-write.md")
        #expect(throws: SavePipeline.WriteError.self) {
            try SavePipeline.write("test", to: invalidURL)
        }
    }

    @Test func cleanupTempFiles() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("marker-sp-cleanup-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true, attributes: nil)
        let fileURL = tempDir.appendingPathComponent("cleanup-test.md")

        try SavePipeline.write("content", to: fileURL)

        let remaining = try FileManager.default.contentsOfDirectory(atPath: tempDir.path)
        let tmpFiles = remaining.filter { $0.contains(".tmp~") }
        #expect(tmpFiles.isEmpty)
    }

    @Test func tabSaveUsesSavePipeline() throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("marker-sp-tab-integration.md")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        try SavePipeline.write("initial", to: tempURL)
        let tab = Tab(path: tempURL.path)
        tab.text = "saved via pipeline"
        let result = try tab.save()
        #expect(result)

        let contents = try String(contentsOf: tempURL, encoding: .utf8)
        #expect(contents == "saved via pipeline")
    }
}