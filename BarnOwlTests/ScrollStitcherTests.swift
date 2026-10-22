import CoreGraphics
import Testing
@testable import BarnOwl

/// A tall made-up page: lines of "words" whose rows all differ, a few pictures,
/// rules and blank gaps, with a sticky header and footer to put frames in.
private struct SyntheticPage {
    let width: Int
    let height: Int
    var pixels: [UInt32]
    static let white: UInt32 = 0xFFFF_FFFF

    init(width: Int, height: Int, seed: UInt64) {
        self.width = width
        self.height = height
        pixels = [UInt32](repeating: Self.white, count: width * height)
        var random = SplitMix(seed: seed)
        var top = 12
        var line = 0
        // A blank margin at the end, as pages have.
        while top < height - 40 {
            line += 1
            if line % 9 == 0 {
                // A picture: a gradient block, every row different.
                let tall = 50
                let left = Int.random(in: 8...40, using: &random)
                let hue = UInt32.random(in: 0...255, using: &random)
                for y in top..<min(top + tall, height - 40) {
                    for x in left..<(width - 60) {
                        let red = (hue &+ UInt32(y * 3)) & 0xFF, green = UInt32(x * 2) & 0xFF
                        set(x, y, 0xFF00_0000 | (red << 16) | (green << 8) | 0x80)
                    }
                }
                top += tall + 14
                continue
            }
            if line % 13 == 0 {
                // A rule across the page, and a gap after it.
                for x in 8..<(width - 8) { set(x, top, 0xFFD0_D0D0) }
                top += 30
                continue
            }
            var x = 8
            while x < width - 30 {
                let word = Int.random(in: 6...34, using: &random)
                let wordTop = top + Int.random(in: 0...3, using: &random)
                let wordBottom = top + 10 + Int.random(in: 0...5, using: &random)
                let ink = UInt32.random(in: 0x10...0x60, using: &random)
                for y in wordTop..<wordBottom {
                    for dx in 0..<min(word, width - 30 - x) {
                        let shade = (ink + UInt32((y - wordTop) * 7 + dx % 5)) & 0xFF
                        set(x + dx, y, 0xFF00_0000 | (shade << 16) | (shade << 8) | shade)
                    }
                }
                x += word + Int.random(in: 4...9, using: &random)
            }
            top += 22
        }
    }

    private mutating func set(_ x: Int, _ y: Int, _ pixel: UInt32) {
        pixels[y * width + x] = pixel
    }

    func rows(_ range: Range<Int>) -> [UInt32] {
        Array(pixels[(range.lowerBound * width)..<(range.upperBound * width)])
    }
}

/// A seeded generator, so every run draws the same page.
private struct SplitMix: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// A window onto the page, `height` pixels tall, with a sticky header and footer.
private struct Viewport {
    let page: SyntheticPage
    let height: Int
    var headerHeight = 40
    var footerHeight = 30

    var width: Int { page.width }
    var band: Int { height - headerHeight - footerHeight }
    /// The furthest the page scrolls.
    var end: Int { page.height - band }

    var header: [UInt32] {
        var pixels = [UInt32](repeating: 0xFF3D_3A8F, count: width * headerHeight)
        guard headerHeight == 40 else { return pixels }
        for y in 12..<28 { for x in 8..<40 { pixels[y * width + x] = 0xFFFF_FFFF } }
        for y in 10..<30 { for x in 60..<(width - 40) { pixels[y * width + x] = 0xFF2A_2870 + UInt32(y) } }
        return pixels
    }

    var footer: [UInt32] {
        var pixels = [UInt32](repeating: 0xFFEE_EEEE, count: width * footerHeight)
        guard footerHeight == 30 else { return pixels }
        for x in 0..<width { pixels[x] = 0xFFC0_C0C0 }
        for y in 8..<22 { for x in stride(from: 10, to: width - 30, by: 50) { for dx in 0..<30 { pixels[y * width + x + dx] = 0xFF55_5555 } } }
        return pixels
    }

    func frame(at scroll: Int, overscroll: Int = 0) -> ScrollFrame {
        let first = scroll + overscroll
        let shown = min(band, page.height - first)
        var pixels = header + page.rows(first..<(first + shown))
        pixels += [UInt32](repeating: SyntheticPage.white, count: (band - shown) * width)
        pixels += footer
        return ScrollFrame(width: width, height: height, pixels: pixels)
    }

    /// What a capture from `start` down to `stop` should be, row for row.
    func expected(from start: Int, to stop: Int) -> [UInt32] {
        header + page.rows(start..<(stop + band)) + footer
    }
}

private func pixels(of image: CGImage?) throws -> ScrollFrame {
    let image = try #require(image)
    return try #require(ScrollFrame(image: image, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!))
}

/// The first row where two pictures differ, if any.
private func firstDifference(_ got: ScrollFrame, _ expected: [UInt32], width: Int, columns: Range<Int>? = nil) -> Int? {
    guard got.pixels.count == expected.count else { return -1 }
    let columns = columns ?? 0..<width
    for y in 0..<(expected.count / width) {
        for x in columns where got.pixels[y * width + x] != expected[y * width + x] { return y }
    }
    return nil
}

struct ScrollStitcherTests {
    private let page = SyntheticPage(width: 240, height: 2400, seed: 7)

    @Test func stitchesAPageScrolledDownWithStickyBarsKeptOnce() throws {
        let view = Viewport(page: page, height: 400)
        let stitcher = ScrollStitcher()
        #expect(stitcher.add(view.frame(at: 0)) == .started)
        var scroll = 0
        while scroll < view.end {
            let next = min(view.end, scroll + 37)
            #expect(stitcher.add(view.frame(at: next)) == .placed(offset: next, added: next - scroll))
            scroll = next
        }
        // Blank rows next to a sticky bar may count as part of it; that changes nothing in the picture.
        #expect(stitcher.header >= 40)
        #expect(stitcher.footer >= 30)
        let result = try pixels(of: stitcher.image())
        #expect(result.height == 40 + page.height + 30)
        #expect(firstDifference(result, view.expected(from: 0, to: view.end), width: page.width) == nil)
    }

    @Test func takesImagesPixelForPixel() throws {
        let view = Viewport(page: page, height: 360)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let stitcher = ScrollStitcher()
        for scroll in stride(from: 0, through: 900, by: 120) {
            let frame = view.frame(at: scroll)
            let image = try #require(frame.image(rows: 0..<frame.height, colorSpace: space))
            _ = stitcher.add(image)
        }
        let result = try pixels(of: stitcher.image())
        #expect(firstDifference(result, view.expected(from: 0, to: 840), width: page.width) == nil)
    }

    @Test func pagesWithoutStickyBars() throws {
        var view = Viewport(page: page, height: 300)
        view.headerHeight = 0
        view.footerHeight = 0
        let stitcher = ScrollStitcher()
        for scroll in stride(from: 0, through: 1200, by: 90) { _ = stitcher.add(view.frame(at: scroll)) }
        let result = try pixels(of: stitcher.image())
        #expect(firstDifference(result, view.expected(from: 0, to: 1170), width: page.width) == nil)
    }

    @Test func noMovementChangesNothing() throws {
        let view = Viewport(page: page, height: 400)
        let stitcher = ScrollStitcher()
        _ = stitcher.add(view.frame(at: 0))
        #expect(stitcher.add(view.frame(at: 0)) == .unchanged)
        #expect(stitcher.height == 400)
        #expect(!stitcher.hasMoved)
        // Without a move, the picture is the frame.
        let result = try pixels(of: stitcher.image())
        #expect(result.pixels == view.frame(at: 0).pixels)
        _ = stitcher.add(view.frame(at: 50))
        #expect(stitcher.add(view.frame(at: 50)) == .unchanged)
        #expect(stitcher.height == 450)
    }

    @Test func tinySteps() throws {
        let view = Viewport(page: page, height: 400)
        let stitcher = ScrollStitcher()
        _ = stitcher.add(view.frame(at: 0))
        for scroll in 1...12 { #expect(stitcher.add(view.frame(at: scroll)) == .placed(offset: scroll, added: 1)) }
        let result = try pixels(of: stitcher.image())
        #expect(firstDifference(result, view.expected(from: 0, to: 12), width: page.width) == nil)
    }

    @Test func scrollingBackUpAddsNothingAndCarriesOn() throws {
        let view = Viewport(page: page, height: 400)
        let stitcher = ScrollStitcher()
        for scroll in stride(from: 0, through: 600, by: 60) { _ = stitcher.add(view.frame(at: scroll)) }
        let height = stitcher.height
        for scroll in stride(from: 560, through: 200, by: -45) {
            #expect(stitcher.add(view.frame(at: scroll)) == .placed(offset: scroll, added: 0))
        }
        #expect(stitcher.height == height)
        // Back down past where it was.
        for scroll in stride(from: 250, through: 1000, by: 50) { _ = stitcher.add(view.frame(at: scroll)) }
        let result = try pixels(of: stitcher.image())
        #expect(firstDifference(result, view.expected(from: 0, to: 1000), width: page.width) == nil)
    }

    @Test func startsMidPageAndScrollsUpFirst() throws {
        let view = Viewport(page: page, height: 400)
        let stitcher = ScrollStitcher()
        _ = stitcher.add(view.frame(at: 500))
        #expect(stitcher.add(view.frame(at: 470)) == .placed(offset: -30, added: 0))
        #expect(stitcher.header == 40)
        #expect(stitcher.footer == 30)
        for scroll in stride(from: 520, through: 1100, by: 58) { _ = stitcher.add(view.frame(at: scroll)) }
        let result = try pixels(of: stitcher.image())
        #expect(firstDifference(result, view.expected(from: 500, to: 1100), width: page.width) == nil)
    }

    @Test func refusesAJumpWithNoOverlapAndRecovers() throws {
        let view = Viewport(page: page, height: 400)
        let stitcher = ScrollStitcher()
        for scroll in stride(from: 0, through: 300, by: 100) { _ = stitcher.add(view.frame(at: scroll)) }
        let height = stitcher.height
        // Two screens further down: nothing in common with the picture.
        #expect(stitcher.add(view.frame(at: 300 + 2 * view.band)) == .mismatch)
        #expect(stitcher.height == height)
        // Back within reach, it carries on.
        #expect(stitcher.add(view.frame(at: 500)) == .placed(offset: 500, added: 200))
        for scroll in stride(from: 600, through: 900, by: 100) { _ = stitcher.add(view.frame(at: scroll)) }
        let result = try pixels(of: stitcher.image())
        #expect(firstDifference(result, view.expected(from: 0, to: 900), width: page.width) == nil)
    }

    @Test func refusesAnotherPage() throws {
        let view = Viewport(page: page, height: 400)
        let other = Viewport(page: SyntheticPage(width: 240, height: 2400, seed: 99), height: 400)
        let stitcher = ScrollStitcher()
        _ = stitcher.add(view.frame(at: 0))
        _ = stitcher.add(view.frame(at: 80))
        #expect(stitcher.add(other.frame(at: 400)) == .mismatch)
        // Its own header and footer aren't enough to place it either, before the first move.
        let fresh = ScrollStitcher()
        _ = fresh.add(view.frame(at: 0))
        #expect(fresh.add(other.frame(at: 400)) == .mismatch)
        #expect(!fresh.hasMoved)
    }

    @Test func stopsAtTheLimit() throws {
        let view = Viewport(page: page, height: 400)
        var configuration = ScrollStitcher.Configuration()
        configuration.maxHeight = 1000
        let stitcher = ScrollStitcher(configuration: configuration)
        for scroll in stride(from: 0, through: 1500, by: 100) { _ = stitcher.add(view.frame(at: scroll)) }
        #expect(stitcher.isFull)
        #expect(stitcher.height == 1000)
        let result = try pixels(of: stitcher.image())
        // The header, as much of the page as fits, and the footer.
        let fits = 1000 - 40 - 30
        let expected = view.header + page.rows(0..<fits) + view.footer
        #expect(firstDifference(result, expected, width: page.width) == nil)
    }

    @Test func ignoresTheScrollBarStrip() throws {
        let view = Viewport(page: page, height: 400)
        let stitcher = ScrollStitcher()
        var random = SplitMix(seed: 3)
        for (index, scroll) in stride(from: 0, through: 800, by: 80).enumerated() {
            var pixels = view.frame(at: scroll).pixels
            // An overlay scroll bar that comes and goes in the last 12 columns.
            let thumb = Int.random(in: 0...300, using: &random)
            for y in 0..<400 {
                for x in (page.width - 12)..<page.width {
                    let inThumb = index % 2 == 0 && (thumb..<(thumb + 80)).contains(y)
                    pixels[y * page.width + x] = inThumb ? 0xFF80_8080 : pixels[y * page.width + x]
                }
            }
            #expect(stitcher.add(ScrollFrame(width: page.width, height: 400, pixels: pixels)) != .mismatch)
        }
        let result = try pixels(of: stitcher.image())
        #expect(result.height == 40 + 800 + view.band + 30)
        let expected = view.expected(from: 0, to: 800)
        #expect(firstDifference(result, expected, width: page.width, columns: 0..<(page.width - 12)) == nil)
    }

    @Test func givesBackTheOverscrollBounce() throws {
        let view = Viewport(page: page, height: 400)
        let stitcher = ScrollStitcher()
        for scroll in stride(from: view.end - 400, through: view.end, by: 50) { _ = stitcher.add(view.frame(at: scroll)) }
        _ = stitcher.add(view.frame(at: view.end))
        let settled = stitcher.height
        // Past the end, the page slides up over blank rows, then settles back.
        for bounce in [12, 30, 22, 9, 0] { _ = stitcher.add(view.frame(at: view.end, overscroll: bounce)) }
        #expect(stitcher.height == settled)
        let result = try pixels(of: stitcher.image())
        let expected = view.expected(from: view.end - 400, to: view.end)
        #expect(firstDifference(result, expected, width: page.width) == nil)
    }

    @Test func fallsBackToRegistrationWhenRowsDontMatchExactly() throws {
        let view = Viewport(page: page, height: 400)
        let stitcher = ScrollStitcher()
        var random = SplitMix(seed: 11)
        func noisy(_ frame: ScrollFrame) -> ScrollFrame {
            // Every pixel a little off, differently each frame, as video or dithering would be.
            let pixels = frame.pixels.map { pixel -> UInt32 in
                let blue = Int(pixel & 0xFF) + Int.random(in: -4...4, using: &random)
                let clamped = UInt32(min(255, max(0, blue)))
                return (pixel & 0xFFFF_FF00) | clamped
            }
            return ScrollFrame(width: frame.width, height: frame.height, pixels: pixels)
        }
        _ = stitcher.add(noisy(view.frame(at: 0)))
        var placed: [Int] = []
        for scroll in stride(from: 70, through: 700, by: 70) {
            if case .placed(let offset, _) = stitcher.add(noisy(view.frame(at: scroll))) { placed.append(offset) }
        }
        #expect(placed == Array(stride(from: 70, through: 700, by: 70)))
        #expect(stitcher.height == 40 + 700 + view.band + 30)
        // Row for row where it should be: only the noise differs.
        let result = try pixels(of: stitcher.image())
        let expected = view.expected(from: 0, to: 700)
        let misplaced = zip(result.pixels, expected).contains { got, want in
            got & 0xFFFF_FF00 != want & 0xFFFF_FF00 || abs(Int(got & 0xFF) - Int(want & 0xFF)) > 4
        }
        #expect(!misplaced)
    }

    @Test func registrationWithoutTheFallbackIsRefused() {
        let view = Viewport(page: page, height: 400)
        var configuration = ScrollStitcher.Configuration()
        configuration.usesRegistration = false
        let stitcher = ScrollStitcher(configuration: configuration)
        var frame = view.frame(at: 0)
        _ = stitcher.add(frame)
        frame = view.frame(at: 60)
        let noisy = frame.pixels.enumerated().map { $0.offset % 7 == 0 ? $0.element ^ 0x0000_0003 : $0.element }
        #expect(stitcher.add(ScrollFrame(width: frame.width, height: frame.height, pixels: noisy)) == .mismatch)
    }

    @Test func previewFollowsTheEnd() throws {
        let view = Viewport(page: page, height: 400)
        let stitcher = ScrollStitcher()
        for scroll in stride(from: 0, through: 1200, by: 100) { _ = stitcher.add(view.frame(at: scroll)) }
        let preview = try #require(stitcher.preview(width: 24, height: 60))
        #expect(preview.width == 24)
        #expect(preview.height == 60)
        // Its last rows are the footer's grey.
        let bottom = try pixels(of: preview)
        let pixel = bottom.pixels[(bottom.height - 1) * 24 + 22]
        #expect(pixel & 0xFF > 0xC0)
        // A short picture comes back whole, not stretched.
        let short = ScrollStitcher()
        _ = short.add(view.frame(at: 0))
        let whole = try #require(short.preview(width: 24, height: 400))
        #expect(whole.height == 40)
    }
}

@MainActor
struct ScrollingCaptureGeometryTests {
    @Test func areaInTheDisplaysOwnPointsFromTheTop() {
        // A second display above and to the right of the main one.
        let screen = CGRect(x: 1512, y: 982, width: 1920, height: 1080)
        let area = CGRect(x: 1612, y: 1500, width: 400, height: 300)
        let source = ScrollingCaptureSession.sourceRect(for: area, on: screen)
        #expect(source == CGRect(x: 100, y: 1080 - (1500 + 300 - 982), width: 400, height: 300))
        // The main display.
        let main = CGRect(x: 0, y: 0, width: 1512, height: 982)
        #expect(ScrollingCaptureSession.sourceRect(for: CGRect(x: 10, y: 20, width: 100, height: 50), on: main)
                == CGRect(x: 10, y: 982 - 70, width: 100, height: 50))
    }

    @Test func snapsToWholePixels() {
        let snapped = ScrollingCaptureSession.pixelAligned(CGRect(x: 10.3, y: 20.74, width: 99.9, height: 50.2), scale: 2)
        #expect(snapped == CGRect(x: 10.5, y: 20.5, width: 99.5, height: 50.5))
        #expect(ScrollingCaptureSession.pixelAligned(CGRect(x: 10.4, y: 0, width: 10, height: 10), scale: 1)
                == CGRect(x: 10, y: 0, width: 10, height: 10))
    }
}
