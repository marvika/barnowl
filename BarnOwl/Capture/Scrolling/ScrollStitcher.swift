import CoreGraphics
import Foundation
import Vision

/// One frame of the area being scrolled: 32-bit BGRA pixels, one `UInt32`
/// each (alpha in the top byte), the top row first.
struct ScrollFrame: Sendable {
    let width: Int
    let height: Int
    let pixels: [UInt32]

    /// The layout of ScreenCaptureKit's BGRA frames.
    static let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue

    init(width: Int, height: Int, pixels: [UInt32]) {
        precondition(pixels.count == width * height, "A frame needs width × height pixels")
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    /// Draws `image` in `colorSpace`: pixel for pixel when it's already in it.
    init?(image: CGImage, colorSpace: CGColorSpace) {
        let width = image.width, height = image.height
        guard width > 0, height > 0 else { return nil }
        var pixels = [UInt32](repeating: 0, count: width * height)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: colorSpace,
                                          bitmapInfo: Self.bitmapInfo) else { return false }
            context.interpolationQuality = .none
            context.setBlendMode(.copy)
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        self.init(width: width, height: height, pixels: pixels)
    }

    /// Copies rows that sit `bytesPerRow` apart, as a pixel buffer's do.
    init(width: Int, height: Int, bytesPerRow: Int, copying base: UnsafeRawPointer) {
        var pixels = [UInt32](repeating: 0, count: width * height)
        pixels.withUnsafeMutableBytes { buffer in
            guard let target = buffer.baseAddress else { return }
            for y in 0..<height {
                memcpy(target + y * width * 4, base + y * bytesPerRow, width * 4)
            }
        }
        self.init(width: width, height: height, pixels: pixels)
    }

    /// Some of its rows as an image.
    func image(rows: Range<Int>, colorSpace: CGColorSpace) -> CGImage? {
        let rows = rows.clamped(to: 0..<height)
        guard !rows.isEmpty else { return nil }
        let slice = Array(pixels[(rows.lowerBound * width)..<(rows.upperBound * width)])
        return ScrollFrame.image(slice, width: width, height: rows.count, colorSpace: colorSpace)
    }

    static func image(_ pixels: [UInt32], width: Int, height: Int, colorSpace: CGColorSpace) -> CGImage? {
        let data = pixels.withUnsafeBytes { Data($0) } as CFData
        guard let provider = CGDataProvider(data: data) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: colorSpace, bitmapInfo: CGBitmapInfo(rawValue: bitmapInfo), provider: provider,
                       decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}

/// Turns frames of an area you scroll through into one tall picture.
///
/// Each row of a frame becomes a hash. A new frame goes where its rows line up
/// with what's stitched so far: distinctive rows vote on the offset, and most of
/// the overlap must then really match. Only rows below the end are added. Rows
/// that stay put at the top and bottom when the page first moves are a sticky
/// header and footer, kept once, at the top and the bottom. Frames that land
/// above the end (you scrolled back up) add nothing, and a frame that can't be
/// placed is left out rather than glued on in the wrong place. When rows don't
/// match exactly (video, noise), Vision's registration suggests the offset and
/// a looser comparison checks it.
final class ScrollStitcher {
    struct Configuration: Sendable {
        /// The tallest picture, in pixels.
        var maxHeight = 30_000
        /// Columns at the right edge left out of matching, where overlay scroll bars come and go.
        var ignoredTrailingColumns = 24
        /// The share of overlapping rows that must match for a frame to be placed.
        var requiredMatch = 0.85
        /// How far above the end, in frame heights, a frame can still be placed.
        var lookBack = 4
        /// Asks Vision for the offset when rows don't match exactly.
        var usesRegistration = true
        /// How different, per channel on average, two rows may be and still match in the looser comparison.
        var tolerance = 10
    }

    enum Outcome: Equatable, Sendable {
        /// The first frame: the picture starts as it.
        case started
        /// Nothing moved.
        case unchanged
        /// Placed `offset` pixels below where the first frame was (negative above it),
        /// adding `added` rows at the end: none when it's within what's stitched already.
        case placed(offset: Int, added: Int)
        /// It didn't line up with the picture closely enough, so it was left out.
        case mismatch
    }

    let configuration: Configuration
    let colorSpace: CGColorSpace
    private(set) var width = 0
    private(set) var frameHeight = 0
    /// The sticky rows at the top and bottom of every frame, found when the page first moves.
    private(set) var header = 0
    private(set) var footer = 0
    private(set) var hasMoved = false
    /// The picture reached `maxHeight`; nothing more is added.
    private(set) var isFull = false
    /// Where the last placed frame sits, in pixels below the first frame.
    private(set) var offset = 0

    /// The picture's height so far, in pixels.
    var height: Int { hasMoved ? header + content.count + footer : frameHeight }
    /// The rows that scroll, between the header and the footer.
    var bandHeight: Int { frameHeight - header - footer }

    private var reference: ScrollFrame?
    private var referencePrints = RowPrints(hashes: [], detailed: [])
    private var headerPixels: [UInt32] = []
    private var footerPixels: [UInt32] = []
    private var content = Rows()
    private var frameNumber = 0
    /// The frame the picture started with, before the first move.
    private var startFrame = 0

    /// Rows the overscroll bounce can add at the very end, given back when it settles.
    private static let overscrollFrames = 20

    init(configuration: Configuration = Configuration(), colorSpace: CGColorSpace = CGColorSpace(name: CGColorSpace.sRGB)!) {
        self.configuration = configuration
        self.colorSpace = colorSpace
    }

    // MARK: Adding frames

    func add(_ image: CGImage) -> Outcome {
        guard let frame = ScrollFrame(image: image, colorSpace: colorSpace) else { return .mismatch }
        return add(frame)
    }

    func add(_ frame: ScrollFrame) -> Outcome {
        frameNumber += 1
        guard reference != nil else {
            width = frame.width
            frameHeight = frame.height
            reference = frame
            referencePrints = prints(of: frame)
            return .started
        }
        guard frame.width == width, frame.height == frameHeight else { return .mismatch }
        let prints = prints(of: frame)
        if prints.hashes == referencePrints.hashes { return .unchanged }
        return hasMoved ? place(frame, prints) : firstMove(frame, prints)
    }

    /// Until the page moves, the header and footer are unknown: compare whole frames.
    private func firstMove(_ frame: ScrollFrame, _ prints: RowPrints) -> Outcome {
        guard let reference else { return .mismatch }
        let previous = referencePrints
        var rowsOf: [UInt64: [Int]] = [:]
        for row in 0..<frameHeight where previous.detailed[row] {
            rowsOf[previous.hashes[row], default: []].append(row)
        }
        var tally: [Int: Int] = [:]
        for row in uniqueDetailedRows(prints, in: 0..<frameHeight) {
            guard let matches = rowsOf[prints.hashes[row]], matches.count <= 8 else { continue }
            for match in matches where match != row { tally[match - row, default: 0] += 1 }
        }
        for shift in ranked(tally, near: 0) {
            let bands = staticBands(shift: shift, prints: prints,
                                    same: { prints.hashes[$0] == previous.hashes[$0] },
                                    shifted: { prints.hashes[$0] == previous.hashes[$0 + shift] })
            if let bands {
                begin(header: bands.header, footer: bands.footer)
                return accept(frame, prints, at: shift)
            }
        }
        // The middle of the frame: sticky bars would hold Vision still.
        let middle = (frameHeight / 4)..<(frameHeight * 3 / 4)
        if configuration.usesRegistration,
           let shift = Self.registeredShift(from: reference, to: frame, rows: middle, colorSpace: colorSpace) {
            // Vision can be a pixel out; the shift that fits the middle best decides.
            let fits = ((shift - 2)...(shift + 2)).filter { $0 != 0 }.map { candidate -> (Int, Double) in
                var difference = 0, rows = 0
                for row in middle where row + candidate >= 0 && row + candidate < frameHeight {
                    difference += Self.rowDifference(frame.pixels, row * width, reference.pixels,
                                                     (row + candidate) * width, span: span)
                    rows += 1
                }
                return (candidate, rows > 0 ? Double(difference) / Double(rows) : .infinity)
            }
            if let best = fits.min(by: { $0.1 < $1.1 })?.0,
               let bands = staticBands(shift: best, prints: prints,
                                       same: { self.close(frame, prints, $0, reference, previous, $0) },
                                       shifted: { self.close(frame, prints, $0, reference, previous, $0 + best) }) {
                begin(header: bands.header, footer: bands.footer)
                return accept(frame, prints, at: best)
            }
        }
        // Nothing moved as a whole: something on the page changed where it was.
        var stayed = 0
        for row in 0..<frameHeight where prints.hashes[row] == previous.hashes[row] { stayed += 1 }
        if stayed * 2 >= frameHeight {
            self.reference = frame
            referencePrints = prints
            return .unchanged
        }
        return .mismatch
    }

    /// After the first move: place the frame's scrolling rows against the picture's last few screens.
    private func place(_ frame: ScrollFrame, _ prints: RowPrints) -> Outcome {
        let band = header..<(header + bandHeight)
        let earliest = max(0, content.count - configuration.lookBack * frameHeight)
        var tally: [Int: Int] = [:]
        for row in uniqueDetailedRows(prints, in: band) {
            guard let matches = content.index[prints.hashes[row]] else { continue }
            var used = 0
            for match in matches.reversed() {
                guard match >= earliest, used < 8 else { break }
                tally[match - (row - header), default: 0] += 1
                used += 1
            }
        }
        for candidate in ranked(tally, near: offset) where matchesExactly(prints, at: candidate) {
            return accept(frame, prints, at: candidate)
        }
        if configuration.usesRegistration, let reference,
           let shift = Self.registeredShift(from: reference, to: frame, rows: band, colorSpace: colorSpace) {
            // Vision can be a pixel out; of the offsets that pass, the closest fit wins.
            let fits = ((shift - 2)...(shift + 2)).compactMap { candidate -> (Int, Double)? in
                closeness(frame, prints, at: offset + candidate).map { (offset + candidate, $0) }
            }
            if let best = fits.min(by: { $0.1 < $1.1 }) { return accept(frame, prints, at: best.0) }
        }
        return .mismatch
    }

    /// Sets the sticky bands, and starts the picture with the frame before the move.
    private func begin(header: Int, footer: Int) {
        guard let reference else { return }
        self.header = header
        self.footer = footer
        hasMoved = true
        offset = 0
        headerPixels = Array(reference.pixels[0..<(header * width)])
        footerPixels = Array(reference.pixels[((frameHeight - footer) * width)...])
        let room = max(0, configuration.maxHeight - header - footer)
        let rows = min(bandHeight, room)
        startFrame = frameNumber - 1
        content.append(reference, referencePrints, rows: header..<(header + rows), frame: startFrame)
        if rows < bandHeight { isFull = true }
    }

    /// Puts a frame's band at `offset` in the picture and adds what's new.
    private func accept(_ frame: ScrollFrame, _ prints: RowPrints, at offset: Int) -> Outcome {
        let band = bandHeight, count = content.count
        let end = offset + band
        var added = 0
        if end > count {
            let first = max(0, count - offset)
            let wanted = band - first
            let room = max(0, configuration.maxHeight - (header + count + footer))
            added = min(wanted, room)
            if added > 0 {
                let start = header + first
                content.append(frame, prints, rows: start..<(start + added), frame: frameNumber)
            }
            if added < wanted {
                isFull = true
            } else {
                takeFooter(from: frame)
            }
        } else if end == count {
            takeFooter(from: frame)
        } else {
            giveBackOverscroll(below: end, frame: frame)
        }
        self.offset = offset
        reference = frame
        referencePrints = prints
        return .placed(offset: offset, added: added)
    }

    /// Scrolling past the end bounces: the page slides up over blank rows and
    /// settles back. Blank rows added just now, below a frame that has settled
    /// above them, were that bounce, not the page.
    private func giveBackOverscroll(below end: Int, frame: ScrollFrame) {
        let extra = content.count - end
        guard extra > 0, extra <= frameHeight / 2, !isFull else { return }
        let addedIn = content.addedIn[end]
        guard addedIn > startFrame, addedIn >= frameNumber - Self.overscrollFrames else { return }
        for row in end..<content.count where content.detailed[row] { return }
        content.truncate(to: end)
        takeFooter(from: frame)
    }

    /// The footer of the frame that shows the end of the picture continues it.
    private func takeFooter(from frame: ScrollFrame) {
        guard footer > 0 else { return }
        footerPixels = Array(frame.pixels[((frameHeight - footer) * width)...])
    }

    // MARK: The picture

    /// The whole picture: header, everything scrolled past, footer.
    func image() -> CGImage? {
        guard let reference else { return nil }
        guard hasMoved else { return reference.image(rows: 0..<frameHeight, colorSpace: colorSpace) }
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: colorSpace, bitmapInfo: ScrollFrame.bitmapInfo),
              let data = context.data else { return nil }
        // A bitmap context's memory runs from the top row down.
        let target = data.assumingMemoryBound(to: UInt32.self)
        var at = 0
        for part in [headerPixels, content.pixels, footerPixels] {
            part.withUnsafeBufferPointer { source in
                guard let base = source.baseAddress, !source.isEmpty else { return }
                (target + at).update(from: base, count: source.count)
            }
            at += part.count
        }
        return context.makeImage()
    }

    /// The bottom of the picture, shrunk to `width` pixels across and at most
    /// `height` tall: it follows the end as the picture grows.
    func preview(width previewWidth: Int, height previewHeight: Int) -> CGImage? {
        guard reference != nil, previewWidth > 0, previewHeight > 0 else { return nil }
        let scale = Double(width) / Double(previewWidth)
        let visible = min(height, Int(Double(previewHeight) * scale))
        let outHeight = max(1, Int(Double(visible) / scale))
        let top = height - visible
        var pixels = [UInt32](repeating: 0, count: previewWidth * outHeight)
        for y in 0..<outHeight {
            let sourceY = min(height - 1, top + Int((Double(y) + 0.5) * scale))
            for x in 0..<previewWidth {
                let sourceX = min(width - 1, Int((Double(x) + 0.5) * scale))
                pixels[y * previewWidth + x] = averaged(around: sourceX, sourceY, radius: max(0, Int(scale / 2)))
            }
        }
        return ScrollFrame.image(pixels, width: previewWidth, height: outHeight, colorSpace: colorSpace)
    }

    /// A few pixels around a point, averaged.
    private func averaged(around x: Int, _ y: Int, radius: Int) -> UInt32 {
        let offsets = radius == 0 ? [0] : [-radius, 0, radius]
        var blue = 0, green = 0, red = 0, samples = 0
        for dy in offsets {
            for dx in offsets {
                let pixel = self.pixel(x: min(width - 1, max(0, x + dx)), y: min(height - 1, max(0, y + dy)))
                blue += Int(pixel & 0xFF)
                green += Int((pixel >> 8) & 0xFF)
                red += Int((pixel >> 16) & 0xFF)
                samples += 1
            }
        }
        let b = UInt32(blue / samples), g = UInt32(green / samples), r = UInt32(red / samples)
        return 0xFF00_0000 | (r << 16) | (g << 8) | b
    }

    /// One pixel of the picture so far.
    private func pixel(x: Int, y: Int) -> UInt32 {
        guard hasMoved else { return reference?.pixels[y * width + x] ?? 0 }
        if y < header { return headerPixels[y * width + x] }
        let row = y - header
        if row < content.count { return content.pixels[row * width + x] }
        return footerPixels[(row - content.count) * width + x]
    }

    // MARK: Matching

    /// What each row looks like: a hash of its pixels, and whether it has any detail.
    struct RowPrints {
        var hashes: [UInt64]
        var detailed: [Bool]
    }

    /// The columns rows are compared over: all but the right edge's scroll bar.
    private var span: Int {
        let span = width - configuration.ignoredTrailingColumns
        return span >= width / 2 ? span : width
    }

    func prints(of frame: ScrollFrame) -> RowPrints {
        let span = self.span, width = frame.width
        let step = max(1, span / 512)
        var hashes = [UInt64](repeating: 0, count: frame.height)
        var detailed = [Bool](repeating: false, count: frame.height)
        frame.pixels.withUnsafeBufferPointer { pixels in
            for y in 0..<frame.height {
                let row = y * width
                var hash: UInt64 = 0xCBF2_9CE4_8422_2325
                for x in 0..<span {
                    hash = (hash ^ UInt64(pixels[row + x])) &* 0x0000_0100_0000_01B3
                }
                var lowest = Int.max, highest = Int.min
                for x in stride(from: 0, to: span, by: step) {
                    let pixel = pixels[row + x]
                    let blue = Int(pixel & 0xFF), green = Int((pixel >> 8) & 0xFF), red = Int((pixel >> 16) & 0xFF)
                    let light = blue + green + red
                    lowest = min(lowest, light)
                    highest = max(highest, light)
                }
                hashes[y] = hash
                detailed[y] = highest - lowest > 48
            }
        }
        return RowPrints(hashes: hashes, detailed: detailed)
    }

    /// Rows with detail whose hash appears only once among `rows`: the ones worth a vote.
    private func uniqueDetailedRows(_ prints: RowPrints, in rows: Range<Int>) -> [Int] {
        var seen: [UInt64: Int] = [:]
        for row in rows where prints.detailed[row] { seen[prints.hashes[row], default: 0] += 1 }
        return rows.filter { prints.detailed[$0] && seen[prints.hashes[$0]] == 1 }
    }

    /// The best few offsets: most votes first, then the nearest.
    private func ranked(_ tally: [Int: Int], near: Int) -> [Int] {
        let sorted = tally.sorted { first, second in
            if first.value != second.value { return first.value > second.value }
            return abs(first.key - near) < abs(second.key - near)
        }
        return sorted.prefix(4).map(\.key)
    }

    private var minimumOverlap: Int { max(12, bandHeight / 16) }

    /// The band's rows that would overlap the picture at `offset`, if enough do.
    private func overlap(at offset: Int) -> Range<Int>? {
        let first = max(0, -offset), last = min(bandHeight, content.count - offset)
        guard last - first >= minimumOverlap else { return nil }
        return first..<last
    }

    /// The frame's band at `offset` overlaps the picture, and enough of the overlap is identical.
    private func matchesExactly(_ prints: RowPrints, at offset: Int) -> Bool {
        guard let rows = overlap(at: offset) else { return false }
        var matched = 0, detailed = 0, detailedRows = 0
        for row in rows {
            let isDetailed = prints.detailed[header + row]
            if isDetailed { detailedRows += 1 }
            guard prints.hashes[header + row] == content.hashes[offset + row] else { continue }
            matched += 1
            if isDetailed { detailed += 1 }
        }
        return enough(matched: matched, of: rows.count, detailed: detailed, of: detailedRows)
    }

    /// The looser check, for an offset Vision suggested: nil when too little of
    /// the overlap is close, else how different it is on average.
    private func closeness(_ frame: ScrollFrame, _ prints: RowPrints, at offset: Int) -> Double? {
        guard let rows = overlap(at: offset) else { return nil }
        var matched = 0, detailed = 0, detailedRows = 0, total = 0
        let allowed = configuration.tolerance * Self.samples(span: span)
        for row in rows {
            let frameRow = header + row, pictureRow = offset + row
            let difference = Self.rowDifference(frame.pixels, frameRow * width, content.pixels, pictureRow * width,
                                                span: span)
            total += difference
            if prints.detailed[frameRow] { detailedRows += 1 }
            guard prints.detailed[frameRow] == content.detailed[pictureRow], difference <= allowed else { continue }
            matched += 1
            if prints.detailed[frameRow] { detailed += 1 }
        }
        guard enough(matched: matched, of: rows.count, detailed: detailed, of: detailedRows) else { return nil }
        return Double(total) / Double(rows.count)
    }

    /// Most of the overlap matches, and so do most of its rows with detail: on a
    /// sparse page, matching blank rows proves nothing.
    private func enough(matched: Int, of overlap: Int, detailed: Int, of detailedRows: Int) -> Bool {
        guard Double(matched) >= configuration.requiredMatch * Double(overlap) else { return false }
        return detailed >= 3 && detailed * 3 >= detailedRows * 2
    }

    /// Two rows with detail in the same way, at most `tolerance` apart per channel on average.
    private func close(_ frame: ScrollFrame, _ prints: RowPrints, _ row: Int,
                       _ other: ScrollFrame, _ otherPrints: RowPrints, _ otherRow: Int) -> Bool {
        guard prints.detailed[row] == otherPrints.detailed[otherRow] else { return false }
        let difference = Self.rowDifference(frame.pixels, row * width, other.pixels, otherRow * width, span: span)
        return difference <= configuration.tolerance * Self.samples(span: span)
    }

    /// How many channel values `rowDifference` adds up.
    static func samples(span: Int) -> Int { (span + 1) / 2 * 3 }

    /// The summed difference of two rows' channels, over every other pixel.
    static func rowDifference(_ first: [UInt32], _ firstStart: Int, _ second: [UInt32], _ secondStart: Int,
                              span: Int) -> Int {
        var difference = 0
        for x in stride(from: 0, to: span, by: 2) {
            let a = first[firstStart + x], b = second[secondStart + x]
            difference += abs(Int(a & 0xFF) - Int(b & 0xFF))
            difference += abs(Int((a >> 8) & 0xFF) - Int((b >> 8) & 0xFF))
            difference += abs(Int((a >> 16) & 0xFF) - Int((b >> 16) & 0xFF))
        }
        return difference
    }

    /// The sticky header and footer, if the page moving by `shift` explains the rest of the frame.
    ///
    /// The footer is the run of unchanged rows at the bottom. The header is
    /// where splitting the frame into "unchanged above, moved below" explains
    /// the most rows; rows that fit either way (blank space) go to the header,
    /// which costs nothing, since the picture starts with that frame anyway.
    private func staticBands(shift: Int, prints: RowPrints, same: (Int) -> Bool,
                             shifted: (Int) -> Bool) -> (header: Int, footer: Int)? {
        let height = frameHeight, cap = frameHeight * 2 / 5
        var footer = 0
        while footer < cap, same(height - 1 - footer) { footer += 1 }
        let end = height - footer
        guard abs(shift) < end else { return nil }
        var moved = [Bool](repeating: false, count: end)
        for row in 0..<end where row + shift >= 0 && row + shift < end { moved[row] = shifted(row) }
        var suffix = [Int](repeating: 0, count: end + 1)
        var detailedSuffix = [Int](repeating: 0, count: end + 1)
        for row in stride(from: end - 1, through: 0, by: -1) {
            suffix[row] = suffix[row + 1] + (moved[row] ? 1 : 0)
            detailedSuffix[row] = detailedSuffix[row + 1] + (moved[row] && prints.detailed[row] ? 1 : 0)
        }
        var best = -1, header = 0, unchanged = 0
        for split in 0...min(cap, end) {
            if split > 0, same(split - 1) { unchanged += 1 }
            let start = shift > 0 ? split : min(end, split - shift)
            let score = unchanged + suffix[start]
            if score >= best {
                best = score
                header = split
            }
        }
        let band = end - header
        guard band >= height / 4 else { return nil }
        let start = shift > 0 ? header : min(end, header - shift)
        let stop = shift > 0 ? end - shift : end
        guard stop - start >= max(12, band / 16) else { return nil }
        var detailedRows = 0
        for row in start..<stop where prints.detailed[row] { detailedRows += 1 }
        guard enough(matched: suffix[start], of: stop - start, detailed: detailedSuffix[start], of: detailedRows) else {
            return nil
        }
        return (header, footer)
    }

    /// How far Vision sees the content move up from `reference` to `frame` over
    /// the same rows, in whole pixels; nil when it's sideways, tiny or too far.
    static func registeredShift(from reference: ScrollFrame, to frame: ScrollFrame, rows: Range<Int>,
                                colorSpace: CGColorSpace) -> Int? {
        guard let before = reference.image(rows: rows, colorSpace: colorSpace),
              let after = frame.image(rows: rows, colorSpace: colorSpace) else { return nil }
        let request = VNTranslationalImageRegistrationRequest(targetedCGImage: after, options: [:])
        let handler = VNImageRequestHandler(cgImage: before, options: [:])
        do { try handler.perform([request]) } catch { return nil }
        guard let transform = request.results?.first?.alignmentTransform, abs(transform.tx) <= 2 else { return nil }
        // Vision's origin is at the bottom: content moving up is a negative y.
        let shift = Int((-transform.ty).rounded())
        guard shift != 0, abs(shift) < rows.count * 9 / 10 else { return nil }
        return shift
    }
}

/// The scrolling rows stitched so far, with what's needed to find a row again.
private struct Rows {
    var pixels: [UInt32] = []
    var hashes: [UInt64] = []
    var detailed: [Bool] = []
    /// Which frame added each row.
    var addedIn: [Int] = []
    /// Rows with detail, by hash, top to bottom.
    var index: [UInt64: [Int]] = [:]

    var count: Int { hashes.count }

    mutating func append(_ frame: ScrollFrame, _ prints: ScrollStitcher.RowPrints, rows: Range<Int>, frame number: Int) {
        guard !rows.isEmpty else { return }
        pixels.append(contentsOf: frame.pixels[(rows.lowerBound * frame.width)..<(rows.upperBound * frame.width)])
        for row in rows {
            let hash = prints.hashes[row]
            if prints.detailed[row] { index[hash, default: []].append(hashes.count) }
            hashes.append(hash)
            detailed.append(prints.detailed[row])
            addedIn.append(number)
        }
    }

    mutating func truncate(to count: Int) {
        guard count < self.count else { return }
        let width = pixels.count / self.count
        for row in count..<self.count where detailed[row] {
            index[hashes[row]]?.removeAll { $0 >= count }
        }
        pixels.removeSubrange((count * width)...)
        hashes.removeSubrange(count...)
        detailed.removeSubrange(count...)
        addedIn.removeSubrange(count...)
    }
}
