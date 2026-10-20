import Darwin
import Foundation

/// What a scan found: every folder, and every file of a megabyte or more.
/// Smaller files are folded into their folder, which keeps a scan of a
/// whole disk to a few hundred thousand entries.
struct DiskScan: Sendable {
    struct Node: Sendable {
        enum Kind: UInt8, Sendable {
            case folder
            /// An app, library or document package: a folder that looks like a file.
            case package
            case file
            /// A folder Barn Owl wasn't allowed to look into.
            case unreadable
        }

        var name: String
        var parent: Int32
        var kind: Kind
        /// Bytes on disk, everything inside included.
        var size: Int64 = 0
        /// Bytes deleting it would free right away: not shared with copies
        /// (APFS clones) or kept by snapshots.
        var reclaimable: Int64 = 0
        /// Files inside; 1 for a file.
        var files: Int64 = 0
        /// Files too small to list one by one, folded together.
        var smallSize: Int64 = 0
        var smallCount: Int32 = 0
        /// Only in iCloud: nothing on this Mac.
        var inCloud = false
        var children: [Int32] = []

        var isFolder: Bool { kind != .file }
    }

    let root: String
    let nodes: [Node]
    let finished: Date
    let duration: TimeInterval

    var total: Node { nodes[0] }

    /// The path on disk.
    func path(of index: Int32) -> String {
        var names: [String] = []
        var current = index
        while current > 0 {
            names.append(nodes[Int(current)].name)
            current = nodes[Int(current)].parent
        }
        return ([root] + names.reversed()).joined(separator: "/")
    }

    /// The path people know: /Users rather than /System/Volumes/Data/Users.
    func displayPath(of index: Int32) -> String {
        DiskScanner.displayPath(path(of: index))
    }

    /// Children, biggest first.
    func children(of index: Int32) -> [Int32] {
        nodes[Int(index)].children.sorted { nodes[Int($0)].size > nodes[Int($1)].size }
    }

    /// Folders that couldn't be read, and how much they're likely hiding.
    var unreadable: [Int32] {
        nodes.indices.filter { nodes[$0].kind == .unreadable }.map(Int32.init)
    }

    /// The node at a path, if the scan reached it.
    func index(of path: String) -> Int32? {
        guard path.hasPrefix(root) else { return nil }
        var current: Int32 = 0
        for name in path.dropFirst(root.count).split(separator: "/") {
            guard let next = nodes[Int(current)].children.first(where: { nodes[Int($0)].name == name }) else { return nil }
            current = next
        }
        return current
    }

    /// The scan as it stands once `path` is gone: its folders count it no
    /// more, and nothing in it shows among the biggest files.
    func removing(_ path: String) -> DiskScan {
        guard let index = index(of: path), index > 0 else { return self }
        var nodes = nodes
        let gone = nodes[Int(index)]
        var parent = gone.parent
        nodes[Int(parent)].children.removeAll { $0 == index }
        while parent >= 0 {
            nodes[Int(parent)].size -= gone.size
            nodes[Int(parent)].reclaimable -= gone.reclaimable
            nodes[Int(parent)].files -= gone.files
            parent = nodes[Int(parent)].parent
        }
        var inside = [index]
        while let next = inside.popLast() {
            inside += nodes[Int(next)].children
            nodes[Int(next)].kind = .folder
            nodes[Int(next)].size = 0
        }
        return DiskScan(root: root, nodes: nodes, finished: finished, duration: duration)
    }

    /// The biggest single files.
    func largestFiles(limit: Int = 50) -> [Int32] {
        nodes.indices.filter { nodes[$0].kind == .file }
            .sorted { nodes[$0].size > nodes[$1].size }
            .prefix(limit).map(Int32.init)
    }
}

/// Reads a whole disk quickly and accurately, the way the file system itself
/// would count it:
///
/// - `getattrlistbulk` fetches a folder's entries with their sizes in one go,
///   on eight threads at once;
/// - sizes are what's allocated on disk, so compressed and sparse files count
///   for what they really take, and hard links count once;
/// - "reclaimable" is APFS's private size, what deleting would actually free;
/// - iCloud placeholders are never downloaded, other disks are never entered,
///   and folders it may not read are noted, not silently skipped.
final class DiskScanner: @unchecked Sendable {
    struct Progress: Sendable {
        var files: Int64
        var bytes: Int64
        var folder: String
    }

    /// Files smaller than this are folded into their folder.
    static let listedFileSize: Int64 = 1 << 20
    /// The Data volume, where everything that isn't macOS lives. Scanning it
    /// rather than / avoids counting firmlinked folders twice.
    static let dataVolume = "/System/Volumes/Data"

    static func displayPath(_ path: String) -> String {
        if path == dataVolume { return "/" }
        if path.hasPrefix(dataVolume + "/") { return String(path.dropFirst(dataVolume.count)) }
        return path
    }

    private static let packageExtensions: Set<String> = [
        "app", "bundle", "framework", "plugin", "kext", "appex", "xpc", "photoslibrary", "musiclibrary",
        "tvlibrary", "imovielibrary", "fcpbundle", "logicx", "band", "xcarchive", "xcodeproj", "xcworkspace",
        "playground", "rtfd", "pages", "numbers", "key", "saver", "prefpane", "qlgenerator", "mdimporter",
        "dsym", "pkg", "mpkg", "photoboothlibrary", "aplibrary", "sparsebundle",
    ]

    /// How urgently the scan threads run: the Barn's own measuring stays in the background.
    private let priority: QualityOfService

    init(priority: QualityOfService = .userInitiated) {
        self.priority = priority
    }

    private let condition = NSCondition()
    private var nodes: [DiskScan.Node] = []
    private var pending: [(index: Int32, path: String)] = []
    private var active = 0
    private var cancelled = false
    private var seenLinks = Set<UInt64>()
    private var fileCount: Int64 = 0
    private var byteCount: Int64 = 0
    private var lastReport = Date.distantPast
    private var progress: (@Sendable (Progress) -> Void)?

    /// Folders listed but not entered, shown as not readable: other apps'
    /// private folders, where looking makes macOS ask "would like to access
    /// data from other apps" again and again unless Barn Owl has Full Disk Access.
    private var notEntered: Set<String> = []

    /// Scans `root` (by default the whole Data volume). Returns nil if cancelled.
    func scan(root: String = DiskScanner.dataVolume, workers: Int = 8, skipping: Set<String> = [],
              progress: @escaping @Sendable (Progress) -> Void) async -> DiskScan? {
        Self.neverDownloadFromICloud()
        let start = Date()
        notEntered = skipping
        prepare(root: root, progress: progress)
        await withTaskCancellationHandler {
            await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
                let group = DispatchGroup()
                for number in 0..<max(1, workers) {
                    group.enter()
                    let thread = Thread { [self] in
                        work()
                        group.leave()
                    }
                    thread.name = "Barn Owl disk scan \(number)"
                    thread.qualityOfService = priority
                    thread.start()
                }
                group.notify(queue: .global()) { done.resume() }
            }
        } onCancel: {
            cancel()
        }
        return finish(root: root, started: start)
    }

    private func prepare(root: String, progress: @escaping @Sendable (Progress) -> Void) {
        condition.lock()
        defer { condition.unlock() }
        nodes = [DiskScan.Node(name: root, parent: -1, kind: .folder)]
        pending = [(0, root)]
        active = 0
        cancelled = false
        seenLinks = []
        fileCount = 0
        byteCount = 0
        self.progress = progress
    }

    private func cancel() {
        condition.lock()
        cancelled = true
        condition.broadcast()
        condition.unlock()
    }

    private func finish(root: String, started: Date) -> DiskScan? {
        condition.lock()
        defer { condition.unlock() }
        guard !cancelled else { return nil }
        var result = nodes
        nodes = []
        // Folders' totals, from the deepest up: a child always comes after its parent.
        for index in result.indices.dropFirst().reversed() where result[index].isFolder {
            let parent = Int(result[index].parent)
            result[parent].size += result[index].size
            result[parent].reclaimable += result[index].reclaimable
            result[parent].files += result[index].files
        }
        return DiskScan(root: root, nodes: result, finished: Date(), duration: Date().timeIntervalSince(started))
    }

    // MARK: Workers

    private func work() {
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: 128 * 1024, alignment: 16)
        defer { buffer.deallocate() }
        condition.lock()
        while true {
            while pending.isEmpty && active > 0 && !cancelled { condition.wait() }
            if cancelled || pending.isEmpty {
                condition.broadcast()
                condition.unlock()
                return
            }
            let job = pending.removeLast()
            active += 1
            condition.unlock()

            let listing = Self.list(job.path, buffer: buffer, size: 128 * 1024)

            condition.lock()
            record(listing, in: job.index, path: job.path)
            active -= 1
            condition.broadcast()
        }
    }

    /// Adds a folder's entries to the tree. Called with the lock held.
    private func record(_ listing: Listing, in folder: Int32, path: String) {
        guard listing.error == 0 else {
            if listing.error == EPERM || listing.error == EACCES { nodes[Int(folder)].kind = .unreadable }
            return
        }
        var ownSize: Int64 = 0, ownReclaimable: Int64 = 0, ownFiles: Int64 = 0
        var smallSize: Int64 = 0, smallCount: Int32 = 0
        var children: [Int32] = []
        for entry in listing.entries {
            if entry.isFolder {
                let index = Int32(nodes.count)
                let ext = (entry.name as NSString).pathExtension.lowercased()
                let childPath = path + "/" + entry.name
                let enter = !notEntered.contains(path)
                nodes.append(DiskScan.Node(name: entry.name, parent: folder,
                                           kind: !enter ? .unreadable
                                               : Self.packageExtensions.contains(ext) ? .package : .folder))
                children.append(index)
                if enter { pending.append((index, childPath)) }
                continue
            }
            // A hard link: count the file once, wherever it's first seen.
            if entry.linkCount > 1, !seenLinks.insert(entry.fileID).inserted { continue }
            ownSize += entry.size
            ownReclaimable += entry.reclaimable
            ownFiles += 1
            if entry.size >= Self.listedFileSize {
                let index = Int32(nodes.count)
                nodes.append(DiskScan.Node(name: entry.name, parent: folder, kind: .file, size: entry.size,
                                           reclaimable: entry.reclaimable, files: 1, inCloud: entry.inCloud))
                children.append(index)
            } else {
                smallSize += entry.size
                smallCount += 1
            }
        }
        nodes[Int(folder)].size += ownSize
        nodes[Int(folder)].reclaimable += ownReclaimable
        nodes[Int(folder)].files += ownFiles
        nodes[Int(folder)].smallSize += smallSize
        nodes[Int(folder)].smallCount += smallCount
        nodes[Int(folder)].children += children
        fileCount += ownFiles
        byteCount += ownSize

        let now = Date()
        if now.timeIntervalSince(lastReport) > 0.2, let progress {
            lastReport = now
            progress(Progress(files: fileCount, bytes: byteCount, folder: Self.displayPath(path)))
        }
    }

    // MARK: Reading a folder

    struct Entry {
        var name: String
        var isFolder: Bool
        var size: Int64
        var reclaimable: Int64
        var linkCount: UInt32
        var fileID: UInt64
        var inCloud: Bool
    }

    struct Listing {
        var entries: [Entry] = []
        var error: Int32 = 0
    }

    // From <sys/attr.h> and <sys/vnode.h>; spelled out so the bit patterns
    // stay unsigned.
    private static let returnedAttrs: UInt32 = 0x8000_0000
    private static let cmnName: UInt32 = 0x0000_0001
    private static let cmnObjType: UInt32 = 0x0000_0008
    private static let cmnFlags: UInt32 = 0x0004_0000
    private static let cmnFileID: UInt32 = 0x0200_0000
    private static let cmnError: UInt32 = 0x2000_0000
    private static let dirMountStatus: UInt32 = 0x0000_0004
    private static let fileLinkCount: UInt32 = 0x0000_0001
    private static let fileAllocSize: UInt32 = 0x0000_0004
    private static let extPrivateSize: UInt32 = 0x0000_0008
    private static let packInvalid: UInt64 = 0x0000_0008
    private static let extendedCommon: UInt64 = 0x0000_0020
    private static let typeDirectory: UInt32 = 2   // VDIR
    private static let mountPoint: UInt32 = 0x0000_0001
    private static let dataless: UInt32 = 0x4000_0000

    /// One folder's entries, through `getattrlistbulk`. With invalid
    /// attributes packed, each entry is laid out as:
    ///
    ///     length, returned attributes, error, name, type, flags, file ID,
    ///     then for a folder: mount status,
    ///     for anything else: link count, allocated size,
    ///     then private size.
    ///
    /// (Folder fields are left out for files and file fields for folders,
    /// even though invalid attributes are packed.)
    static func list(_ path: String, buffer: UnsafeMutableRawPointer, size: Int) -> Listing {
        var listing = Listing()
        let fd = open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else {
            listing.error = errno
            return listing
        }
        defer { close(fd) }

        var request = attrlist()
        request.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        request.commonattr = returnedAttrs | cmnName | cmnObjType | cmnFlags | cmnFileID | cmnError
        request.dirattr = dirMountStatus
        request.fileattr = fileLinkCount | fileAllocSize
        request.forkattr = extPrivateSize

        while true {
            let count = getattrlistbulk(fd, &request, buffer, size, packInvalid | extendedCommon)
            if count < 0 {
                listing.error = errno
                return listing
            }
            if count == 0 { return listing }
            var entryStart = buffer
            for _ in 0..<count {
                let length = Int(entryStart.loadUnaligned(as: UInt32.self))
                defer { entryStart += length }
                var field = entryStart + 4
                let returned = field.loadUnaligned(as: attribute_set_t.self)
                field += MemoryLayout<attribute_set_t>.size
                let error = field.loadUnaligned(as: UInt32.self)
                field += 4
                guard error == 0 else { continue }
                let nameRef = field.loadUnaligned(as: attrreference_t.self)
                let name = String(cString: (field + Int(nameRef.attr_dataoffset)).assumingMemoryBound(to: CChar.self))
                field += MemoryLayout<attrreference_t>.size
                let type = field.loadUnaligned(as: UInt32.self)
                field += 4
                let flags = field.loadUnaligned(as: UInt32.self)
                field += 4
                let fileID = field.loadUnaligned(as: UInt64.self)
                field += 8
                var mountStatus: UInt32 = 0, linkCount: UInt32 = 1, allocated: Int64 = 0
                if type == typeDirectory {
                    mountStatus = field.loadUnaligned(as: UInt32.self)
                    field += 4
                } else {
                    linkCount = field.loadUnaligned(as: UInt32.self)
                    field += 4
                    allocated = field.loadUnaligned(as: Int64.self)
                    field += 8
                }
                let privateSize = field.loadUnaligned(as: Int64.self)

                if type == typeDirectory {
                    // Another disk mounted here (an external drive in /Volumes): not ours to count.
                    if mountStatus & mountPoint != 0 { continue }
                    listing.entries.append(Entry(name: name, isFolder: true, size: 0, reclaimable: 0, linkCount: 1,
                                                 fileID: fileID, inCloud: false))
                } else {
                    let hasPrivateSize = returned.forkattr & extPrivateSize != 0
                    listing.entries.append(Entry(name: name, isFolder: false, size: max(0, allocated),
                                                 reclaimable: hasPrivateSize ? max(0, privateSize) : max(0, allocated),
                                                 linkCount: linkCount, fileID: fileID,
                                                 inCloud: flags & dataless != 0))
                }
            }
        }
    }

    /// Reading a file's size never downloads it from iCloud, but just in case
    /// anything ever opens one: fail instead of downloading.
    private static func neverDownloadFromICloud() {
        let typeMaterializeDataless: Int32 = 3, scopeProcess: Int32 = 0, materializeOff: Int32 = 1
        _ = setiopolicy_np(typeMaterializeDataless, scopeProcess, materializeOff)
    }
}
