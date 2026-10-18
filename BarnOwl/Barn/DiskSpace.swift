import Darwin
import Foundation

/// How the startup disk's space is used, from the numbers macOS keeps. All
/// the volumes on the disk (macOS itself, your data, swap, recovery) share
/// one pool, so these add up to the whole disk.
struct DiskSpace: Equatable, Sendable {
    /// The whole disk.
    var total: Int64
    /// Free right now.
    var free: Int64
    /// Space macOS can free by itself when it needs room: caches it manages,
    /// iCloud copies, local Time Machine snapshots. Finder counts it as free.
    var purgeable: Int64
    /// The sealed, read-only macOS system volume.
    var system: Int64

    var used: Int64 { total - free }
    /// What Finder calls available.
    var available: Int64 { free + purgeable }
    var freeFraction: Double { total > 0 ? Double(available) / Double(total) : 0 }

    static func current() -> DiskSpace? {
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityKey,
                                         .volumeAvailableCapacityForImportantUsageKey]
        guard let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys),
              let total = values.volumeTotalCapacity, let free = values.volumeAvailableCapacity
        else { return nil }
        let important = values.volumeAvailableCapacityForImportantUsage ?? Int64(free)
        var info = statfs()
        let system = statfs("/", &info) == 0 ? Int64(info.f_blocks - info.f_bfree) * Int64(info.f_bsize) : 0
        return DiskSpace(total: Int64(total), free: Int64(free), purgeable: max(0, important - Int64(free)),
                         system: system)
    }
}

/// Full Disk Access lets Barn Owl look into Mail, Messages, Safari, the Trash
/// and iPhone backups. macOS has no way to ask whether it's granted, so this
/// tries to open a few things only it unlocks.
enum FullDiskAccess {
    static var isGranted: Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        for path in ["/Library/Preferences/com.apple.TimeMachine.plist", home + "/Library/Safari",
                     home + "/Library/Mail", home + "/.Trash"] {
            let fd = open(path, O_RDONLY)
            if fd >= 0 {
                close(fd)
                return true
            }
            // Missing on this Mac: try the next one. Refused: not granted.
            if errno != ENOENT { return false }
        }
        return false
    }

    static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
}

enum Bytes {
    /// "12.4 GB", the way Finder counts.
    static func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
