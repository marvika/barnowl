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
