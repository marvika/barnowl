// Turns a screen recording into a looping GIF for the README, with Apple's
// own frameworks (no ffmpeg needed). macOS's screen-recording indicator in
// the menu bar (a purple pill, and a dot by Control Center) is found in each
// frame and painted over with the menu bar behind it.
//
//   swift Scripts/make-gif.swift <in.mov> <out.gif> [fps=12] [width=720] [crop-left=0]
import AVFoundation
import AppKit
import ImageIO
import UniformTypeIdentifiers

let arguments = CommandLine.arguments
guard arguments.count >= 3 else {
    print("usage: swift Scripts/make-gif.swift <in.mov> <out.gif> [fps] [width] [crop-left]")
    exit(1)
}
let input = URL(fileURLWithPath: arguments[1])
let output = URL(fileURLWithPath: arguments[2])
let fps = arguments.count > 3 ? Double(arguments[3]) ?? 12 : 12
let width = arguments.count > 4 ? Double(arguments[4]) ?? 720 : 720
let cropLeft = arguments.count > 5 ? Int(arguments[5]) ?? 0 : 0

let asset = AVURLAsset(url: input)
let duration = try await asset.load(.duration).seconds
let times = stride(from: 0.0, to: duration, by: 1 / fps).map { CMTime(seconds: $0, preferredTimescale: 600) }
let generator = AVAssetImageGenerator(asset: asset)
generator.requestedTimeToleranceBefore = .zero
generator.requestedTimeToleranceAfter = .zero
generator.maximumSize = CGSize(width: width, height: 10_000)

// Frames past the end can't be read; keep the ones that can.
var frames: [CGImage] = []
for await result in generator.images(for: times) {
    if let image = try? result.image { frames.append(image) }
}

/// Where the recording indicator is in one frame: clusters of its purple in
/// the menu bar, big enough not to be a stray pixel of the clock.
func indicatorBoxes(in frame: CGImage) -> [CGRect] {
    let barHeight = Int(Double(frame.height) * 0.06)
    guard let strip = frame.cropping(to: CGRect(x: 0, y: 0, width: frame.width, height: barHeight)) else { return [] }
    let rep = NSBitmapImageRep(cgImage: strip)
    var columns: [Int: (minY: Int, maxY: Int, count: Int)] = [:]
    for y in 0..<rep.pixelsHigh {
        for x in 0..<rep.pixelsWide {
            guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
            if c.blueComponent > 0.9, (0.4...0.7).contains(c.redComponent), (0.35...0.7).contains(c.greenComponent) {
                let old = columns[x] ?? (y, y, 0)
                columns[x] = (min(old.minY, y), max(old.maxY, y), old.count + 1)
            }
        }
    }
    var boxes: [(rect: CGRect, count: Int)] = []
    for x in columns.keys.sorted() {
        let span = columns[x]!
        let column = CGRect(x: x, y: span.minY, width: 1, height: span.maxY - span.minY + 1)
        if let last = boxes.last, CGFloat(x) - last.rect.maxX < 6 {
            boxes[boxes.count - 1] = (last.rect.union(column), last.count + span.count)
        } else {
            boxes.append((column, span.count))
        }
    }
    // The pill's white symbol isn't purple; pad to cover it and the soft edge.
    return boxes.filter { $0.count >= 12 }.map { $0.rect.insetBy(dx: -6, dy: -5) }
}

/// Paints each box over, row by row, blending the colours just left and
/// right of it, so it melts into the menu bar.
func hiding(_ boxes: [CGRect], in image: CGImage) -> CGImage {
    guard !boxes.isEmpty, let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                                bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return image }
    let height = CGFloat(image.height)
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    let rep = NSBitmapImageRep(cgImage: image)
    for box in boxes {
        let left = max(0, Int(box.minX) - 3), right = min(image.width - 1, Int(box.maxX) + 3)
        for y in max(0, Int(box.minY))..<min(image.height, Int(box.maxY)) {
            guard let a = rep.colorAt(x: left, y: y)?.usingColorSpace(.sRGB),
                  let b = rep.colorAt(x: right, y: y)?.usingColorSpace(.sRGB) else { continue }
            let span = CGFloat(max(1, right - left))
            for x in max(0, Int(box.minX))..<min(image.width, Int(box.maxX)) {
                let t = CGFloat(x - left) / span
                context.setFillColor(red: a.redComponent + (b.redComponent - a.redComponent) * t,
                                     green: a.greenComponent + (b.greenComponent - a.greenComponent) * t,
                                     blue: a.blueComponent + (b.blueComponent - a.blueComponent) * t, alpha: 1)
                // Bitmap rows count down from the top; the context's count up.
                context.fill(CGRect(x: CGFloat(x), y: height - CGFloat(y) - 1, width: 1, height: 1))
            }
        }
    }
    return context.makeImage() ?? image
}

/// Trims empty sky off the left.
func cropped(_ image: CGImage, left: Int) -> CGImage {
    guard left > 0 else { return image }
    return image.cropping(to: CGRect(x: left, y: 0, width: image.width - left, height: image.height)) ?? image
}

// The indicator appears a moment after recording starts, so the first frames
// show the menu bar without it: copy those exact pixels over it. (Painting a
// blend is the fallback, for a recording with no clean frame.)
let found = frames.map(indicatorBoxes(in:))
let clean = found.firstIndex(where: \.isEmpty).map { frames[$0] }

func restoring(_ boxes: [CGRect], in image: CGImage, from reference: CGImage) -> CGImage {
    guard !boxes.isEmpty, let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                                bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return image }
    let full = CGRect(x: 0, y: 0, width: image.width, height: image.height)
    context.draw(image, in: full)
    for box in boxes {
        // Bitmap rows count down from the top; the context's count up.
        let flipped = CGRect(x: box.minX, y: CGFloat(image.height) - box.maxY, width: box.width, height: box.height)
        context.saveGState()
        context.clip(to: flipped)
        context.draw(reference, in: full)
        context.restoreGState()
    }
    return context.makeImage() ?? image
}

frames = zip(frames, found).map { frame, boxes in
    let fixed = clean.map { restoring(boxes, in: frame, from: $0) } ?? hiding(boxes, in: frame)
    return cropped(fixed, left: cropLeft)
}

guard !frames.isEmpty,
      let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.gif.identifier as CFString, frames.count, nil)
else { fatalError("No frames, or can't write \(output.path)") }
CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
let delay = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1 / fps,
                                             kCGImagePropertyGIFUnclampedDelayTime: 1 / fps]] as CFDictionary
for image in frames { CGImageDestinationAddImage(destination, image, delay) }
guard CGImageDestinationFinalize(destination) else { fatalError("Couldn't write \(output.path)") }
let bytes = (try? FileManager.default.attributesOfItem(atPath: output.path)[.size] as? Int) ?? 0
print("Wrote \(output.path): \(frames.count) frames, \(bytes / 1024) KB")
