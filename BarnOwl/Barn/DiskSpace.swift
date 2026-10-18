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
    /// Your apps, files and settings: the Data volume.
    var data: Int64

    var used: Int64 { total - free }
    /// Everything else macOS keeps: swap, startup and recovery volumes,
    /// update staging, snapshots.
    var otherSystem: Int64 { max(0, used - system - data) }
    /// Data that's really yours: data minus what macOS can purge.
    var yours: Int64 { max(0, data - purgeable) }
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
        let free64 = Int64(free)
        let used = Int64(total) - free64
        // statfs reports the whole disk for every volume; this is each volume's own share.
        let system = volumeSpaceUsed("/") ?? 0
        let data = volumeSpaceUsed(DiskScanner.dataVolume) ?? max(0, used - system)
        return DiskSpace(total: Int64(total), free: free64, purgeable: max(0, important - free64),
                         system: system, data: data)
    }

    /// One volume's used space (ATTR_VOL_SPACEUSED), as df shows it.
    static func volumeSpaceUsed(_ path: String) -> Int64? {
        var request = attrlist()
        request.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        request.volattr = 0x8000_0000 | 0x0080_0000 // ATTR_VOL_INFO | ATTR_VOL_SPACEUSED
        var buffer = [UInt8](repeating: 0, count: 64)
        let status = buffer.withUnsafeMutableBytes { getattrlist(path, &request, $0.baseAddress, 64, 0) }
        guard status == 0 else { return nil }
        // A 4-byte length, then the value.
        return buffer.withUnsafeBytes { ($0.baseAddress! + 4).loadUnaligned(as: Int64.self) }
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
