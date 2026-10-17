// Composes docs/images/hero.png from the screenshots in docs/images.
// Usage: swift Scripts/make-hero.swift
import AppKit

let folder = URL(fileURLWithPath: "docs/images")
func load(_ name: String) -> NSImage { NSImage(contentsOf: folder.appending(path: name))! }
// Screenshots are 2× pixels; work in pixels throughout.
func pixels(_ image: NSImage) -> NSSize {
    let rep = image.representations.first!
    return NSSize(width: rep.pixelsWide, height: rep.pixelsHigh)
}

let menuBar = load("menu-bar-countdown.png")
let bar = load("barnowl-bar.png")
let quick = load("quick-panel.png")

let width: CGFloat = 2400
let height: CGFloat = 1250
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width), pixelsHigh: Int(height),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// Background: a soft dusk gradient, rounded like a window.
let frame = NSRect(x: 0, y: 0, width: width, height: height)
let clip = NSBezierPath(roundedRect: frame, xRadius: 48, yRadius: 48)
clip.addClip()
NSGradient(colors: [NSColor(srgbRed: 0.33, green: 0.45, blue: 0.70, alpha: 1),
                    NSColor(srgbRed: 0.55, green: 0.42, blue: 0.68, alpha: 1),
                    NSColor(srgbRed: 0.88, green: 0.55, blue: 0.55, alpha: 1)])!
    .draw(in: frame, angle: -35)

// The menu bar strip along the top, right-aligned like the real one.
let strip = pixels(menuBar)
let stripHeight: CGFloat = 66
let stripWidth = strip.width * stripHeight / strip.height
NSColor.black.withAlphaComponent(0.12).setFill()
NSRect(x: 0, y: height - stripHeight, width: width, height: stripHeight).fill()
menuBar.draw(in: NSRect(x: width - stripWidth - 24, y: height - stripHeight, width: stripWidth, height: stripHeight))

// Panels under it.
let barSize = pixels(bar)
let quickSize = pixels(quick)
let top = height - stripHeight - 10
quick.draw(in: NSRect(x: width - quickSize.width - 120, y: top - quickSize.height,
                      width: quickSize.width, height: quickSize.height))
bar.draw(in: NSRect(x: width - quickSize.width - 120 - barSize.width - 40, y: top - barSize.height - 40,
                    width: barSize.width, height: barSize.height))

// Name and tagline on the left.
let title = NSAttributedString(string: "Barn Owl", attributes: [
    .font: NSFont.systemFont(ofSize: 150, weight: .bold), .foregroundColor: NSColor.white])
let tagline = NSAttributedString(string: "A tidier menu bar,\nand a Mac that stays awake.", attributes: [
    .font: NSFont.systemFont(ofSize: 64, weight: .medium), .foregroundColor: NSColor.white.withAlphaComponent(0.88)])
title.draw(at: NSPoint(x: 110, y: 470))
tagline.draw(in: NSRect(x: 115, y: 250, width: 900, height: 200))

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: folder.appending(path: "hero.png"))
print("Wrote docs/images/hero.png")
