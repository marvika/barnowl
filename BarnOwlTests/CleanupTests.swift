import AppKit
import Foundation
import Testing
@testable import BarnOwl

/// The safety gate, against the real home folder (read-only checks).
struct CleanupGateTests {
    private let home = FileManager.default.homeDirectoryForCurrentUser.path
    private func rule(_ id: String) throws -> CleanupRule { try #require(CleanupRule.all.first { $0.id == id }) }

    @Test func refusesPathsOutsideTheRulesFolders() throws {
        let caches = try rule("app-caches")
        #expect(CleanupGate.check("/", rule: caches) == .outsideAllowedFolders)
        #expect(CleanupGate.check(home, rule: caches) == .outsideAllowedFolders)
        #expect(CleanupGate.check(home + "/Documents", rule: caches) == .outsideAllowedFolders)
        #expect(CleanupGate.check("/System/Library", rule: caches) == .outsideAllowedFolders)
    }

    @Test func refusesTrickyPaths() throws {
        let caches = try rule("app-caches")
        #expect(CleanupGate.check("Library/Caches/x", rule: caches) == .notAbsolute)
        #expect(CleanupGate.check(home + "/Library/Caches/../Preferences", rule: caches) == .notAbsolute)
        #expect(CleanupGate.check(home + "/Library/Caches/does-not-exist-\(UUID())", rule: caches) == .notFound)
    }

    @Test func rulesThatOnlyShowNeverRemoveAnything() throws {
        for shown in CleanupRule.all where shown.safety == .yourCall {
            for path in shown.expandedPaths where FileManager.default.fileExists(atPath: path) {
                #expect(CleanupGate.check(path, rule: shown, wholeFolderAllowed: true) != nil)
            }
        }
    }

    @Test func neverOffersPersonalOrSystemFolders() {
        let roots = CleanupGate.allowedRoots()
        for forbidden in [home, home + "/Library", home + "/Documents", home + "/Desktop", home + "/Pictures",
                          home + "/Library/Application Support", "/Library", "/"] {
            #expect(!roots.contains(forbidden))
        }
        // Applications only for picking apps one by one, to the Trash.
        for rule in CleanupRule.all where rule.paths.contains("/Applications") {
            #expect(rule.pickItems && rule.extensions == ["app"], "\(rule.id)")
            if case .trash = rule.method {} else { Issue.record("\(rule.id) must use the Trash") }
        }
    }

    @Test func toolCleanUpsThatRemoveMoreThanCachesAsk() throws {
        #expect(try rule("simulators-unavailable").needsConfirmation)
        #expect(try rule("homebrew").needsConfirmation)
        #expect(try rule("simulators-unavailable").safety != .safe)
        #expect(try !rule("npm").needsConfirmation)
    }

    @Test func keepIgnoresCase() throws {
        let caches = try rule("app-caches")
        #expect(caches.keeps("homebrew") && caches.keeps("HOMEBREW"))
        #expect(!caches.allows(URL(fileURLWithPath: home + "/Library/Caches/homebrew"), size: nil))
    }

    @Test(arguments: ["/Users/x/Library/Mobile Documents/com~apple~CloudDocs/Thesis",
                      "/Users/x/Library/Application Support/Slack", "/Users/x/Library/Messages/Attachments",
                      "/Users/x/Library/Containers/com.apple.mail", "/Users/x/Documents", "/Users/x",
                      "/Users/x/.ssh/id_ed25519", "/Applications/Xcode.app/Contents/Developer", "/private/var/vm",
                      // The protected folders themselves, and the folders holding them.
                      "/Users/x/Library/Containers", "/Users/x/Library/Mobile Documents", "/opt/homebrew",
                      "/opt/homebrew/Cellar", "/Users/x/Pictures/Photos Library.photoslibrary"])
    func basketRefusesWhatYoudMiss(path: String) {
        #expect(BarnModel.basketRefusal(path, home: "/Users/x") != nil)
    }

    @Test(arguments: ["/Users/x/Downloads/dataset.zip", "/Users/x/Movies/Holiday.mov", "/Users/x/Projects/app/node_modules",
                      "/Applications/Blender.app"])
    func basketTakesOrdinaryThings(path: String) {
        #expect(BarnModel.basketRefusal(path, home: "/Users/x") == nil)
    }

    @Test(arguments: ["com.apple.Safari", "com.apple.bird", "com.agilebits.onepassword7", "com.bitwarden.desktop",
                      "com.crowdstrike.falcon", "com.wireguard.macos", "CloudKit"])
    func sensitiveCachesAreNeverOffered(name: String) {
        #expect(CleanupRule.isSensitiveCache(name))
    }

    @Test(arguments: ["com.spotify.client", "com.tinyspeck.slackmacgap", "JetBrains", "com.microsoft.VSCode"])
    func ordinaryCachesCanBeOffered(name: String) {
        #expect(!CleanupRule.isSensitiveCache(name))
    }

    @Test func confirmationsForWhatCantBeUndone() throws {
        #expect(try rule("trash").needsConfirmation)
        #expect(try rule("device-support").needsConfirmation)
        #expect(try !rule("xcode-derived-data").needsConfirmation)
        #expect(try !rule("app-caches").needsConfirmation)   // to the Trash, with undo
    }

    @Test func ruleIDsAreUnique() {
        let ids = CleanupRule.all.map(\.id)
        #expect(Set(ids).count == ids.count)
    }
}

/// Every kind of clean-up, run for real against a stand-in home folder, so
/// nothing of yours is touched.
@Suite(.serialized)
struct CleanupEndToEndTests {
    let home: String
    private let fm = FileManager.default

    init() throws {
        home = fm.temporaryDirectory.appending(path: "barn-home-\(UUID().uuidString)").path
        let files: [(String, Int)] = [
            ("Library/Developer/Xcode/DerivedData/App-abc/Build/Products/app.o", 200_000),
            ("Library/Developer/Xcode/DerivedData/Other-def/Index/data", 150_000),
            ("Library/Caches/com.example.app/cache.db", 300_000),
            ("Library/Caches/com.example.second/blob", 250_000),
            ("Library/Caches/com.apple.Safari/Cache.db", 300_000),
            ("Library/Caches/com.bitwarden.desktop/vault-cache", 300_000),
            ("Library/Caches/Homebrew/downloads/pkg.tar.gz", 300_000),
            ("Library/Caches/CocoaPods/Pods/Release/pod.zip", 300_000),
            ("Library/Logs/DiagnosticReports/crash.ips", 150_000),
            ("Library/Logs/SomeApp/run.log", 150_000),
            ("Downloads/Old Installer.dmg", 300_000),
            ("Downloads/New Installer.dmg", 300_000),
            ("Downloads/Old report.pdf", 300_000),
            (".Trash/thrown away.txt", 150_000),
            (".Trash/Old Folder/inside.txt", 150_000),
            ("Documents/precious.txt", 10_000),
        ]
        for (path, size) in files {
            let url = URL(fileURLWithPath: home + "/" + path)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data((0..<size).map { _ in UInt8.random(in: 0...255) }).write(to: url)
        }
        // A cache that's really a link to your documents.
        try fm.createSymbolicLink(atPath: home + "/Library/Caches/sneaky-link", withDestinationPath: home + "/Documents")
        // Downloads count from when they arrived, not the file's own date.
        let monthAgo = Date().addingTimeInterval(-30 * 86_400)
        for old in ["Downloads/Old Installer.dmg", "Downloads/Old report.pdf"] {
            try Self.setAddedDate(monthAgo, of: home + "/" + old)
        }
        try fm.setAttributes([.modificationDate: Date(timeIntervalSince1970: 0)], ofItemAtPath: home + "/Downloads/New Installer.dmg")
    }

    /// Sets when a file arrived in its folder (ATTR_CMN_ADDEDTIME).
    static func setAddedDate(_ date: Date, of path: String) throws {
        var request = attrlist()
        request.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        request.commonattr = attrgroup_t(ATTR_CMN_ADDEDTIME)
        var time = timespec(tv_sec: Int(date.timeIntervalSince1970), tv_nsec: 0)
        guard setattrlist(path, &request, &time, MemoryLayout<timespec>.size, 0) == 0 else {
            throw CocoaError(.fileWriteUnknown)
        }
    }

    private func rule(_ id: String) throws -> CleanupRule { try #require(CleanupRule.all.first { $0.id == id }) }
    private func exists(_ path: String) -> Bool { fm.fileExists(atPath: home + "/" + path) }
    private func tidyUp() { try? fm.removeItem(atPath: home) }

    @Test func deletesRebuildableBuildFilesWhole() async throws {
        defer { tidyUp() }
        let outcome = await CleanupRunner.run(try rule("xcode-derived-data"), items: [], home: home)
        let xcodeOpen = await MainActor.run {
            !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dt.Xcode").isEmpty
        }
        let building = await CleanupRunner.busyTool(try rule("xcode-derived-data")) != nil
        if xcodeOpen || building {
            // Never while Xcode is open or a build is running (like the one running these tests).
            #expect(!outcome.skipped.isEmpty)
            #expect(exists("Library/Developer/Xcode/DerivedData/App-abc/Build/Products/app.o"))
        } else {
            #expect(outcome.skipped.isEmpty, "skipped: \(outcome.skipped)")
            #expect(!exists("Library/Developer/Xcode/DerivedData"))
        }
        #expect(exists("Documents/precious.txt"))
    }

    @Test func deletesADownloadCacheWhole() async throws {
        defer { tidyUp() }
        let outcome = await CleanupRunner.run(try rule("cocoapods"), items: [], home: home)
        #expect(outcome.skipped.isEmpty, "skipped: \(outcome.skipped)")
        #expect(!exists("Library/Caches/CocoaPods"))
        #expect(exists("Library/Caches/com.example.app/cache.db"))
        #expect(exists("Documents/precious.txt"))
    }

    @Test func offersOnlyOrdinaryAppCaches() async throws {
        defer { tidyUp() }
        let items = await BarnModel.items(for: try rule("app-caches"), home: home).map(\.name)
        #expect(Set(items) == ["com.example.app", "com.example.second"])
    }

    @Test func trashesPickedCachesAndRefusesEverythingElse() async throws {
        defer { tidyUp() }
        let caches = try rule("app-caches")
        let attempts = [home + "/Library/Caches/com.example.app",          // fine
                        home + "/Library/Caches/com.apple.Safari",         // Apple's own
                        home + "/Library/Caches/com.bitwarden.desktop",    // a password manager
                        home + "/Library/Caches/Homebrew",                 // kept for its own rule
                        home + "/Library/Caches/sneaky-link",              // a symlink
                        home + "/Documents/precious.txt",                  // not a cache
                        home + "/Library/Caches",                          // the folder itself
                        home + "/Library/Caches/../../Documents"]          // a trick
        let outcome = await CleanupRunner.run(caches, items: attempts, home: home)
        #expect(outcome.done == [home + "/Library/Caches/com.example.app"])
        #expect(!exists("Library/Caches/com.example.app"))
        for kept in ["Library/Caches/com.apple.Safari", "Library/Caches/com.bitwarden.desktop", "Library/Caches/Homebrew",
                     "Library/Caches/sneaky-link", "Documents/precious.txt", "Library/Caches/com.example.second"] {
            #expect(exists(kept), "\(kept) should be kept")
        }
        // And back it comes.
        #expect(CleanupRunner.undo(outcome.trashed).isEmpty)
        #expect(exists("Library/Caches/com.example.app/cache.db"))
    }

    @Test func aRuleCantReachIntoAnotherRulesFolder() async throws {
        defer { tidyUp() }
        let outcome = await CleanupRunner.run(try rule("logs"), items: [home + "/Library/Caches/com.example.app"], home: home)
        #expect(outcome.done.isEmpty)
        #expect(exists("Library/Caches/com.example.app"))
    }

    @Test func keepsCrashReportsWhenTidyingLogs() async throws {
        defer { tidyUp() }
        let logs = try rule("logs")
        #expect(await BarnModel.items(for: logs, home: home).map(\.name) == ["SomeApp"])
        let outcome = await CleanupRunner.run(logs, items: [home + "/Library/Logs/DiagnosticReports"], home: home)
        #expect(outcome.done.isEmpty)
        #expect(exists("Library/Logs/DiagnosticReports/crash.ips"))
    }

    @Test func offersOnlyOldInstallers() async throws {
        defer { tidyUp() }
        let items = await BarnModel.items(for: try rule("installers"), home: home).map(\.name)
        #expect(items == ["Old Installer.dmg"])
    }

    @Test func refusesWhatsReachedThroughALinkedFolder() throws {
        // sneaky-link → Documents, so this is really Documents/precious.txt.
        let refusal = CleanupGate.check(home + "/Library/Caches/sneaky-link/precious.txt", rule: try rule("app-caches"), home: home)
        #expect(refusal == .outsideAllowedFolders)
    }

    @Test func refusesARuleFolderThatIsALink() throws {
        defer { tidyUp() }
        // ~/Library/Logs swapped for a link to Documents: what's in it isn't logs.
        try fm.removeItem(atPath: home + "/Library/Logs")
        try fm.createSymbolicLink(atPath: home + "/Library/Logs", withDestinationPath: home + "/Documents")
        let refusal = CleanupGate.check(home + "/Library/Logs/precious.txt", rule: try rule("logs"), home: home)
        #expect(refusal == .symlink)
        #expect(CleanupGate.check(home + "/Library/Caches/com.example.app", rule: try rule("app-caches"), home: home) == nil)
    }

    @Test func emptiesFromTheTrashOnlyWhatItPutThere() throws {
        defer { tidyUp() }
        let original = URL(fileURLWithPath: home + "/.Trash/thrown away.txt")
        TrashLedger.note(original)
        // Something else takes its name in the Trash.
        try fm.removeItem(at: original)
        try Data("other".utf8).write(to: original)
        #expect(throws: (any Error).self) { try CleanupRunner.removeFromTrash(original, home: home) }
        #expect(exists(".Trash/thrown away.txt"))
    }

    @Test func basketKeepsPackagesWhole() throws {
        defer { tidyUp() }
        for inside in ["Tool.app/Contents/Resources", "Build.xcarchive/Products"] {
            try fm.createDirectory(atPath: home + "/Projects/" + inside, withIntermediateDirectories: true)
        }
        #expect(BarnModel.basketRefusal(home + "/Projects/Tool.app/Contents/Resources", home: "/Users/x") == "inside an app")
        #expect(BarnModel.basketRefusal(home + "/Projects/Build.xcarchive/Products", home: "/Users/x") != nil)
        #expect(BarnModel.basketRefusal(home + "/Projects/Tool.app", home: "/Users/x") == nil)
    }

    @Test func undoSaysWhatItCouldntPutBack() async throws {
        defer { tidyUp() }
        let caches = try rule("app-caches")
        let outcome = await CleanupRunner.run(caches, items: [home + "/Library/Caches/com.example.app",
                                                              home + "/Library/Caches/com.example.second"], home: home)
        #expect(outcome.trashed.count == 2)
        // The app made its cache folder again in the meantime.
        try fm.createDirectory(atPath: home + "/Library/Caches/com.example.app", withIntermediateDirectories: false)
        let stuck = CleanupRunner.undo(outcome.trashed)
        #expect(stuck.map(\.from.lastPathComponent) == ["com.example.app"])
        #expect(exists("Library/Caches/com.example.second/blob"))
        try? fm.removeItem(at: stuck[0].to)
    }

    @Test func removesFromTheTrashOnlyWhatsInIt() throws {
        defer { tidyUp() }
        #expect(throws: (any Error).self) {
            try CleanupRunner.removeFromTrash(URL(fileURLWithPath: home + "/Documents/precious.txt"), home: home)
        }
        try fm.createSymbolicLink(atPath: home + "/.Trash/link", withDestinationPath: home + "/Documents")
        #expect(throws: (any Error).self) { try CleanupRunner.removeFromTrash(URL(fileURLWithPath: home + "/.Trash/link"), home: home) }
        try CleanupRunner.removeFromTrash(URL(fileURLWithPath: home + "/.Trash/thrown away.txt"), home: home)
        #expect(!exists(".Trash/thrown away.txt"))
        #expect(exists("Documents/precious.txt"))
    }

    @Test func emptiesTheTrashButKeepsIt() async throws {
        defer { tidyUp() }
        let outcome = await CleanupRunner.run(try rule("trash"), items: [], home: home)
        #expect(outcome.skipped.isEmpty)
        #expect(exists(".Trash"))
        #expect(try fm.contentsOfDirectory(atPath: home + "/.Trash").isEmpty)
        #expect(exists("Documents/precious.txt"))
    }

    @Test func rulesThatOnlyShowDoNothing() async throws {
        defer { tidyUp() }
        let outcome = await CleanupRunner.run(try rule("iphone-backups"), items: [], home: home)
        #expect(outcome.done.isEmpty)
        #expect(exists("Documents/precious.txt"))
    }
}
