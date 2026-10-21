import AppKit
import UniformTypeIdentifiers

enum CaptureFormat: String, CaseIterable, Identifiable {
    case png, jpeg, heic

    var id: String { rawValue }
    var title: String {
        switch self {
        case .png: "PNG"
        case .jpeg: "JPEG"
        case .heic: "HEIC"
        }
    }
    var type: UTType {
        switch self {
        case .png: .png
        case .jpeg: .jpeg
        case .heic: .heic
        }
    }
    var fileExtension: String { self == .jpeg ? "jpg" : rawValue }
}

enum CardCorner: String, CaseIterable, Identifiable {
    case bottomLeft, bottomRight
    var id: String { rawValue }
    var title: String { self == .bottomLeft ? "Bottom left" : "Bottom right" }
}

/// One screenshot, as it was caught.
struct Capture: Identifiable {
    enum Kind: String {
        // macOS's own words for kMDItemScreenCaptureType.
        case area = "selection", window, screen = "display"
    }

    let id = UUID()
    var image: CGImage
    /// Pixels per point: 2 on a Retina display.
    let scale: CGFloat
    let kind: Kind
    let date: Date
    /// The app in front when it was taken, for the file name.
    let appName: String?
    /// Where it was saved, once it is.
    var fileURL: URL?

    /// Its size on screen, in points.
    var pointSize: CGSize { CGSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale) }
}

/// Where captures go and how they're written, copied and named.
enum CaptureStore {
    /// The folder chosen in Settings, or the one macOS uses for its own
    /// screenshots (the Desktop unless changed with ⌘⇧5 › Options).
    static var folder: URL {
        let chosen = Preferences.captureFolder
        if !chosen.isEmpty, FileManager.default.fileExists(atPath: chosen) { return URL(fileURLWithPath: chosen) }
        return systemFolder
    }

    static var systemFolder: URL {
        let desktop = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Desktop")
        guard let value = CFPreferencesCopyAppValue("location" as CFString, "com.apple.screencapture" as CFString) as? String,
              !value.isEmpty else { return desktop }
        let path = (value as NSString).expandingTildeInPath
        return FileManager.default.fileExists(atPath: path) ? URL(fileURLWithPath: path) : desktop
    }

    /// "Screenshot 2026-10-21 at 14.32.07", like macOS's own, with the app's
    /// name after it if asked for.
    static func baseName(prefix: String, date: Date, appName: String?) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        var name = "\(prefix) \(formatter.string(from: date))"
        if let appName, !appName.isEmpty { name += " (\(appName))" }
        // Slashes and colons can't be in a file name.
        return name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
    }

    /// A file name that isn't taken yet in `folder`: "Name", then "Name 2", "Name 3"…
    static func freeURL(in folder: URL, baseName: String, fileExtension: String) -> URL {
        var url = folder.appending(path: "\(baseName).\(fileExtension)")
        var number = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appending(path: "\(baseName) \(number).\(fileExtension)")
            number += 1
        }
        return url
    }

    /// Writes the capture into the capture folder, or over its own file if it has one.
    @discardableResult
    static func save(_ capture: Capture, image: CGImage? = nil) throws -> URL {
        let format = Preferences.captureFormat
        let url = capture.fileURL ?? freeURL(
            in: folder,
            baseName: baseName(prefix: Preferences.captureNamePrefix, date: capture.date,
                               appName: Preferences.captureNameIncludesApp ? capture.appName : nil),
            fileExtension: format.fileExtension)
        let data = try encode(image ?? capture.image, scale: capture.scale, as: format, atOneX: Preferences.captureAtOneX)
        try data.write(to: url, options: .atomic)
        markAsScreenshot(url, kind: capture.kind)
        return url
    }

    /// A copy in a temporary folder, for dragging out a capture that isn't saved.
    static func temporaryFile(for capture: Capture, image: CGImage? = nil) -> URL? {
        let folder = FileManager.default.temporaryDirectory.appending(path: "Barn Owl Captures")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = baseName(prefix: Preferences.captureNamePrefix, date: capture.date, appName: nil)
        let url = folder.appending(path: "\(name).png")
        guard let data = try? encode(image ?? capture.image, scale: capture.scale, as: .png, atOneX: false),
              (try? data.write(to: url, options: .atomic)) != nil else { return nil }
        return url
    }

    /// Image data at the right size and resolution, so a Retina capture opens
    /// at the size it looked on screen.
    static func encode(_ image: CGImage, scale: CGFloat, as format: CaptureFormat, atOneX: Bool) throws -> Data {
        let output = atOneX && scale > 1 ? (resized(image, by: 1 / scale) ?? image) : image
        let dpi = atOneX ? 72 : 72 * scale
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, format.type.identifier as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        var properties: [CFString: Any] = [kCGImagePropertyDPIWidth: dpi, kCGImagePropertyDPIHeight: dpi]
        if format != .png { properties[kCGImageDestinationLossyCompressionQuality] = 0.9 }
        CGImageDestinationAddImage(destination, output, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
        return data as Data
    }

    static func resized(_ image: CGImage, by factor: CGFloat) -> CGImage? {
        let width = max(1, Int((CGFloat(image.width) * factor).rounded()))
        let height = max(1, Int((CGFloat(image.height) * factor).rounded()))
        let space = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    /// Puts the image on the clipboard, at its on-screen size.
    @MainActor
    static func copy(_ image: CGImage, scale: CGFloat) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        if let png = try? encode(image, scale: scale, as: .png, atOneX: false) { item.setData(png, forType: .png) }
        let size = NSSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
        if let tiff = NSImage(cgImage: image, size: size).tiffRepresentation { item.setData(tiff, forType: .tiff) }
        pasteboard.writeObjects([item])
    }

    /// Tags the file the way macOS tags its own screenshots, so Finder and
    /// Spotlight searches for screenshots find it.
    static func markAsScreenshot(_ url: URL, kind: Capture.Kind) {
        setAttribute("com.apple.metadata:kMDItemIsScreenCapture", true, on: url)
        setAttribute("com.apple.metadata:kMDItemScreenCaptureType", kind.rawValue, on: url)
    }

    private static func setAttribute(_ name: String, _ value: Any, on url: URL) {
        guard let data = try? PropertyListSerialization.data(fromPropertyList: value, format: .binary, options: 0)
        else { return }
        _ = data.withUnsafeBytes { bytes in
            setxattr(url.path, name, bytes.baseAddress, data.count, 0, 0)
        }
    }
}

/// Other screenshot apps on this Mac, so Barn Owl can offer to stay out of their way.
enum OtherCaptureApps {
    /// App names to look for, matched at the start of the bundle's name.
    static let known = ["CleanShot X", "Shottr", "Snagit", "Xnapper", "Monosnap", "Skitch", "Zight", "Lightshot",
                        "ScreenFloat"]

    static func installed(in folders: [URL]? = nil) -> [String] {
        let fm = FileManager.default
        let places = folders ?? [URL(fileURLWithPath: "/Applications"), fm.homeDirectoryForCurrentUser.appending(path: "Applications")]
        let names = places.flatMap { (try? fm.contentsOfDirectory(atPath: $0.path)) ?? [] }
            .filter { $0.hasSuffix(".app") }
        return known.filter { app in names.contains { $0.hasPrefix(app) } }
    }
}

/// macOS's own screenshot shortcuts (⌘⇧3, ⌘⇧4, ⌘⇧5 and their clipboard
/// versions), read from System Settings. Barn Owl never changes them.
enum SystemScreenshotShortcuts {
    /// The symbolic hot key numbers macOS uses for them.
    static let ids = ["28", "29", "30", "31", "184"]

    /// Whether any of them still answers. A shortcut that was never changed
    /// isn't listed at all, and is on.
    static func anyEnabled(in hotKeys: [String: Any]?) -> Bool {
        ids.contains { id in
            guard let entry = hotKeys?[id] as? [String: Any] else { return true }
            return (entry["enabled"] as? Bool) ?? ((entry["enabled"] as? Int) ?? 1 != 0)
        }
    }

    static var anyEnabled: Bool {
        CFPreferencesAppSynchronize("com.apple.symbolichotkeys" as CFString)
        let value = CFPreferencesCopyAppValue("AppleSymbolicHotKeys" as CFString, "com.apple.symbolichotkeys" as CFString)
        return anyEnabled(in: value as? [String: Any])
    }

    /// System Settings › Keyboard, where Keyboard Shortcuts… › Screenshots lives.
    static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!
}
