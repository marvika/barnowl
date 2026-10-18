import AppKit
import Foundation

/// Something the owl knows how to tidy, and how safely.
///
/// Barn Owl's own list, written from what each app and tool documents about
/// its caches. It only names folders it knows; it never sweeps a whole
/// folder like ~/Library/Caches by pattern.
struct CleanupRule: Identifiable, Sendable {
    enum Safety: Int, Comparable, Sendable {
        /// Rebuilt automatically when needed; cleaned in one click.
        case safe
        /// Probably fine, but pick what goes.
        case review
        /// Worth knowing about, but yours to decide: never cleaned by Barn Owl.
        case yourCall

        static func < (lhs: Safety, rhs: Safety) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    enum Method: Sendable {
        /// Deleted straight away: caches the app or tool rebuilds.
        case delete
        /// Moved to the Trash, so it can be put back.
        case trash
        /// The tool's own clean-up command, run in a login shell so it finds
        /// the tool the way your Terminal does.
        case command(String)
        /// Shown only.
        case none
    }

    enum Group: String, CaseIterable, Sendable {
        case developer = "Developer"
        case browsers = "Browsers"
        case apps = "Apps"
        case downloads = "Downloads and Trash"
        case yours = "Yours to decide"
    }

    let id: String
    let title: String
    let detail: String
    let symbol: String
    let group: Group
    let safety: Safety
    let method: Method
    /// Folders it covers, ~ for home.
    let paths: [String]
    /// Lists what's inside each folder so you can pick, rather than taking
    /// the folder as a whole.
    var pickItems = false
    /// Only items older than this many days.
    var olderThanDays: Int?
    /// Only items with these extensions.
    var extensions: Set<String>?
    /// Names never offered, inside its folders.
    var keep: Set<String> = []
    /// Apps whose files these are; skipped while they're running.
    var ownerApps: [String] = []
    /// A command-line tool that must be installed for this to apply.
    var tool: String?
    var needsFullDiskAccess = false

    var expandedPaths: [String] { paths.map { ($0 as NSString).expandingTildeInPath } }
}

extension CleanupRule {
    static let all: [CleanupRule] = [
        // Developer
        CleanupRule(id: "xcode-derived-data", title: "Xcode build files",
                    detail: "DerivedData: intermediate build products and indexes. Xcode rebuilds them on the next build.",
                    symbol: "hammer.fill", group: .developer, safety: .safe, method: .delete,
                    paths: ["~/Library/Developer/Xcode/DerivedData"], ownerApps: ["com.apple.dt.Xcode"]),
        CleanupRule(id: "simulator-caches", title: "Simulator caches",
                    detail: "Caches the iOS Simulator rebuilds when it next starts.",
                    symbol: "iphone", group: .developer, safety: .safe, method: .delete,
                    paths: ["~/Library/Developer/CoreSimulator/Caches"],
                    ownerApps: ["com.apple.iphonesimulator", "com.apple.dt.Xcode"]),
        CleanupRule(id: "simulators-unavailable", title: "Simulators for old Xcodes",
                    detail: "Simulators whose runtime is no longer installed and can't run. Removed with xcrun simctl.",
                    symbol: "iphone.slash", group: .developer, safety: .safe,
                    method: .command("xcrun simctl delete unavailable"), paths: [],
                    ownerApps: ["com.apple.iphonesimulator"], tool: "xcrun"),
        CleanupRule(id: "device-support", title: "Device support files",
                    detail: "Debug symbols Xcode copies from each iPhone, iPad and Watch version you've connected. Copied again if you need one.",
                    symbol: "cable.connector", group: .developer, safety: .review, method: .delete,
                    paths: ["~/Library/Developer/Xcode/iOS DeviceSupport", "~/Library/Developer/Xcode/watchOS DeviceSupport",
                            "~/Library/Developer/Xcode/tvOS DeviceSupport", "~/Library/Developer/Xcode/visionOS DeviceSupport"],
                    pickItems: true, ownerApps: ["com.apple.dt.Xcode"]),
        CleanupRule(id: "homebrew", title: "Homebrew downloads",
                    detail: "Old versions and downloaded bottles. Cleaned with brew cleanup.",
                    symbol: "mug.fill", group: .developer, safety: .safe,
                    method: .command("brew cleanup --prune=all"), paths: ["~/Library/Caches/Homebrew"], tool: "brew"),
        CleanupRule(id: "npm", title: "npm cache", detail: "Packages npm keeps to install faster. Cleaned with npm cache clean.",
                    symbol: "shippingbox.fill", group: .developer, safety: .safe,
                    method: .command("npm cache clean --force"), paths: ["~/.npm/_cacache"], tool: "npm"),
        CleanupRule(id: "pnpm", title: "pnpm store", detail: "Packages no project uses any more. Cleaned with pnpm store prune.",
                    symbol: "shippingbox.fill", group: .developer, safety: .safe,
                    method: .command("pnpm store prune"), paths: ["~/Library/pnpm/store"], tool: "pnpm"),
        CleanupRule(id: "yarn", title: "Yarn cache", detail: "Packages Yarn keeps to install faster. Cleaned with yarn cache clean.",
                    symbol: "shippingbox.fill", group: .developer, safety: .safe,
                    method: .command("yarn cache clean"), paths: ["~/Library/Caches/Yarn"], tool: "yarn"),
        CleanupRule(id: "pip", title: "pip cache", detail: "Python packages pip keeps to install faster. Cleaned with pip cache purge.",
                    symbol: "shippingbox.fill", group: .developer, safety: .safe,
                    method: .command("pip3 cache purge"), paths: ["~/Library/Caches/pip"], tool: "pip3"),
        CleanupRule(id: "cocoapods", title: "CocoaPods cache", detail: "Downloaded pods, fetched again when needed.",
                    symbol: "shippingbox.fill", group: .developer, safety: .safe, method: .delete,
                    paths: ["~/Library/Caches/CocoaPods"]),
        CleanupRule(id: "swiftpm", title: "Swift package cache", detail: "Downloaded Swift packages, fetched again when needed.",
                    symbol: "swift", group: .developer, safety: .safe, method: .delete,
                    paths: ["~/Library/Caches/org.swift.swiftpm"], ownerApps: ["com.apple.dt.Xcode"]),
        CleanupRule(id: "go-build", title: "Go build cache", detail: "Compiled Go packages, rebuilt when needed.",
                    symbol: "hammer.fill", group: .developer, safety: .safe, method: .delete,
                    paths: ["~/Library/Caches/go-build"]),
        CleanupRule(id: "cargo", title: "Cargo downloads", detail: "Downloaded Rust crates, fetched again when needed.",
                    symbol: "shippingbox.fill", group: .developer, safety: .safe, method: .delete,
                    paths: ["~/.cargo/registry/cache"]),
        CleanupRule(id: "gradle", title: "Gradle caches",
                    detail: "Downloaded dependencies and build caches. Rebuilt when needed, but the next build downloads a lot.",
                    symbol: "shippingbox.fill", group: .developer, safety: .review, method: .delete,
                    paths: ["~/.gradle/caches"], pickItems: true),

        // Browsers: only their caches, never history, passwords or sign-ins.
        CleanupRule(id: "chrome", title: "Chrome cache", detail: "Pages and images Chrome keeps to load sites faster.",
                    symbol: "globe", group: .browsers, safety: .safe, method: .delete,
                    paths: ["~/Library/Caches/Google/Chrome"], ownerApps: ["com.google.Chrome"]),
        CleanupRule(id: "edge", title: "Edge cache", detail: "Pages and images Edge keeps to load sites faster.",
                    symbol: "globe", group: .browsers, safety: .safe, method: .delete,
                    paths: ["~/Library/Caches/Microsoft Edge"], ownerApps: ["com.microsoft.edgemac"]),
        CleanupRule(id: "brave", title: "Brave cache", detail: "Pages and images Brave keeps to load sites faster.",
                    symbol: "globe", group: .browsers, safety: .safe, method: .delete,
                    paths: ["~/Library/Caches/BraveSoftware"], ownerApps: ["com.brave.Browser"]),
        CleanupRule(id: "firefox", title: "Firefox cache", detail: "Pages and images Firefox keeps to load sites faster.",
                    symbol: "globe", group: .browsers, safety: .safe, method: .delete,
                    paths: ["~/Library/Caches/Firefox"], ownerApps: ["org.mozilla.firefox"]),
        CleanupRule(id: "arc", title: "Arc cache", detail: "Pages and images Arc keeps to load sites faster.",
                    symbol: "globe", group: .browsers, safety: .safe, method: .delete,
                    paths: ["~/Library/Caches/Arc"], ownerApps: ["company.thebrowser.Browser"]),
        CleanupRule(id: "safari", title: "Safari cache", detail: "Pages and images Safari keeps to load sites faster.",
                    symbol: "safari", group: .browsers, safety: .safe, method: .delete,
                    paths: ["~/Library/Caches/com.apple.Safari"], ownerApps: ["com.apple.Safari"],
                    needsFullDiskAccess: true),

        // Apps
        CleanupRule(id: "app-caches", title: "Other app caches",
                    detail: "Caches other apps keep. Most rebuild them, but a few keep things there, so pick what goes. They go to the Trash.",
                    symbol: "square.stack.3d.up.fill", group: .apps, safety: .review, method: .trash,
                    paths: ["~/Library/Caches"], pickItems: true,
                    keep: ["Homebrew", "Yarn", "pip", "CocoaPods", "org.swift.swiftpm", "go-build", "Google",
                           "Microsoft Edge", "BraveSoftware", "Firefox", "Arc", "com.apple.Safari", "CloudKit",
                           "com.apple.bird", "com.apple.akd", "FamilyCircle", "com.apple.ap.adprivacyd",
                           "com.apple.HomeKit", "com.apple.containermanagerd"]),
        CleanupRule(id: "logs", title: "App logs", detail: "Logs apps write as they run. Crash reports are kept.",
                    symbol: "doc.text.fill", group: .apps, safety: .review, method: .trash,
                    paths: ["~/Library/Logs"], pickItems: true, keep: ["DiagnosticReports", "Barn Owl"]),

        // Downloads and Trash
        CleanupRule(id: "installers", title: "Old installers",
                    detail: "Disk images and installer packages in Downloads, older than a week. Once installed, they're not needed.",
                    symbol: "arrow.down.app.fill", group: .downloads, safety: .review, method: .trash,
                    paths: ["~/Downloads"], pickItems: true, olderThanDays: 7,
                    extensions: ["dmg", "pkg", "mpkg", "xip", "iso"]),
        CleanupRule(id: "trash", title: "The Trash", detail: "What's in the Trash still takes space until it's emptied.",
                    symbol: "trash.fill", group: .downloads, safety: .review, method: .delete,
                    paths: ["~/.Trash"], needsFullDiskAccess: true),

        // Yours to decide: shown, never cleaned.
        CleanupRule(id: "iphone-backups", title: "iPhone and iPad backups",
                    detail: "Each backup can be many gigabytes. Manage them in Finder: select your device, then Manage Backups.",
                    symbol: "iphone.gen3", group: .yours, safety: .yourCall, method: .none,
                    paths: ["~/Library/Application Support/MobileSync/Backup"], needsFullDiskAccess: true),
        CleanupRule(id: "xcode-archives", title: "Xcode archives",
                    detail: "Builds you've archived. They hold the symbols needed to read crash reports, so keep the ones for versions people use.",
                    symbol: "archivebox.fill", group: .yours, safety: .yourCall, method: .none,
                    paths: ["~/Library/Developer/Xcode/Archives"]),
        CleanupRule(id: "simulator-devices", title: "Simulator devices",
                    detail: "Each simulator keeps its apps and data. Delete ones you don't use in Xcode → Devices and Simulators.",
                    symbol: "iphone", group: .yours, safety: .yourCall, method: .none,
                    paths: ["~/Library/Developer/CoreSimulator/Devices"]),
        CleanupRule(id: "docker", title: "Docker", detail: "Images, containers and volumes. Clean up in Docker Desktop, or with docker system prune.",
                    symbol: "shippingbox.circle.fill", group: .yours, safety: .yourCall, method: .none,
                    paths: ["~/Library/Containers/com.docker.docker/Data/vms"], needsFullDiskAccess: true),
    ]
}

// MARK: - The safety gate

/// Every deletion goes through here, once when it's offered and again right
/// before it happens. Anything it isn't sure about is kept.
enum CleanupGate {
    enum Refusal: Error, Equatable {
        case notAbsolute, notFound, symlink, outsideAllowedFolders, protected, isAllowedFolderItself, appRunning(String)
    }

    private static var home: String { FileManager.default.homeDirectoryForCurrentUser.path }

    /// The only folders anything may be removed from.
    static var allowedRoots: [String] {
        let rules = CleanupRule.all.filter { $0.safety != .yourCall }.flatMap(\.expandedPaths)
        return Array(Set(rules)).sorted()
    }

    /// Never touched, even inside an allowed folder.
    static var protectedPaths: [String] {
        ["/System", "/usr", "/bin", "/sbin", "/private/var/db", "/Library", "/Applications",
         home + "/Library/Mobile Documents", home + "/Library/Keychains", home + "/Library/Application Support",
         home + "/Library/Mail", home + "/Library/Messages", home + "/Documents", home + "/Desktop",
         home + "/Pictures", home + "/Movies", home + "/Music", home + "/.ssh", home + "/.claude", home + "/.config",
         home + "/.local"]
    }

    /// Whether `path` may be removed. `allowedRoot` is the rule folder it
    /// came from; removing that folder itself is only allowed when the rule
    /// says so (DerivedData can go as a whole, ~/Library/Caches can't).
    static func check(_ path: String, wholeFolderAllowed: Bool = false, ownerApps: [String] = []) -> Refusal? {
        guard path.hasPrefix("/") else { return .notAbsolute }
        let standard = (path as NSString).standardizingPath
        guard standard == path, !path.contains("/../"), !path.hasSuffix("/..") else { return .notAbsolute }
        var info = stat()
        guard lstat(path, &info) == 0 else { return .notFound }
        if info.st_mode & S_IFMT == S_IFLNK { return .symlink }
        // Follow symlinked parent folders, then check where it really is.
        let parent = (path as NSString).deletingLastPathComponent
        let real = URL(fileURLWithPath: parent).resolvingSymlinksInPath().path + "/" + (path as NSString).lastPathComponent
        for candidate in Set([path, real]) {
            guard let root = allowedRoots.first(where: { candidate == $0 || candidate.hasPrefix($0 + "/") }) else {
                return .outsideAllowedFolders
            }
            if candidate == root && !wholeFolderAllowed { return .isAllowedFolderItself }
            // An allowed folder can sit inside a protected one (Caches inside
            // Library); protection only applies outside allowed folders.
            if protectedPaths.contains(where: { candidate == $0 || (candidate.hasPrefix($0 + "/") && !root.hasPrefix($0 + "/")) }) {
                return .protected
            }
        }
        if let running = ownerApps.first(where: { !NSRunningApplication.runningApplications(withBundleIdentifier: $0).isEmpty }) {
            return .appRunning(running)
        }
        return nil
    }
}

// MARK: - Doing it

/// Removes, trashes or runs a tool's clean-up, after the gate says yes, and
/// writes what it did to ~/Library/Logs/Barn Owl/cleanup.log.
enum CleanupRunner {
    struct Outcome: Sendable {
        var done: [String] = []
        var skipped: [(String, String)] = []
        /// Moved to the Trash, original → where it went, for undo.
        var trashed: [(from: URL, to: URL)] = []
    }

    static let logURL: URL = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: "Library/Logs/Barn Owl/cleanup.log")

    /// Cleans `items` (paths inside the rule's folders), or the rule's
    /// folders themselves when `items` is empty.
    static func run(_ rule: CleanupRule, items: [String]) async -> Outcome {
        var outcome = Outcome()
        switch rule.method {
        case .none:
            return outcome
        case .command(let command):
            if let running = rule.ownerApps.first(where: { !NSRunningApplication.runningApplications(withBundleIdentifier: $0).isEmpty }) {
                outcome.skipped.append((command, "\(running) is running"))
                return outcome
            }
            let (status, output) = await shell(command)
            log("\(status == 0 ? "ran" : "failed (\(status))") \(command)\(output.isEmpty ? "" : ": " + output.prefix(300))")
            if status == 0 { outcome.done.append(command) } else { outcome.skipped.append((command, output)) }
            return outcome
        case .delete, .trash:
            let targets = items.isEmpty ? rule.expandedPaths : items
            for path in targets {
                if rule.keep.contains((path as NSString).lastPathComponent) {
                    outcome.skipped.append((path, "kept"))
                    continue
                }
                if let refusal = CleanupGate.check(path, wholeFolderAllowed: items.isEmpty && !rule.pickItems,
                                                   ownerApps: rule.ownerApps) {
                    if refusal != .notFound { outcome.skipped.append((path, "\(refusal)")) }
                    continue
                }
                do {
                    if case .trash = rule.method {
                        var resulting: NSURL?
                        try FileManager.default.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: &resulting)
                        if let resulting { outcome.trashed.append((URL(fileURLWithPath: path), resulting as URL)) }
                        log("trashed \(path)")
                    } else if rule.id == "trash" {
                        // Empty the Trash, but keep the Trash itself.
                        try emptyFolder(path)
                        log("emptied \(path)")
                    } else {
                        try FileManager.default.removeItem(atPath: path)
                        log("deleted \(path)")
                    }
                    outcome.done.append(path)
                } catch {
                    outcome.skipped.append((path, error.localizedDescription))
                    log("couldn't remove \(path): \(error.localizedDescription)")
                }
            }
            return outcome
        }
    }

    /// Puts trashed items back where they were.
    static func undo(_ trashed: [(from: URL, to: URL)]) -> Int {
        var restored = 0
        for item in trashed where !FileManager.default.fileExists(atPath: item.from.path) {
            if (try? FileManager.default.moveItem(at: item.to, to: item.from)) != nil {
                restored += 1
                log("put back \(item.from.path)")
            }
        }
        return restored
    }

    /// Empties a folder but keeps it (the Trash itself must stay).
    private static func emptyFolder(_ path: String) throws {
        for name in try FileManager.default.contentsOfDirectory(atPath: path) {
            try FileManager.default.removeItem(atPath: path + "/" + name)
        }
    }

    /// Runs a command in a login shell, like Terminal, so tools installed
    /// with Homebrew or a version manager are found. Gives up after two minutes.
    static func shell(_ command: String) async -> (Int32, String) {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-lc", command]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            process.terminationHandler = { finished in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                continuation.resume(returning: (finished.terminationStatus,
                                                String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)))
            }
            do {
                try process.run()
                DispatchQueue.global().asyncAfter(deadline: .now() + 120) { if process.isRunning { process.terminate() } }
            } catch {
                continuation.resume(returning: (-1, error.localizedDescription))
            }
        }
    }

    /// Whether a command-line tool is installed, as your login shell sees it.
    static func hasTool(_ name: String) async -> Bool {
        await shell("command -v \(name)").0 == 0
    }

    static func log(_ line: String) {
        let folder = logURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: Date())
        let text = "\(stamp) \(line)\n"
        if let handle = try? FileHandle(forWritingTo: logURL) {
            handle.seekToEndOfFile()
            handle.write(Data(text.utf8))
            try? handle.close()
        } else {
            try? text.write(to: logURL, atomically: true, encoding: .utf8)
        }
    }
}
