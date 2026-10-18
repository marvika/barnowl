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
                          home + "/Library/Application Support", "/Library", "/Applications", "/"] {
            #expect(!roots.contains(forbidden))
        }
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
        let monthAgo = Date().addingTimeInterval(-30 * 86_400)
        for old in ["Downloads/Old Installer.dmg", "Downloads/Old report.pdf"] {
            try fm.setAttributes([.modificationDate: monthAgo], ofItemAtPath: home + "/" + old)
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
        if xcodeOpen {
            // Never while Xcode is open.
            #expect(outcome.skipped.first?.1 == "appRunning(\"com.apple.dt.Xcode\")")
            #expect(exists("Library/Developer/Xcode/DerivedData/App-abc/Build/Products/app.o"))
        } else {
            #expect(outcome.skipped.isEmpty, "skipped: \(outcome.skipped)")
            #expect(!exists("Library/Developer/Xcode/DerivedData"))
        }
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
        #expect(CleanupRunner.undo(outcome.trashed) == 1)
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
