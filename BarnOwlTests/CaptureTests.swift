import AppKit
import Foundation
import ImageIO
import Testing
@testable import BarnOwl

struct CaptureStoreTests {
    private let date = DateComponents(calendar: .current, year: 2026, month: 10, day: 21, hour: 14, minute: 32, second: 7).date!

    @Test func namesLikeMacOS() {
        #expect(CaptureStore.baseName(prefix: "Screenshot", date: date, appName: nil) == "Screenshot 2026-10-21 at 14.32.07")
        #expect(CaptureStore.baseName(prefix: "Shot", date: date, appName: "Notes") == "Shot 2026-10-21 at 14.32.07 (Notes)")
        // Characters a file name can't hold.
        #expect(CaptureStore.baseName(prefix: "A/B", date: date, appName: "C:D") == "A-B 2026-10-21 at 14.32.07 (C-D)")
    }

    @Test func neverOverwritesAFile() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "capture-names-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let first = CaptureStore.freeURL(in: folder, baseName: "Shot", fileExtension: "png")
        #expect(first.lastPathComponent == "Shot.png")
        try Data().write(to: first)
        let second = CaptureStore.freeURL(in: folder, baseName: "Shot", fileExtension: "png")
        #expect(second.lastPathComponent == "Shot 2.png")
        try Data().write(to: second)
        #expect(CaptureStore.freeURL(in: folder, baseName: "Shot", fileExtension: "png").lastPathComponent == "Shot 3.png")
    }

    @Test func savesRetinaAtItsOnScreenSizeWhenAsked() throws {
        let image = try #require(Self.image(width: 200, height: 100))
        let full = try CaptureStore.encode(image, scale: 2, as: .png, atOneX: false)
        let half = try CaptureStore.encode(image, scale: 2, as: .png, atOneX: true)
        let fullProps = try #require(Self.properties(full))
        let halfProps = try #require(Self.properties(half))
        #expect(fullProps[kCGImagePropertyPixelWidth] as? Int == 200)
        // 144 dpi tells apps it's Retina, so it opens at 100 × 50 points.
        #expect((fullProps[kCGImagePropertyDPIWidth] as? Double) == 144)
        #expect(halfProps[kCGImagePropertyPixelWidth] as? Int == 100)
        #expect((halfProps[kCGImagePropertyDPIWidth] as? Double) == 72)
    }

    @Test func tagsFilesAsScreenshots() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "capture-tag-\(UUID()).png")
        try Data([0]).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        CaptureStore.markAsScreenshot(url, kind: .window)
        let size = getxattr(url.path, "com.apple.metadata:kMDItemScreenCaptureType", nil, 0, 0, 0)
        #expect(size > 0)
    }

    static func image(width: Int, height: Int) -> CGImage? {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        context?.setFillColor(NSColor.systemOrange.cgColor)
        context?.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context?.makeImage()
    }

    private static func properties(_ data: Data) -> [CFString: Any]? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
    }
}

struct CaptureSelectionTests {
    @Test func cropsTheRightPixels() throws {
        // A 100 × 50 point screen at 2x, sitting right of the main one.
        let image = try #require(CaptureStoreTests.image(width: 200, height: 100))
        let snapshot = DisplaySnapshot(displayID: 2, frame: CGRect(x: 1000, y: 0, width: 100, height: 50), scale: 2, image: image)
        let crop = try #require(snapshot.crop(CGRect(x: 1010, y: 20, width: 30, height: 10)))
        #expect(crop.width == 60 && crop.height == 20)
        // Outside the display: nothing.
        #expect(snapshot.crop(CGRect(x: 0, y: 0, width: 30, height: 10)) == nil)
    }

    @Test func dragsMakeRects() {
        let start = CGPoint(x: 100, y: 100)
        #expect(SelectionView.rect(from: start, to: CGPoint(x: 60, y: 130), flags: []) == CGRect(x: 60, y: 100, width: 40, height: 30))
        // ⇧ squares it, towards the drag.
        #expect(SelectionView.rect(from: start, to: CGPoint(x: 60, y: 130), flags: .shift) == CGRect(x: 60, y: 100, width: 40, height: 40))
        // ⌥ grows it from the start point.
        #expect(SelectionView.rect(from: start, to: CGPoint(x: 120, y: 110), flags: .option) == CGRect(x: 80, y: 90, width: 40, height: 20))
    }

    @Test func picksTheFrontmostWindow() {
        let back = WindowTarget(windowID: 1, frame: CGRect(x: 0, y: 0, width: 500, height: 500), appName: "Back")
        let front = WindowTarget(windowID: 2, frame: CGRect(x: 100, y: 100, width: 100, height: 100), appName: "Front")
        #expect(WindowLocator.window(at: CGPoint(x: 150, y: 150), in: [front, back])?.windowID == 2)
        #expect(WindowLocator.window(at: CGPoint(x: 20, y: 20), in: [front, back])?.windowID == 1)
        #expect(WindowLocator.window(at: CGPoint(x: 900, y: 20), in: [front, back]) == nil)
    }
}

struct CaptureSetupTests {
    @Test func readsMacOSScreenshotShortcuts() {
        let allOff: [String: Any] = Dictionary(uniqueKeysWithValues: SystemScreenshotShortcuts.ids.map {
            ($0, ["enabled": false] as [String: Any])
        })
        #expect(!SystemScreenshotShortcuts.anyEnabled(in: allOff))
        var oneOn = allOff
        oneOn["30"] = ["enabled": 1]
        #expect(SystemScreenshotShortcuts.anyEnabled(in: oneOn))
        // Never changed means on.
        var missing = allOff
        missing["184"] = nil
        #expect(SystemScreenshotShortcuts.anyEnabled(in: missing))
        #expect(SystemScreenshotShortcuts.anyEnabled(in: nil))
    }

    @Test func findsOtherCaptureApps() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "capture-apps-\(UUID())")
        for name in ["CleanShot X.app", "Snagit 2025.app", "Notes.app"] {
            try FileManager.default.createDirectory(at: folder.appending(path: name), withIntermediateDirectories: true)
        }
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(OtherCaptureApps.installed(in: [folder]) == ["CleanShot X", "Snagit"])
    }
}

struct CaptureFlowTests {
    @Test func handlesResizeFromTheOppositeEdge() {
        let rect = CGRect(x: 100, y: 100, width: 200, height: 100)
        #expect(SelectionView.resize(rect, handle: .right, to: CGPoint(x: 350, y: 0)) == CGRect(x: 100, y: 100, width: 250, height: 100))
        #expect(SelectionView.resize(rect, handle: .topLeft, to: CGPoint(x: 50, y: 260)) == CGRect(x: 50, y: 100, width: 250, height: 160))
        // Dragging past the opposite edge flips instead of going negative.
        #expect(SelectionView.resize(rect, handle: .left, to: CGPoint(x: 400, y: 0)) == CGRect(x: 300, y: 100, width: 100, height: 100))
        #expect(SelectionView.handlePoints(of: rect).count == 8)
    }

    @Test func twoCapturesInOneSecondGetTheirOwnNames() {
        let folder = FileManager.default.temporaryDirectory.appending(path: "capture-names-\(UUID())")
        let first = CaptureStore.freeURL(in: folder, baseName: "Shot", fileExtension: "png")
        let second = CaptureStore.freeURL(in: folder, baseName: "Shot", fileExtension: "png")
        #expect(first != second)
    }

    @MainActor @Test func describesWhatIsVisible() {
        func finding(_ kind: SensitiveTextFinder.Kind) -> SensitiveTextFinder.Finding { .init(rect: .zero, kind: kind, text: "") }
        #expect(CaptureCoordinator.describe([finding(.key)]) == "A key or token")
        #expect(CaptureCoordinator.describe([finding(.key), finding(.homeFolder)]) == "A key or token and your user name")
        #expect(CaptureCoordinator.describe([finding(.nationalID)]) == "An ID number")
        #expect(CaptureCoordinator.describe([finding(.key), finding(.key), finding(.email)]) == "3 private details")
    }

    @Test func savingAgainKeepsTheFilesFormat() {
        #expect(CaptureStore.format(of: URL(fileURLWithPath: "/tmp/a.jpg")) == .jpeg)
        #expect(CaptureStore.format(of: URL(fileURLWithPath: "/tmp/a.HEIC")) == .heic)
        #expect(CaptureStore.format(of: URL(fileURLWithPath: "/tmp/a.png")) == .png)
    }

    @Test func jpegHasNoTransparency() throws {
        let image = try #require(CaptureStoreTests.image(width: 10, height: 10))
        let flat = try #require(CaptureStore.flattened(image))
        #expect(flat.alphaInfo == .noneSkipLast)
    }
}

struct CaptureLibraryTests {
    private func root() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "capture-library-\(UUID())")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func keepsCapturesEditable() throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let image = try #require(CaptureStoreTests.image(width: 20, height: 10))
        let entry = CaptureLibrary.Entry(id: UUID(), date: Date(), scale: 2, kind: "selection", appName: "Notes",
                                         fileURL: nil, edited: false)
        try CaptureLibrary.store(image, entry: entry, in: root)
        #expect(CaptureLibrary.entry(entry.id, in: root) == entry)
        #expect(CaptureLibrary.original(entry.id, in: root)?.width == 20)
        try CaptureLibrary.storeDocument(Data("{}".utf8), for: entry.id, in: root)
        #expect(CaptureLibrary.document(entry.id, in: root) == Data("{}".utf8))
        #expect(CaptureLibrary.entry(entry.id, in: root)?.edited == true)
        #expect(CaptureLibrary.latest(in: root)?.id == entry.id)
    }

    @Test func neverKeepsMarksWithoutTheirPicture() throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID()
        try CaptureLibrary.storeDocument(Data("{}".utf8), for: id, in: root)
        #expect(!FileManager.default.fileExists(atPath: CaptureLibrary.folder(for: id, in: root).path))
    }

    @Test func findsTheCaptureBehindAFile() throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appending(path: "shot.png")
        try Data([1]).write(to: file)
        let id = UUID()
        CaptureLibrary.tag(file, id: id)
        #expect(CaptureLibrary.id(of: file) == id)
    }

    @Test func letsGoOfOldCaptures() throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let image = try #require(CaptureStoreTests.image(width: 4, height: 4))
        let old = CaptureLibrary.Entry(id: UUID(), date: Date().addingTimeInterval(-40 * 86_400), scale: 1, kind: "display",
                                       appName: nil, fileURL: nil, edited: false)
        let new = CaptureLibrary.Entry(id: UUID(), date: Date(), scale: 1, kind: "display", appName: nil, fileURL: nil, edited: false)
        try CaptureLibrary.store(image, entry: old, in: root)
        try CaptureLibrary.store(image, entry: new, in: root)
        CaptureLibrary.prune(days: 30, in: root)
        #expect(CaptureLibrary.entries(in: root).map(\.id) == [new.id])
    }
}
