import AppKit
import CoreServices
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
    /// Only items older than this many days: added to the folder that long
    /// ago, or for apps, last opened that long ago.
    var olderThanDays: Int?
    /// Only items with these extensions.
    var extensions: Set<String>?
    /// Never items with these extensions (another rule covers them).
    var skipExtensions: Set<String> = []
    /// Only items whose names start like this.
    var namePrefix: String?
    /// Only items at least this big.
    var minItemSize: Int64 = 100_000
    /// Never Apple's own apps.
    var skipAppleApps = false
    /// Names never offered, inside its folders (compared ignoring case, as APFS does).
    var keep: Set<String> = []
    /// Apps whose files these are; skipped while they're running.
    var ownerApps: [String] = []
    /// Command-line tools that use these files; skipped while one is running
    /// (a build halfway through would break).
    var ownerProcesses: [String] = []
    /// A command-line tool that must be installed for this to apply.
    var tool: String?
    var needsFullDiskAccess = false

    /// Its folders, with ~ as the given home (a test can use a stand-in).
    func expandedPaths(home: String = CleanupRule.realHome) -> [String] {
        paths.map { $0.hasPrefix("~/") ? home + $0.dropFirst() : $0 }
    }

    var expandedPaths: [String] { expandedPaths() }

    static var realHome: String { FileManager.default.homeDirectoryForCurrentUser.path }

    /// Caches never offered for picking: Apple's own (iCloud, Music, Photos
    /// keep state there), and those of password managers, VPNs and security
    /// tools, where removing files can lock you out or trip tamper alarms.
    static func isSensitiveCache(_ name: String) -> Bool {
        let lower = name.lowercased()
        if lower.hasPrefix("com.apple.") || lower.hasPrefix("group.com.apple.") { return true }
        let words = ["1password", "agilebits", "bitwarden", "lastpass", "dashlane", "keeper", "keepass", "enpass",
                     "vpn", "tunnelblick", "wireguard", "tailscale", "zscaler", "globalprotect", "anyconnect",
                     "crowdstrike", "falcon", "sentinel", "jamf", "kandji", "mosyle", "intune", "defender",
                     "littlesnitch", "lulu", "keychain", "cloudkit", "familycircle", "mobile documents"]
        return words.contains { lower.contains($0) }
    }

    /// Cleaning it can't be undone, so it asks first: emptying the Trash,
    /// deleting things you picked, and tools' clean-ups that remove more than
    /// caches.
    var needsConfirmation: Bool {
        if id == "trash" { return true }
        switch method {
        case .delete, .command: return safety != .safe
        case .trash, .none: return false
        }
    }

    func keeps(_ name: String) -> Bool {
        keep.contains { $0.caseInsensitiveCompare(name) == .orderedSame }
    }

    /// Whether one thing inside its folders is the kind it offers: the
    /// filters the pick list uses, checked again before anything is removed.
    func allows(_ url: URL, size: Int64?) -> Bool {
        let name = url.lastPathComponent
        let ext = url.pathExtension.lowercased()
        if name.hasPrefix(".") || keeps(name) { return false }
        if id == "app-caches", Self.isSensitiveCache(name) { return false }
        if let extensions, !extensions.contains(ext) { return false }
        if skipExtensions.contains(ext) { return false }
        if let namePrefix, !name.hasPrefix(namePrefix) { return false }
        if let size, size < minItemSize { return false }
        if skipAppleApps, ext == "app", Bundle(url: url)?.bundleIdentifier?.lowercased().hasPrefix("com.apple.") ?? true {
            return false
        }
        if let olderThanDays {
            // No date, no way to tell: not offered.
            guard let date = Self.age(of: url, lastOpened: ext == "app") else { return false }
            if date > Date().addingTimeInterval(-Double(olderThanDays) * 86_400) { return false }
        }
        return true
    }

    /// When it arrived in its folder (a download's own date can be years
    /// old), or for apps when it was last opened. An app Spotlight hasn't
    /// indexed has no age: without its "last opened" date, one used every day
    /// would look as old as when it was installed.
    static func age(of url: URL, lastOpened: Bool) -> Date? {
        let values = try? url.resourceValues(forKeys: [.addedToDirectoryDateKey, .creationDateKey])
        let arrived = values?.addedToDirectoryDate ?? values?.creationDate
        guard lastOpened else { return arrived }
        guard let item = MDItemCreateWithURL(nil, url as CFURL),
              MDItemCopyAttribute(item, kMDItemContentType) != nil else { return nil }
        // Indexed but never opened: its arrival is its age.
        return MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date ?? arrived
    }

    /// What happens when it's cleaned, in a few words.
    var methodSummary: String {
        switch method {
        case .delete: id == "trash" ? "Emptied for good" : safety == .safe ? "Removed, and made again when needed" : "Removed for good"
        case .trash: "Goes to the Trash, so you can undo"
        case .command(let command): "Runs \(command)"
        case .none: "Barn Owl only shows you where"
        }
    }
}

extension CleanupRule {
    static let all: [CleanupRule] = [
        // Developer
        CleanupRule(id: "xcode-derived-data", title: "Xcode build files",
                    detail: "DerivedData: intermediate build products and indexes. Xcode rebuilds them on the next build.",
                    symbol: "hammer.fill", group: .developer, safety: .safe, method: .delete,
                    paths: ["~/Library/Developer/Xcode/DerivedData"], ownerApps: ["com.apple.dt.Xcode"],
                    ownerProcesses: ["xcodebuild", "swift-build"]),
        CleanupRule(id: "simulator-caches", title: "Simulator caches",
                    detail: "Caches the iOS Simulator rebuilds when it next starts.",
                    symbol: "iphone", group: .developer, safety: .safe, method: .delete,
                    paths: ["~/Library/Developer/CoreSimulator/Caches"],
                    ownerApps: ["com.apple.iphonesimulator", "com.apple.dt.Xcode"]),
        CleanupRule(id: "simulators-unavailable", title: "Simulators for old Xcodes",
                    detail: "Simulators whose iOS version is no longer installed, with their apps and data. If you'll install that version again, keep them.",
                    symbol: "iphone.slash", group: .developer, safety: .review,
                    method: .command("xcrun simctl delete unavailable"), paths: [],
                    ownerApps: ["com.apple.iphonesimulator", "com.apple.dt.Xcode"], ownerProcesses: ["xcodebuild", "simctl"],
                    tool: "xcrun"),
        CleanupRule(id: "device-support", title: "Device support files",
                    detail: "Debug symbols Xcode copies from each iPhone, iPad and Watch version you've connected. Copied again if you need one.",
                    symbol: "cable.connector", group: .developer, safety: .review, method: .delete,
                    paths: ["~/Library/Developer/Xcode/iOS DeviceSupport", "~/Library/Developer/Xcode/watchOS DeviceSupport",
                            "~/Library/Developer/Xcode/tvOS DeviceSupport", "~/Library/Developer/Xcode/visionOS DeviceSupport"],
                    pickItems: true, ownerApps: ["com.apple.dt.Xcode"]),
        CleanupRule(id: "homebrew", title: "Homebrew downloads and old versions",
                    detail: "Downloaded bottles, and older versions of what you've upgraded. Something pointing at an old version by its full path would stop working.",
                    symbol: "mug.fill", group: .developer, safety: .review,
                    method: .command("brew cleanup --prune=all"), paths: ["~/Library/Caches/Homebrew"],
                    ownerProcesses: ["brew"], tool: "brew"),
        CleanupRule(id: "npm", title: "npm cache", detail: "Packages npm keeps to install faster. Cleaned with npm cache clean.",
                    symbol: "shippingbox.fill", group: .developer, safety: .safe,
                    method: .command("npm cache clean --force"), paths: ["~/.npm/_cacache"],
                    ownerProcesses: ["npm"], tool: "npm"),
        CleanupRule(id: "pnpm", title: "pnpm store", detail: "Packages no project uses any more. Cleaned with pnpm store prune.",
                    symbol: "shippingbox.fill", group: .developer, safety: .safe,
                    method: .command("pnpm store prune"), paths: ["~/Library/pnpm/store"],
                    ownerProcesses: ["pnpm"], tool: "pnpm"),
        CleanupRule(id: "yarn", title: "Yarn cache", detail: "Packages Yarn keeps to install faster. Cleaned with yarn cache clean.",
                    symbol: "shippingbox.fill", group: .developer, safety: .safe,
                    method: .command("yarn cache clean"), paths: ["~/Library/Caches/Yarn"],
                    ownerProcesses: ["yarn"], tool: "yarn"),
        CleanupRule(id: "pip", title: "pip cache", detail: "Python packages pip keeps to install faster. Cleaned with pip cache purge.",
                    symbol: "shippingbox.fill", group: .developer, safety: .safe,
                    method: .command("pip3 cache purge"), paths: ["~/Library/Caches/pip"], tool: "pip3"),
        CleanupRule(id: "cocoapods", title: "CocoaPods cache", detail: "Downloaded pods, fetched again when needed.",
                    symbol: "shippingbox.fill", group: .developer, safety: .safe, method: .delete,
                    paths: ["~/Library/Caches/CocoaPods"]),
        CleanupRule(id: "swiftpm", title: "Swift package cache", detail: "Downloaded Swift packages, fetched again when needed.",
                    symbol: "swift", group: .developer, safety: .safe, method: .delete,
                    paths: ["~/Library/Caches/org.swift.swiftpm"], ownerApps: ["com.apple.dt.Xcode"],
                    ownerProcesses: ["xcodebuild", "swift-build"]),
        CleanupRule(id: "go-build", title: "Go build cache", detail: "Compiled Go packages, rebuilt when needed.",
                    symbol: "hammer.fill", group: .developer, safety: .safe, method: .delete,
                    paths: ["~/Library/Caches/go-build"], ownerProcesses: ["go"]),
        CleanupRule(id: "cargo", title: "Cargo downloads", detail: "Downloaded Rust crates, fetched again when needed.",
                    symbol: "shippingbox.fill", group: .developer, safety: .safe, method: .delete,
                    paths: ["~/.cargo/registry/cache"], ownerProcesses: ["cargo"]),
        CleanupRule(id: "gradle", title: "Gradle caches",
                    detail: "Downloaded dependencies and build caches. Rebuilt when needed, but the next build downloads a lot.",
                    symbol: "shippingbox.fill", group: .developer, safety: .review, method: .delete,
                    paths: ["~/.gradle/caches"], pickItems: true, ownerProcesses: ["gradle", "GradleDaemon"]),

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

        CleanupRule(id: "macos-installers", title: "macOS installers",
                    detail: "Install macOS apps left in Applications after an upgrade. You can download one again from Software Update.",
                    symbol: "arrow.down.circle.fill", group: .apps, safety: .review, method: .trash,
                    paths: ["/Applications"], pickItems: true, extensions: ["app"], namePrefix: "Install macOS"),
        CleanupRule(id: "unused-apps", title: "Apps you haven't opened in 6 months",
                    detail: "Apps that haven't been opened for half a year. They go to the Trash; their settings stay, so they're as you left them if you install them again.",
                    symbol: "app.dashed", group: .apps, safety: .review, method: .trash,
                    paths: ["/Applications"], pickItems: true, olderThanDays: 182, extensions: ["app"],
                    minItemSize: 50_000_000, skipAppleApps: true),
        CleanupRule(id: "ios-updates", title: "iPhone and iPad updates",
                    detail: "Copies of iOS and iPadOS updates Finder downloaded to update your devices. Downloaded again if needed.",
                    symbol: "arrow.triangle.2.circlepath", group: .apps, safety: .safe, method: .delete,
                    paths: ["~/Library/iTunes/iPhone Software Updates", "~/Library/iTunes/iPad Software Updates",
                            "~/Library/iTunes/iPod Software Updates"]),
        CleanupRule(id: "mail-downloads", title: "Mail attachments you opened",
                    detail: "Copies Mail makes when you open an attachment. The originals stay in your mail; check for any you edited and saved there.",
                    symbol: "paperclip", group: .apps, safety: .review, method: .trash,
                    paths: ["~/Library/Containers/com.apple.mail/Data/Library/Mail Downloads"], pickItems: true,
                    ownerApps: ["com.apple.mail"], needsFullDiskAccess: true),

        // Downloads and Trash
        CleanupRule(id: "installers", title: "Old installers",
                    detail: "Disk images and installer packages in Downloads, older than a week. Once installed, they're not needed.",
                    symbol: "arrow.down.app.fill", group: .downloads, safety: .review, method: .trash,
                    paths: ["~/Downloads"], pickItems: true, olderThanDays: 7,
                    extensions: ["dmg", "pkg", "mpkg", "xip", "iso"]),
        CleanupRule(id: "big-downloads", title: "Big, old downloads",
                    detail: "Files of 200 MB or more that arrived in Downloads over three months ago. Have a look: some may be worth keeping somewhere else.",
                    symbol: "arrow.down.doc.fill", group: .downloads, safety: .review, method: .trash,
                    paths: ["~/Downloads"], pickItems: true, olderThanDays: 90,
                    skipExtensions: ["dmg", "pkg", "mpkg", "xip", "iso"], minItemSize: 200_000_000),
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
        CleanupRule(id: "photos-library", title: "Photos library",
                    detail: "With iCloud Photos, Photos → Settings → iCloud → Optimise Mac Storage keeps small copies here and the originals in iCloud.",
                    symbol: "photo.on.rectangle.angled", group: .yours, safety: .yourCall, method: .none,
                    paths: ["~/Pictures/Photos Library.photoslibrary"], needsFullDiskAccess: true),
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

    /// Every folder anything may ever be removed from, across all rules.
    static func allowedRoots(home: String = CleanupRule.realHome) -> [String] {
        Array(Set(CleanupRule.all.filter { $0.safety != .yourCall }.flatMap { $0.expandedPaths(home: home) })).sorted()
    }

    /// Never touched, even inside an allowed folder.
    static func protectedPaths(home: String = CleanupRule.realHome) -> [String] {
        ["/System", "/usr", "/bin", "/sbin", "/private/var/db", "/Library", "/Applications",
         home + "/Library/Mobile Documents", home + "/Library/Keychains", home + "/Library/Application Support",
         home + "/Library/Mail", home + "/Library/Messages", home + "/Documents", home + "/Desktop",
         home + "/Pictures", home + "/Movies", home + "/Music", home + "/.ssh", home + "/.claude", home + "/.config",
         home + "/.local"]
    }

    /// Whether `path` may be removed by `rule`: it must be inside one of that
    /// rule's own folders. The folder itself may only go when the rule takes
    /// it whole (DerivedData can go as a whole, ~/Library/Caches can't).
    static func check(_ path: String, rule: CleanupRule, home: String = CleanupRule.realHome,
                      wholeFolderAllowed: Bool = false) -> Refusal? {
        guard rule.safety != .yourCall else { return .outsideAllowedFolders }
        guard path.hasPrefix("/") else { return .notAbsolute }
        let standard = (path as NSString).standardizingPath
        guard standard == path, !path.contains("/../"), !path.hasSuffix("/..") else { return .notAbsolute }
        var info = stat()
        guard lstat(path, &info) == 0 else { return .notFound }
        if info.st_mode & S_IFMT == S_IFLNK { return .symlink }
        // Where it really is, every link on the way followed.
        guard let real = realPath(path) else { return .notFound }
        let roots = rule.expandedPaths(home: home)
        let realRoots = roots.map { realPath($0) ?? $0 }
        let protected = protectedPaths(home: home)
        let realProtected = protected.map { realPath($0) ?? $0 }
        // A rule's own folder reached through a link (~/.gradle/caches pointing into
        // Documents) would make its target look like the rule's to clean: refuse it.
        // Links above the home folder (/var → /private/var) are the system's own.
        if let root = roots.first(where: { path == $0 || path.hasPrefix($0 + "/") }), let realRoot = realPath(root) {
            let expected = root.hasPrefix(home + "/") ? (realPath(home) ?? home) + root.dropFirst(home.count) : root
            if realRoot != expected { return .symlink }
        }
        for (candidate, allowed, guarded) in [(path, roots, protected), (real, realRoots, realProtected)] {
            guard let root = allowed.first(where: { candidate == $0 || candidate.hasPrefix($0 + "/") }) else {
                return .outsideAllowedFolders
            }
            if candidate == root && !wholeFolderAllowed { return .isAllowedFolderItself }
            // What you pick is something directly inside the folder, never deeper.
            if rule.pickItems, (candidate as NSString).deletingLastPathComponent != root { return .outsideAllowedFolders }
            // An allowed folder can sit inside a protected one (Caches inside
            // Library); protection only applies outside allowed folders.
            if guarded.contains(where: { candidate == $0 || (candidate.hasPrefix($0 + "/") && !(root == $0 || root.hasPrefix($0 + "/"))) }) {
                return .protected
            }
        }
        if let running = rule.ownerApps.first(where: { !NSRunningApplication.runningApplications(withBundleIdentifier: $0).isEmpty }) {
            return .appRunning(running)
        }
        let url = URL(fileURLWithPath: path)
        let name = url.lastPathComponent
        if rule.pickItems {
            let isFile = info.st_mode & S_IFMT == S_IFREG
            guard rule.allows(url, size: isFile ? Int64(info.st_blocks) * 512 : nil) else { return .protected }
            // A cache folder named after a running app (com.example.App) is in use, and so is a running app.
            let running = NSWorkspace.shared.runningApplications
            if running.contains(where: { $0.bundleIdentifier?.lowercased() == name.lowercased() || $0.bundleURL?.path == path }) {
                return .appRunning(name)
            }
        }
        return nil
    }
}

/// The path with every link followed, as the file system sees it.
func realPath(_ path: String) -> String? {
    guard let resolved = Darwin.realpath(path, nil) else { return nil }
    defer { free(resolved) }
    return String(cString: resolved)
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
    static func run(_ rule: CleanupRule, items: [String], home: String = CleanupRule.realHome) async -> Outcome {
        var outcome = Outcome()
        if let busy = await busyTool(rule) {
            outcome.skipped.append((rule.title, "\(busy) is running"))
            return outcome
        }
        switch rule.method {
        case .none:
            return outcome
        case .command(let command):
            if let running = rule.ownerApps.first(where: { !NSRunningApplication.runningApplications(withBundleIdentifier: $0).isEmpty }) {
                outcome.skipped.append((command, "\(running) is running"))
                return outcome
            }
            let (status, output) = await shell(command, timeout: 600)
            log("\(status == 0 ? "ran" : "failed (\(status))") \(command)\(output.isEmpty ? "" : ": " + output.prefix(300))")
            if status == 0 { outcome.done.append(command) } else { outcome.skipped.append((command, output)) }
            return outcome
        case .delete, .trash:
            let targets = items.isEmpty ? rule.expandedPaths(home: home) : items
            for path in targets {
                if rule.keeps((path as NSString).lastPathComponent) {
                    outcome.skipped.append((path, "kept"))
                    continue
                }
                if let refusal = CleanupGate.check(path, rule: rule, home: home,
                                                   wholeFolderAllowed: items.isEmpty && !rule.pickItems) {
                    if refusal != .notFound { outcome.skipped.append((path, "\(refusal)")) }
                    continue
                }
                do {
                    if case .trash = rule.method {
                        var resulting: NSURL?
                        try FileManager.default.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: &resulting)
                        if let resulting {
                            outcome.trashed.append((URL(fileURLWithPath: path), resulting as URL))
                            TrashLedger.note(resulting as URL)
                        }
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

    /// A command-line tool using the rule's files right now, if any.
    static func busyTool(_ rule: CleanupRule) async -> String? {
        for name in rule.ownerProcesses {
            // pgrep directly, not through a shell.
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
            process.arguments = name.first?.isUppercase == true ? ["-f", name] : ["-x", name]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            guard (try? process.run()) != nil else { continue }
            process.waitUntilExit()
            if process.terminationStatus == 0 { return name }
        }
        return nil
    }

    /// Puts trashed items back where they were. Returns what couldn't go
    /// back (something new is in its place, or its folder is gone), still in
    /// the Trash.
    static func undo(_ trashed: [(from: URL, to: URL)]) -> [(from: URL, to: URL)] {
        var stuck: [(from: URL, to: URL)] = []
        for item in trashed {
            do {
                guard !FileManager.default.fileExists(atPath: item.from.path) else { throw CocoaError(.fileWriteFileExists) }
                // Put back only what Barn Owl moved there, not another item with its name.
                guard TrashLedger.isSame(item.to) else { throw CocoaError(.fileNoSuchFile) }
                try FileManager.default.moveItem(at: item.to, to: item.from)
                log("put back \(item.from.path)")
            } catch {
                stuck.append(item)
                log("couldn't put back \(item.from.path): \(error.localizedDescription)")
            }
        }
        return stuck
    }

    enum TrashError: LocalizedError {
        case notInTrash
        case replaced
        var errorDescription: String? {
            switch self {
            case .notInTrash: "it's no longer in the Trash"
            case .replaced: "something else has taken its place in the Trash"
            }
        }
    }

    /// Removes one thing Barn Owl just moved to the Trash, for good. Refuses
    /// anything that isn't straight inside your Trash, or is a link.
    static func removeFromTrash(_ url: URL, home: String = CleanupRule.realHome) throws {
        let trash = URL(fileURLWithPath: home + "/.Trash").resolvingSymlinksInPath().path
        let parent = url.deletingLastPathComponent().resolvingSymlinksInPath().path
        var info = stat()
        guard parent == trash, url.lastPathComponent != "..", lstat(url.path, &info) == 0,
              info.st_mode & S_IFMT != S_IFLNK else { throw TrashError.notInTrash }
        // Only the very item Barn Owl moved there, not another that has since taken its name.
        guard TrashLedger.isSame(url) else { throw TrashError.replaced }
        try FileManager.default.removeItem(at: url)
        log("removed \(url.path) from the Trash")
    }

    /// Empties a folder but keeps it (the Trash itself must stay).
    private static func emptyFolder(_ path: String) throws {
        for name in try FileManager.default.contentsOfDirectory(atPath: path) {
            try FileManager.default.removeItem(atPath: path + "/" + name)
        }
    }

    /// Collects a command's output as it comes, so a chatty tool never
    /// blocks on a full pipe.
    private final class Output: @unchecked Sendable {
        private let lock = NSLock()
        private var data = Data()
        func append(_ more: Data) { lock.withLock { data.append(more) } }
        var text: String { lock.withLock { String(decoding: data, as: UTF8.self) } }
    }

    /// Runs a command in a login shell, like Terminal, so tools installed
    /// with Homebrew or a version manager are found. It runs in a temporary
    /// folder, never inside a project, and gives up after `timeout` seconds.
    static func shell(_ command: String, timeout: TimeInterval = 30) async -> (Int32, String) {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-lc", command]
            process.currentDirectoryURL = FileManager.default.temporaryDirectory
            let pipe = Pipe()
            let output = Output()
            process.standardOutput = pipe
            process.standardError = pipe
            process.standardInput = FileHandle.nullDevice
            pipe.fileHandleForReading.readabilityHandler = { handle in output.append(handle.availableData) }
            process.terminationHandler = { finished in
                // Not readDataToEndOfFile: a tool the shell started (brew) can
                // still hold the pipe open after a timeout, and that would wait
                // for it forever. What it printed has been collected already.
                pipe.fileHandleForReading.readabilityHandler = nil
                continuation.resume(returning: (finished.terminationStatus,
                                                output.text.trimmingCharacters(in: .whitespacesAndNewlines)))
            }
            do {
                try process.run()
                let pid = process.processIdentifier
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                    guard process.isRunning else { return }
                    // The tool itself first (the shell's children), then the shell.
                    let children = Process()
                    children.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
                    children.arguments = ["-TERM", "-P", String(pid)]
                    try? children.run()
                    children.waitUntilExit()
                    process.terminate()
                }
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
        // Test runs clean a stand-in home; they don't belong in your log.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        let folder = logURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: Date())
        let text = "\(stamp) \(line)\n"
        if let handle = try? FileHandle(forWritingTo: logURL) {
            // The throwing calls: the old ones raise an exception on a full disk, mid clean-up.
            do {
                try handle.seekToEnd()
                try handle.write(contentsOf: Data(text.utf8))
            } catch {
                Log.app.error("Couldn't write to the clean-up log: \(error.localizedDescription)")
            }
            try? handle.close()
        } else {
            try? text.write(to: logURL, atomically: true, encoding: .utf8)
        }
    }
}

/// Which file each item Barn Owl moved to the Trash was (device and inode), by
/// where it went, so "Empty from Trash" and Undo act only on that very item.
enum TrashLedger {
    struct Identity: Equatable, Sendable {
        let device: Int32
        let inode: UInt64
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var identities: [String: Identity] = [:]

    static func identity(of path: String) -> Identity? {
        var info = stat()
        guard lstat(path, &info) == 0 else { return nil }
        return Identity(device: info.st_dev, inode: info.st_ino)
    }

    static func note(_ url: URL) {
        guard let identity = identity(of: url.path) else { return }
        lock.withLock { identities[url.path] = identity }
    }

    /// Whether `url` still holds the item noted there. Something never noted is
    /// taken as is (older reports), but every move to the Trash notes it.
    static func isSame(_ url: URL) -> Bool {
        guard let noted = lock.withLock({ identities[url.path] }) else { return true }
        return identity(of: url.path) == noted
    }
}
