// Draws Barn Owl's app icon at every size macOS needs.
// Usage: swift Scripts/make-icon.swift BarnOwl/Resources/Assets.xcassets/AppIcon.appiconset
import AppKit

let folder = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

func render(_ size: Int) -> Data {
    let s = CGFloat(size)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    // macOS icon grid: an 824/1024 rounded square with room for the shadow.
    let inset = s * 100 / 1024
    let body = NSRect(x: inset, y: inset * 1.15, width: s - inset * 2, height: s - inset * 2)
    let path = NSBezierPath(roundedRect: body, xRadius: body.width * 0.225, yRadius: body.width * 0.225)
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.shadowBlurRadius = s * 0.025
    shadow.shadowOffset = NSSize(width: 0, height: -s * 0.012)
    NSGraphicsContext.current?.saveGraphicsState()
    shadow.set()
    NSGradient(colors: [NSColor(srgbRed: 1.0, green: 0.62, blue: 0.25, alpha: 1),
                        NSColor(srgbRed: 0.93, green: 0.27, blue: 0.45, alpha: 1)])!
        .draw(in: path, angle: -55)
    NSGraphicsContext.current?.restoreGraphicsState()
    // A soft highlight across the top.
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.22), NSColor.white.withAlphaComponent(0)])!
        .draw(in: path, angle: -90)
    // The cup.
    let config = NSImage.SymbolConfiguration(pointSize: s * 0.42, weight: .semibold)
        .applying(.init(paletteColors: [.white]))
    if let cup = NSImage(systemSymbolName: "cup.and.heat.waves.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) {
        let size = cup.size
        cup.draw(in: NSRect(x: body.midX - size.width / 2, y: body.midY - size.height / 2 - s * 0.01,
                            width: size.width, height: size.height))
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

var images: [[String: String]] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = points * scale
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        try render(pixels).write(to: folder.appending(path: name))
        images.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": name])
    }
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    .write(to: folder.appending(path: "Contents.json"))
print("Wrote \(images.count) icons to \(folder.path)")
