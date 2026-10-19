import AppKit

/// Turns OwletArt's frames into small images, once each. Shown at a whole
/// number of points per sprite pixel with no smoothing, so every pixel stays
/// a crisp square.
@MainActor
enum OwletRenderer {
    private static var cache: [String: CGImage] = [:]
    private static var templates: [String: NSImage] = [:]

    /// `name` identifies the frame ("state:typing:0"), so the cache key stays short.
    static func image(_ frame: String, name: String, width: Int, height: Int, palette: String) -> CGImage? {
        let key = "\(palette)|\(name)"
        if let cached = cache[key] { return cached }
        let colours = OwletArt.palettes[palette] ?? OwletArt.palettes["golden"] ?? [:]
        let image = draw(frame, width: width, height: height) { colours[$0] }
        cache[key] = image
        return image
    }

    /// A one-colour 16 x 16 owlet for the menu bar.
    static func template(_ name: String) -> NSImage? {
        if let cached = templates[name] { return cached }
        guard let frame = OwletArt.templates[name],
              let cg = draw(frame, width: OwletArt.iconSize, height: OwletArt.iconSize, colour: { $0 == "." ? nil : 0x000000 })
        else { return nil }
        let image = NSImage(cgImage: cg, size: NSSize(width: OwletArt.iconSize, height: OwletArt.iconSize))
        image.isTemplate = true
        templates[name] = image
        return image
    }

    private static func draw(_ frame: String, width: Int, height: Int, colour: (Character) -> UInt32?) -> CGImage? {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for (index, key) in frame.enumerated() where index < width * height && key != "." {
            guard let rgb = colour(key) else { continue }
            pixels[index * 4] = UInt8((rgb >> 16) & 0xFF)
            pixels[index * 4 + 1] = UInt8((rgb >> 8) & 0xFF)
            pixels[index * 4 + 2] = UInt8(rgb & 0xFF)
            pixels[index * 4 + 3] = 0xFF
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue), provider: provider,
                       decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}
