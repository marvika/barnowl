// Composes docs/images/hero.png from the screenshots in docs/images and the
// owl drawn by the app. Run Scripts/make-hero.sh, which draws the owl first.
import AppKit

let folder = URL(fileURLWithPath: "docs/images")
func load(_ name: String) -> NSImage { NSImage(contentsOf: folder.appending(path: name))! }
// Screenshots are 2× pixels; work in pixels throughout.
func pixels(_ image: NSImage) -> NSSize {
    let rep = image.representations.first!
    return NSSize(width: rep.pixelsWide, height: rep.pixelsHigh)
}

let menuBar = load("menu-bar-countdown.png")
let perch = load("perch.png")
let quick = load("quick-panel.png")
let owl = NSImage(contentsOf: URL(fileURLWithPath: "build/hero-owl.png"))!

let width: CGFloat = 2400
let height: CGFloat = 1250
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width), pixelsHigh: Int(height),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// Background: the dusk sky from the app, rounded like a window, with stars.
let frame = NSRect(x: 0, y: 0, width: width, height: height)
NSBezierPath(roundedRect: frame, xRadius: 48, yRadius: 48).addClip()
NSGradient(colors: [NSColor(srgbRed: 0.24, green: 0.23, blue: 0.56, alpha: 1),
                    NSColor(srgbRed: 0.11, green: 0.10, blue: 0.25, alpha: 1)])!
    .draw(in: frame, angle: -90)
var seed: UInt64 = 42
func random() -> CGFloat {
    seed = seed &* 6364136223846793005 &+ 1442695040888963407
    return CGFloat(seed >> 33) / CGFloat(UInt32.max >> 1)
}
for _ in 0..<70 {
    let size = 2 + random() * 4
    NSColor.white.withAlphaComponent(0.3 + random() * 0.5).setFill()
    NSBezierPath(ovalIn: NSRect(x: random() * width, y: random() * height, width: size, height: size)).fill()
}
// An amber crescent moon: a disc with a second disc cut out of it.
if let context = NSGraphicsContext.current?.cgContext {
    context.saveGState()
    context.addRect(frame)
    context.addEllipse(in: CGRect(x: 655, y: 1045, width: 110, height: 110))
    context.clip(using: .evenOdd)
    context.setFillColor(NSColor(srgbRed: 0.96, green: 0.65, blue: 0.20, alpha: 1).cgColor)
    context.fillEllipse(in: CGRect(x: 620, y: 1025, width: 120, height: 120))
    context.restoreGState()
}

// The menu bar strip along the top, right-aligned like the real one.
let strip = pixels(menuBar)
let stripHeight: CGFloat = 66
let stripWidth = strip.width * stripHeight / strip.height
NSColor.black.withAlphaComponent(0.18).setFill()
NSRect(x: 0, y: height - stripHeight, width: width, height: stripHeight).fill()
menuBar.draw(in: NSRect(x: width - stripWidth - 24, y: height - stripHeight, width: stripWidth, height: stripHeight))

// Panels under it.
let perchSize = pixels(perch)
let quickSize = pixels(quick)
let top = height - stripHeight - 6
let quickX = width - quickSize.width - 60
quick.draw(in: NSRect(x: quickX, y: top - quickSize.height, width: quickSize.width, height: quickSize.height))
perch.draw(in: NSRect(x: quickX - perchSize.width + 10, y: top - perchSize.height - 30,
                      width: perchSize.width, height: perchSize.height))

// The owl, with the name and tagline under it.
owl.draw(in: NSRect(x: 150, y: 470, width: 560, height: 560))
let title = NSAttributedString(string: "Barn Owl", attributes: [
    .font: NSFont.systemFont(ofSize: 140, weight: .heavy), .foregroundColor: NSColor.white])
let tagline = NSAttributedString(string: "A tidier menu bar,\nand a Mac that stays awake.", attributes: [
    .font: NSFont.systemFont(ofSize: 56, weight: .medium), .foregroundColor: NSColor.white.withAlphaComponent(0.85)])
title.draw(at: NSPoint(x: 120, y: 290))
tagline.draw(in: NSRect(x: 125, y: 90, width: 900, height: 180))

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: folder.appending(path: "hero.png"))
print("Wrote docs/images/hero.png")
