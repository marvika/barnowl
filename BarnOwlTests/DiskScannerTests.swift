import Foundation
import Testing
@testable import BarnOwl

struct DiskScannerTests {
    /// A small tree: a 3 MB file, ten 10 KB files, a hard link to the big
    /// file, a package, and a folder that can't be read.
    private func makeTree() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: "barn-scan-\(UUID().uuidString)")
        let fm = FileManager.default
        try fm.createDirectory(at: root.appending(path: "Media/Small"), withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appending(path: "Tool.app/Contents"), withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appending(path: "Locked"), withIntermediateDirectories: true)
        // Random bytes, so APFS can't compress them away.
        let big = Data((0..<(3 << 20)).map { _ in UInt8.random(in: 0...255) })
        try big.write(to: root.appending(path: "Media/movie.mov"))
        for number in 0..<10 {
            try Data(repeating: UInt8(number), count: 10_000).write(to: root.appending(path: "Media/Small/\(number).txt"))
        }
        try fm.linkItem(at: root.appending(path: "Media/movie.mov"), to: root.appending(path: "Media/same-movie.mov"))
        try Data(repeating: 1, count: 2_000).write(to: root.appending(path: "Tool.app/Contents/Info.plist"))
        try fm.setAttributes([.posixPermissions: 0o000], ofItemAtPath: root.appending(path: "Locked").path)
        return root
    }

    private func cleanUp(_ root: URL) {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.appending(path: "Locked").path)
        try? FileManager.default.removeItem(at: root)
    }

    private func node(_ scan: DiskScan, _ path: String) -> DiskScan.Node? {
        scan.nodes.indices.first { scan.path(of: Int32($0)) == scan.root + "/" + path }.map { scan.nodes[$0] }
    }

    @Test func countsSizesFilesAndFolders() async throws {
        let root = try makeTree()
        defer { cleanUp(root) }
        let scan = try #require(await DiskScanner().scan(root: root.path, workers: 4) { _ in })

        // A file and its hard link: whichever is met first is counted.
        let movie = try #require(node(scan, "Media/movie.mov") ?? node(scan, "Media/same-movie.mov"))
        #expect(movie.kind == .file)
        #expect(movie.size >= 3 << 20)

        // Small files are folded into their folder, not listed.
        let small = try #require(node(scan, "Media/Small"))
        #expect(small.smallCount == 10)
        #expect(small.children.isEmpty)
        #expect(small.files == 10)

        // The hard link counts once.
        let media = try #require(node(scan, "Media"))
        #expect(media.files == 11)
        #expect(media.size < (3 << 20) * 2)

        #expect(node(scan, "Tool.app")?.kind == .package)
        #expect(node(scan, "Locked")?.kind == .unreadable)
        #expect(scan.total.files == 12)
        #expect(scan.total.size == scan.nodes.filter { $0.parent == 0 }.map(\.size).reduce(0, +))
    }

    @Test func biggestChildrenComeFirst() async throws {
        let root = try makeTree()
        defer { cleanUp(root) }
        let scan = try #require(await DiskScanner().scan(root: root.path) { _ in })
        let sizes = scan.children(of: 0).map { scan.nodes[Int($0)].size }
        #expect(sizes == sizes.sorted(by: >))
        let largest = scan.largestFiles(limit: 1).map { scan.nodes[Int($0)].name }
        #expect(largest == ["movie.mov"] || largest == ["same-movie.mov"])
    }

    @Test func displayPathsHideTheDataVolume() {
        #expect(DiskScanner.displayPath("/System/Volumes/Data/Users/me") == "/Users/me")
        #expect(DiskScanner.displayPath("/System/Volumes/Data") == "/")
        #expect(DiskScanner.displayPath("/Applications") == "/Applications")
    }
}
