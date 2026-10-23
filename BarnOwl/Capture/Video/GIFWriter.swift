import Foundation

/// Writes a GIF89a frame by frame, keeping only the frame before in memory. (ImageIO holds
/// every frame and needs gigabytes to finish a long GIF.) Each frame after the first stores
/// only the rectangle that changed, with unchanged pixels inside it transparent, so a screen
/// that mostly sits still makes a small file. Pixels within a hair of what's already showing
/// count as unchanged, so a video encoder's faint noise doesn't redraw the screen. Each frame
/// gets its own palette: exact when it has 255 colours or fewer, as screen content often
/// does, otherwise a median cut.
final class GIFWriter {
    /// Where the bytes go: a file, or nowhere, only counted (for estimates).
    enum Sink {
        case file(FileHandle)
        case count
    }

    let width: Int
    let height: Int
    private let sink: Sink
    private var buffer: [UInt8] = []
    private(set) var byteCount = 0
    /// What's showing so far (BGRA), to find what changed.
    private var canvas: [UInt32]?
    /// The frame waiting for its delay, known once the next different frame arrives.
    private var pending: (start: Double, bytes: [UInt8], transparent: Int?)?
    /// Centiseconds shown so far.
    private var shown = 0
    private(set) var delays: [Int] = []

    init(width: Int, height: Int, sink: Sink) {
        self.width = max(1, width)
        self.height = max(1, height)
        self.sink = sink
        writeHeader()
    }

    /// Adds a frame of BGRA pixels (`bytesPerRow` apart) that starts at `time` seconds.
    /// Returns false when it's the same as the frame before, which then simply lasts longer.
    @discardableResult
    func add(bgra base: UnsafeRawPointer, bytesPerRow: Int, at time: Double) throws -> Bool {
        var pixels = [UInt32](repeating: 0, count: width * height)
        pixels.withUnsafeMutableBytes { target in
            guard let out = target.baseAddress else { return }
            for y in 0..<height {
                (out + y * width * 4).copyMemory(from: base + y * bytesPerRow, byteCount: width * 4)
            }
        }
        var rect = (minX: 0, minY: 0, maxX: width - 1, maxY: height - 1)
        if let canvas {
            guard let changed = Self.changedRect(pixels, canvas, width: width, height: height) else { return false }
            rect = changed
        }
        let frame = encode(pixels, rect: rect)
        try flush(until: time)
        pending = (time, frame.bytes, frame.transparent)
        return true
    }

    /// Writes the last frame, lasting until `end` seconds, and the trailer.
    func finish(at end: Double) throws {
        try flush(until: end)
        buffer.append(0x3B)
        try drain(force: true)
        if case .file(let handle) = sink { try handle.close() }
    }

    // MARK: File

    private func writeHeader() {
        buffer += Array("GIF89a".utf8)
        append16(width)
        append16(height)
        // No global palette; 8 bits of colour resolution.
        buffer += [0x70, 0, 0]
        // Loop forever.
        buffer += [0x21, 0xFF, 0x0B]
        buffer += Array("NETSCAPE2.0".utf8)
        buffer += [0x03, 0x01, 0x00, 0x00, 0x00]
    }

    private func append16(_ value: Int) {
        buffer.append(UInt8(value & 0xFF))
        buffer.append(UInt8((value >> 8) & 0xFF))
    }

    /// Writes the waiting frame now that it's known to last until `time`.
    private func flush(until time: Double) throws {
        guard let frame = pending else { return }
        pending = nil
        let target = Int((time * 100).rounded())
        let delay = min(65_535, max(2, target - shown))
        shown += delay
        delays.append(delay)
        // Graphic control: leave the frame in place for the next to draw over.
        let packed: UInt8 = (1 << 2) | (frame.transparent == nil ? 0 : 1)
        buffer += [0x21, 0xF9, 0x04, packed]
        append16(delay)
        buffer += [UInt8(frame.transparent ?? 0), 0x00]
        buffer += frame.bytes
        try drain(force: false)
    }

    private func drain(force: Bool) throws {
        guard force || buffer.count >= 1 << 20 else { return }
        byteCount += buffer.count
        if case .file(let handle) = sink { try handle.write(contentsOf: buffer) }
        buffer.removeAll(keepingCapacity: true)
    }

    // MARK: Frames

    /// Whether two pixels look the same: each colour within 4 of the other.
    @inline(__always)
    static func matches(_ a: UInt32, _ b: UInt32) -> Bool {
        if a & 0x00FF_FFFF == b & 0x00FF_FFFF { return true }
        let r = abs(Int((a >> 16) & 0xFF) - Int((b >> 16) & 0xFF))
        let g = abs(Int((a >> 8) & 0xFF) - Int((b >> 8) & 0xFF))
        let blue = abs(Int(a & 0xFF) - Int(b & 0xFF))
        return r <= 4 && g <= 4 && blue <= 4
    }

    /// The smallest rectangle holding every pixel that differs, or nil if none does.
    static func changedRect(_ a: [UInt32], _ b: [UInt32], width: Int, height: Int)
        -> (minX: Int, minY: Int, maxX: Int, maxY: Int)? {
        var minX = width, minY = height, maxX = -1, maxY = -1
        a.withUnsafeBufferPointer { a in
            b.withUnsafeBufferPointer { b in
                for y in 0..<height {
                    let row = y * width
                    var first = -1
                    for x in 0..<width where !matches(a[row + x], b[row + x]) {
                        first = x
                        break
                    }
                    guard first >= 0 else { continue }
                    var last = first
                    var x = width - 1
                    while x > first {
                        if !matches(a[row + x], b[row + x]) {
                            last = x
                            break
                        }
                        x -= 1
                    }
                    minX = min(minX, first)
                    maxX = max(maxX, last)
                    if minY == height { minY = y }
                    maxY = y
                }
            }
        }
        guard maxX >= 0 else { return nil }
        return (minX, minY, maxX, maxY)
    }

    /// An image descriptor, palette and compressed pixels for `rect`. Pixels that match what's
    /// showing become the transparent index; the rest are drawn, and show from then on.
    private func encode(_ pixels: [UInt32], rect: (minX: Int, minY: Int, maxX: Int, maxY: Int))
        -> (bytes: [UInt8], transparent: Int?) {
        let previous = canvas
        var shown = canvas ?? pixels
        let w = rect.maxX - rect.minX + 1
        let h = rect.maxY - rect.minY + 1
        var indices = [UInt8](repeating: 0, count: w * h)
        var palette = Palette()
        pixels.withUnsafeBufferPointer { pixels in
            // Exact colours when there are few enough, as there usually are on a screen.
            var exact: [UInt32: UInt8] = [:]
            var isExact = true
            scan: for y in rect.minY...rect.maxY {
                let row = y * width
                for x in rect.minX...rect.maxX {
                    let colour = pixels[row + x] & 0x00FF_FFFF
                    if let previous, Self.matches(previous[row + x], colour) { continue }
                    guard exact[colour] == nil else { continue }
                    guard exact.count < 255 else {
                        isExact = false
                        break scan
                    }
                    exact[colour] = UInt8(exact.count)
                }
            }
            if isExact {
                palette = Palette(exact: exact)
            } else {
                var drawn: [UInt32] = []
                drawn.reserveCapacity(w * h)
                for y in rect.minY...rect.maxY {
                    let row = y * width
                    for x in rect.minX...rect.maxX {
                        let colour = pixels[row + x] & 0x00FF_FFFF
                        if let previous, Self.matches(previous[row + x], colour) { continue }
                        drawn.append(colour)
                    }
                }
                palette = Palette(medianCut: drawn, colours: 255)
            }
            let transparent = UInt8(palette.count)
            var index = 0
            for y in rect.minY...rect.maxY {
                let row = y * width
                for x in rect.minX...rect.maxX {
                    let colour = pixels[row + x] & 0x00FF_FFFF
                    if let previous, Self.matches(previous[row + x], colour) {
                        indices[index] = transparent
                    } else {
                        indices[index] = palette.index(of: colour)
                        shown[row + x] = pixels[row + x]
                    }
                    index += 1
                }
            }
        }
        canvas = shown
        let used = palette.count + (previous == nil ? 0 : 1)
        var bits = 1
        while (1 << bits) < used { bits += 1 }
        bits = max(1, bits)

        var bytes: [UInt8] = [0x2C]
        func put16(_ value: Int) {
            bytes.append(UInt8(value & 0xFF))
            bytes.append(UInt8((value >> 8) & 0xFF))
        }
        put16(rect.minX)
        put16(rect.minY)
        put16(w)
        put16(h)
        bytes.append(0x80 | UInt8(bits - 1))
        for slot in 0..<(1 << bits) {
            let colour = slot < palette.count ? palette.colours[slot] : 0
            // BGRA in memory: blue in the low byte.
            bytes.append(UInt8((colour >> 16) & 0xFF))
            bytes.append(UInt8((colour >> 8) & 0xFF))
            bytes.append(UInt8(colour & 0xFF))
        }
        let codeSize = max(2, bits)
        bytes.append(UInt8(codeSize))
        let compressed = LZW.encode(indices, codeSize: codeSize)
        var offset = 0
        while offset < compressed.count {
            let length = min(255, compressed.count - offset)
            bytes.append(UInt8(length))
            bytes += compressed[offset..<(offset + length)]
            offset += length
        }
        bytes.append(0)
        return (bytes, previous == nil ? nil : palette.count)
    }
}

/// Up to 255 colours (one slot stays free for transparency) and a quick way to look one up.
struct Palette {
    /// Colours as 0x00RRGGBB.
    private(set) var colours: [UInt32] = []
    private var exact: [UInt32: UInt8] = [:]
    /// From a 15-bit colour to its palette slot, after a median cut.
    private var table: [UInt8] = []

    var count: Int { colours.count }

    init() {}

    init(exact: [UInt32: UInt8]) {
        self.exact = exact
        colours = [UInt32](repeating: 0, count: exact.count)
        for (colour, index) in exact { colours[Int(index)] = colour }
    }

    /// Splits the colour space where the pixels are, until there are `colours` boxes, and uses
    /// each box's average.
    init(medianCut pixels: [UInt32], colours wanted: Int) {
        var counts = [Int](repeating: 0, count: 1 << 15)
        var sums = [(r: Int, g: Int, b: Int)](repeating: (0, 0, 0), count: 1 << 15)
        for colour in pixels {
            let key = Palette.key(colour)
            counts[key] += 1
            sums[key].r += Int((colour >> 16) & 0xFF)
            sums[key].g += Int((colour >> 8) & 0xFF)
            sums[key].b += Int(colour & 0xFF)
        }
        struct Box {
            var keys: [Int]
            var weight = 0
            var axis = 0
            var range = 0

            init(_ keys: [Int], counts: [Int]) {
                self.keys = keys
                var low = [31, 31, 31], high = [0, 0, 0]
                for key in keys {
                    weight += counts[key]
                    for axis in 0..<3 {
                        let value = Box.channel(key, axis)
                        low[axis] = min(low[axis], value)
                        high[axis] = max(high[axis], value)
                    }
                }
                range = -1
                for axis in 0..<3 where high[axis] - low[axis] > range {
                    range = high[axis] - low[axis]
                    self.axis = axis
                }
                range = max(0, range)
            }

            static func channel(_ key: Int, _ axis: Int) -> Int { (key >> (10 - axis * 5)) & 0x1F }
        }
        var boxes = [Box(counts.indices.filter { counts[$0] > 0 }, counts: counts)]
        while boxes.count < wanted {
            // The box with the most pixels spread over the widest range.
            var chosen = -1
            var score = 0
            for (index, box) in boxes.enumerated() where box.keys.count > 1 {
                let value = box.weight * (box.range + 1)
                if value > score {
                    score = value
                    chosen = index
                }
            }
            guard chosen >= 0 else { break }
            let box = boxes[chosen]
            let axis = box.axis
            let sorted = box.keys.sorted { Box.channel($0, axis) < Box.channel($1, axis) }
            let half = box.weight / 2
            var running = 0
            var cut = 1
            for (position, key) in sorted.enumerated() {
                running += counts[key]
                if running >= half {
                    cut = min(max(1, position + 1), sorted.count - 1)
                    break
                }
            }
            boxes[chosen] = Box(Array(sorted[..<cut]), counts: counts)
            boxes.append(Box(Array(sorted[cut...]), counts: counts))
        }
        table = [UInt8](repeating: 0, count: 1 << 15)
        for (index, box) in boxes.enumerated() {
            var r = 0, g = 0, b = 0
            for key in box.keys {
                r += sums[key].r
                g += sums[key].g
                b += sums[key].b
                table[key] = UInt8(index)
            }
            let n = max(box.weight, 1)
            colours.append(UInt32(r / n) << 16 | UInt32(g / n) << 8 | UInt32(b / n))
        }
    }

    static func key(_ colour: UInt32) -> Int {
        let r = Int((colour >> 19) & 0x1F), g = Int((colour >> 11) & 0x1F), b = Int((colour >> 3) & 0x1F)
        return r << 10 | g << 5 | b
    }

    func index(of colour: UInt32) -> UInt8 {
        if !exact.isEmpty { return exact[colour] ?? 0 }
        return table[Palette.key(colour)]
    }
}

/// GIF's variable-length LZW, with the classic open-addressed table.
enum LZW {
    static func encode(_ indices: [UInt8], codeSize: Int) -> [UInt8] {
        var output: [UInt8] = []
        output.reserveCapacity(indices.count / 2 + 16)
        guard let first = indices.first else { return output }
        let maxBits = 12
        let maxMaxCode = 1 << maxBits
        let tableSize = 5003
        let initBits = codeSize + 1
        let clearCode = 1 << codeSize
        let endCode = clearCode + 1
        var bits = initBits
        var maxCode = (1 << bits) - 1
        var nextCode = clearCode + 2
        var clearing = false
        var accumulator = 0
        var accumulated = 0
        var hashes = [Int](repeating: -1, count: tableSize)
        var codes = [Int](repeating: 0, count: tableSize)
        var shift = 0
        var probe = tableSize
        while probe < 65_536 {
            shift += 1
            probe *= 2
        }
        shift = 8 - shift

        func emit(_ code: Int) {
            accumulator |= code << accumulated
            accumulated += bits
            while accumulated >= 8 {
                output.append(UInt8(accumulator & 0xFF))
                accumulator >>= 8
                accumulated -= 8
            }
            if nextCode > maxCode || clearing {
                if clearing {
                    bits = initBits
                    maxCode = (1 << bits) - 1
                    clearing = false
                } else {
                    bits += 1
                    maxCode = bits == maxBits ? maxMaxCode : (1 << bits) - 1
                }
            }
            if code == endCode {
                while accumulated > 0 {
                    output.append(UInt8(accumulator & 0xFF))
                    accumulator >>= 8
                    accumulated -= 8
                }
            }
        }

        emit(clearCode)
        var prefix = Int(first)
        indices.withUnsafeBufferPointer { pixels in
            var position = 1
            while position < pixels.count {
                let pixel = Int(pixels[position])
                position += 1
                let key = (pixel << maxBits) + prefix
                var slot = (pixel << shift) ^ prefix
                if hashes[slot] == key {
                    prefix = codes[slot]
                    continue
                }
                var found = false
                if hashes[slot] >= 0 {
                    let step = slot == 0 ? 1 : tableSize - slot
                    repeat {
                        slot -= step
                        if slot < 0 { slot += tableSize }
                        if hashes[slot] == key {
                            prefix = codes[slot]
                            found = true
                            break
                        }
                    } while hashes[slot] >= 0
                }
                if found { continue }
                emit(prefix)
                prefix = pixel
                if nextCode < maxMaxCode {
                    codes[slot] = nextCode
                    nextCode += 1
                    hashes[slot] = key
                } else {
                    for index in hashes.indices { hashes[index] = -1 }
                    nextCode = clearCode + 2
                    clearing = true
                    emit(clearCode)
                }
            }
        }
        emit(prefix)
        emit(endCode)
        return output
    }
}
