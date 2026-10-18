import Foundation
import Testing
@testable import BarnOwl

struct CleanupTests {
    private let home = FileManager.default.homeDirectoryForCurrentUser.path

    @Test func refusesPathsOutsideItsFolders() {
        #expect(CleanupGate.check("/") == .outsideAllowedFolders)
        #expect(CleanupGate.check(home) == .outsideAllowedFolders)
        #expect(CleanupGate.check(home + "/Documents") == .outsideAllowedFolders)
        #expect(CleanupGate.check("/System/Library") == .outsideAllowedFolders)
    }

    @Test func refusesTrickyPaths() {
        #expect(CleanupGate.check("Library/Caches/x") == .notAbsolute)
        #expect(CleanupGate.check(home + "/Library/Caches/../Preferences") == .notAbsolute)
        #expect(CleanupGate.check(home + "/Library/Caches/does-not-exist-\(UUID())") == .notFound)
    }

    @Test func keepsTheFoldersThemselves() throws {
        let caches = home + "/Library/Caches"
        try #require(FileManager.default.fileExists(atPath: caches))
        // Things can be taken out of ~/Library/Caches, but never the folder itself.
        #expect(CleanupGate.check(caches) == .isAllowedFolderItself)
        #expect(CleanupGate.check(caches, wholeFolderAllowed: true) == nil)
    }

    @Test func allowsItemsInsideItsFoldersButNotSymlinks() throws {
        let caches = URL(fileURLWithPath: home + "/Library/Caches")
        let item = caches.appending(path: "barn-owl-test-\(UUID().uuidString)")
        let link = caches.appending(path: "barn-owl-link-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: item, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: URL(fileURLWithPath: home + "/Documents"))
        defer {
            try? FileManager.default.removeItem(at: item)
            try? FileManager.default.removeItem(at: link)
        }
        #expect(CleanupGate.check(item.path) == nil)
        #expect(CleanupGate.check(link.path) == .symlink)
    }

    @Test func neverOffersPersonalOrSystemFolders() {
        let roots = CleanupGate.allowedRoots
        for forbidden in [home, home + "/Library", home + "/Documents", home + "/Library/Application Support", "/Library", "/"] {
            #expect(!roots.contains(forbidden))
        }
        // Rules that are only shown never open a folder for deletion.
        for rule in CleanupRule.all where rule.safety == .yourCall {
            for path in rule.expandedPaths { #expect(!roots.contains(path)) }
        }
    }

    @Test func ruleIDsAreUnique() {
        let ids = CleanupRule.all.map(\.id)
        #expect(Set(ids).count == ids.count)
    }
}
