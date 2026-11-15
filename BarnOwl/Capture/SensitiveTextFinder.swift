import CoreGraphics
import Foundation
import Vision

/// What Barn Owl can read in a capture, worked out once, on the device:
/// lines and words of text with their boxes, blocks of text, and the parts
/// worth hiding. Boxes are in image pixels, from the top left, like marks.
struct CaptureText: Sendable, Equatable {
    struct Word: Sendable, Equatable {
        let rect: CGRect
        let text: String
    }

    struct Line: Sendable, Equatable {
        let rect: CGRect
        let text: String
        let words: [Word]
    }

    var lines: [Line] = []
    /// Lines that belong together: same left edge, close above each other.
    var blocks: [CGRect] = []
    var findings: [SensitiveTextFinder.Finding] = []

    static let empty = CaptureText()

    /// The text as you'd read it. `within` keeps only lines mostly inside it; words under
    /// `covered` (redactions) are left out. Both are in the same pixels as the lines.
    func plainText(within area: CGRect? = nil, excluding covered: [CGRect] = []) -> String {
        // Hidden once a redaction covers a fifth of it: a secret is often only part of a word
        // ("password=hunter2"), and a word's middle can fall on the part left showing.
        func hidden(_ rect: CGRect) -> Bool {
            covered.contains { cover in
                let overlap = cover.intersection(rect)
                return !overlap.isNull && overlap.width * overlap.height >= rect.width * rect.height * 0.2
            }
        }
        var kept: [Line] = []
        for line in lines {
            if let area {
                let inside = line.rect.intersection(area)
                guard !inside.isNull, inside.width * inside.height >= line.rect.width * line.rect.height * 0.5 else { continue }
            }
            if covered.isEmpty { kept.append(line); continue }
            if line.words.isEmpty {
                if !hidden(line.rect) { kept.append(line) }
                continue
            }
            let words = line.words.filter { !hidden($0.rect) }
            if words.count == line.words.count {
                kept.append(line)
            } else if !words.isEmpty {
                kept.append(Line(rect: line.rect, text: words.map(\.text).joined(separator: " "), words: words))
            }
        }
        return Self.readingOrder(kept)
    }

    /// Top to bottom. Short cells side by side on the same rows (labels and values, a table)
    /// read across, joined by a tab; columns of longer lines (a sidebar beside a page, an
    /// article in two columns) read one column after the other.
    static func readingOrder(_ lines: [Line]) -> String {
        let rows = rows(of: lines)
        let sideBySide = rows.filter { $0.count > 1 }
        let span = lines.reduce(CGRect.null) { $0.union($1.rect) }.width
        let cells = sideBySide.flatMap { $0 }
        let short = cells.isEmpty || cells.map(\.rect.width).reduce(0, +) / CGFloat(cells.count) < span * 0.4
        if sideBySide.count * 10 >= rows.count * 6 && short {
            return text(of: rows)
        }
        // Columns: lines that overlap left to right belong together.
        var columns: [[Line]] = []
        for line in lines.sorted(by: { $0.rect.minX < $1.rect.minX }) {
            if let index = columns.firstIndex(where: { column in
                column.contains { $0.rect.minX < line.rect.maxX && line.rect.minX < $0.rect.maxX }
            }) {
                columns[index].append(line)
            } else {
                columns.append([line])
            }
        }
        guard columns.count > 1 else { return text(of: rows) }
        return columns.map { text(of: Self.rows(of: $0)) }.joined(separator: "\n\n")
    }

    /// Lines grouped into rows: their middles within half a line of each other.
    private static func rows(of lines: [Line]) -> [[Line]] {
        var rows: [[Line]] = []
        for line in lines.sorted(by: { $0.rect.midY < $1.rect.midY }) {
            if let last = rows.last?.last, abs(last.rect.midY - line.rect.midY) < min(last.rect.height, line.rect.height) / 2 {
                rows[rows.count - 1].append(line)
            } else {
                rows.append([line])
            }
        }
        return rows
    }

    private static func text(of rows: [[Line]]) -> String {
        rows.map { row in row.sorted { $0.rect.minX < $1.rect.minX }.map(\.text).joined(separator: "\t") }
            .joined(separator: "\n")
    }
}

/// Reads text with Vision and decides what's private. Nothing leaves the Mac.
enum SensitiveTextFinder {
    /// How much it matters, which decides what's offered by default and what
    /// may interrupt you.
    enum Tier: Int, Sendable, Comparable {
        case info, personal, secret
        static func < (lhs: Tier, rhs: Tier) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    enum Kind: String, Sendable, CaseIterable {
        case key, password, card, privateKey, credentialLink
        case email, phone, iban, nationalID, homeFolder
        case link, ipAddress

        var tier: Tier {
            switch self {
            case .key, .password, .card, .privateKey, .credentialLink: .secret
            case .email, .phone, .iban, .nationalID, .homeFolder: .personal
            case .link, .ipAddress: .info
            }
        }

        var title: String {
            switch self {
            case .key: "Key or token"
            case .password: "Password"
            case .card: "Card number"
            case .privateKey: "Private key"
            case .credentialLink: "Link with a password"
            case .email: "Email address"
            case .phone: "Phone number"
            case .iban: "Bank account"
            case .nationalID: "ID number"
            case .homeFolder: "Your user name"
            case .link: "Link with a token"
            case .ipAddress: "IP address"
            }
        }

        /// The kind in a sentence: "a key or token", "an ID number", "your user name".
        var phrase: String {
            switch self {
            case .homeFolder: "your user name"
            case .ipAddress: "an IP address"
            case .email: "an email address"
            case .nationalID: "an ID number"
            default: "a " + title.prefix(1).lowercased() + title.dropFirst()
            }
        }

        /// Offered for hiding unless you choose otherwise.
        var isDefault: Bool { tier > .info }
    }

    struct Finding: Sendable, Equatable {
        /// In image pixels, from the top left: the whole height of its line, and room around it.
        let rect: CGRect
        let kind: Kind
        let text: String
    }

    // MARK: Reading

    /// Reads the capture once. Throws rather than report "nothing private"
    /// when Vision fails.
    /// `forReading`: for Copy Text, where words read best corrected; looking for keys and
    /// addresses, which aren't words, never corrects them.
    static func scan(_ image: CGImage, forReading: Bool = false) async throws -> CaptureText {
        var text = CaptureText()
        // A tall scrolling capture is read a strip at a time, so Vision never takes it whole.
        for strip in strips(height: image.height) {
            let part: CGImage
            if strip.rows.count == image.height {
                part = image
            } else {
                let rect = CGRect(x: 0, y: strip.rows.lowerBound, width: image.width, height: strip.rows.count)
                guard let cropped = image.cropping(to: rect) else { continue }
                part = cropped
            }
            let read = try await read(part, forReading: forReading)
            let down = CGFloat(strip.rows.lowerBound)
            // Each line once: from the strip whose own part its middle is in.
            for line in read.lines where strip.keeps.contains(Int(line.rect.midY + down)) {
                let words = line.words.map { CaptureText.Word(rect: $0.rect.offsetBy(dx: 0, dy: down), text: $0.text) }
                text.lines.append(CaptureText.Line(rect: line.rect.offsetBy(dx: 0, dy: down), text: line.text, words: words))
            }
            for finding in read.findings where strip.keeps.contains(Int(finding.rect.midY + down)) {
                let rect = finding.rect.offsetBy(dx: 0, dy: down)
                text.findings.append(Finding(rect: rect, kind: finding.kind, text: finding.text))
            }
        }
        text.blocks = blocks(of: text.lines.map(\.rect))
        return text
    }

    /// Part of a tall picture that's read on its own: `rows`, of which it keeps the lines whose
    /// middles are in `keeps`. Strips overlap, so a line cut by one's edge is whole in the next.
    struct Strip: Equatable, Sendable {
        let rows: Range<Int>
        let keeps: Range<Int>
    }

    /// Strips at most `tallest` pixels high, overlapping by `overlap`; one for a picture that fits.
    static func strips(height: Int, tallest: Int = 4_000, overlap: Int = 300) -> [Strip] {
        guard height > tallest, tallest > overlap else { return [Strip(rows: 0..<max(height, 0), keeps: 0..<max(height, 0))] }
        var strips: [Strip] = []
        var top = 0
        while true {
            let bottom = min(height, top + tallest)
            let last = bottom == height
            let keepsFrom = strips.isEmpty ? 0 : top + overlap / 2
            strips.append(Strip(rows: top..<bottom, keeps: keepsFrom..<(last ? height : bottom - overlap / 2)))
            if last { return strips }
            top = bottom - overlap
        }
    }

    /// Reads one picture (or strip), in its own pixels.
    private static func read(_ image: CGImage, forReading: Bool) async throws -> CaptureText {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = forReading
        request.recognitionLanguages = languages(supported: request.supportedRecognitionLanguages)
        // The default skips text under 1/32 of the image's height: everything
        // on a full-screen Retina capture.
        request.minimumTextHeightFraction = Float(min(1, 7 / Double(max(image.height, 1))))
        let observations = try await request.perform(on: image)
        let size = CGSize(width: image.width, height: image.height)
        var text = CaptureText()
        for observation in observations {
            guard let candidate = observation.topCandidates(1).first else { continue }
            let string = candidate.string
            let lineRect = observation.boundingBox.toImageCoordinates(size, origin: .upperLeft)
            func box(_ range: Range<String.Index>) -> CGRect {
                candidate.boundingBox(for: range)?.boundingBox.toImageCoordinates(size, origin: .upperLeft) ?? lineRect
            }
            let words = string.split(whereSeparator: \.isWhitespace).map { word in
                CaptureText.Word(rect: box(word.startIndex..<word.endIndex), text: String(word))
            }
            text.lines.append(CaptureText.Line(rect: lineRect, text: string, words: words))
            let found = classify(string)
            guard !found.isEmpty else { continue }
            // Where the line's ink is: looked up once, for everything found on it.
            let inked: CGRect = fitted(lineRect, in: image) ?? lineRect
            for (range, kind) in found {
                let reached: CGRect = reaching(box(range), on: inked, in: image)
                let rect: CGRect = padded(reached, line: inked)
                text.findings.append(Finding(rect: rect, kind: kind, text: String(string[range])))
            }
        }
        return text
    }

    /// Your languages first, then English; only ones Vision reads.
    static func languages(supported: [Locale.Language]) -> [Locale.Language] {
        var wanted = Locale.preferredLanguages.map { Locale.Language(identifier: $0) }
        wanted.append(Locale.Language(identifier: "en-US"))
        var result: [Locale.Language] = []
        for language in wanted {
            let match = supported.first { $0 == language }
                ?? supported.first { $0.languageCode == language.languageCode }
            if let match, !result.contains(match) { result.append(match) }
        }
        return result
    }

    /// The box that hides `rect`, part of a line: the line's whole height, and a quarter of it
    /// again on every side. That reaches the accents over capitals and the tails under the
    /// line, and stops short of the lines above and below. `line` is best where the ink is
    /// (see `fitted`): Vision's own box for a line can hug the glyphs or cut into them, by as
    /// much as three pixels on small text, so the room is never less than that.
    static func padded(_ rect: CGRect, line: CGRect) -> CGRect {
        let room: CGFloat = max(3, line.height * 0.25)
        let width: CGFloat = rect.width + 2 * room
        let height: CGFloat = line.height + 2 * room
        return CGRect(x: rect.minX - room, y: line.minY - room, width: width, height: height)
    }

    /// The box that hides `rect`, a word or more of `line`, in `image`: fitted to the ink there,
    /// with room around it. `rect` and `line` are Vision's boxes, as they came.
    static func cover(_ rect: CGRect, line: CGRect, in image: CGImage) -> CGRect {
        let inked: CGRect = fitted(line, in: image) ?? line
        return padded(reaching(rect, on: inked, in: image), line: inked)
    }

    /// `line` with its top and bottom moved to the text's ink, read from the pixels: out past
    /// glyphs the box cuts through, in over empty rows and bits of other lines it takes in.
    /// Vision's boxes change with macOS (on macOS 27 they sit on a coarse grid: a few pixels
    /// inside the glyphs here, into the next line there); the ink doesn't. In whole pixels.
    /// Nil when the pixels don't say where the line is.
    static func fitted(_ line: CGRect, in image: CGImage) -> CGRect? {
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let seed: CGRect = line.integral.intersection(bounds)
        guard !seed.isNull, seed.width >= 3, seed.height >= 2 else { return nil }
        // A little over half the box up and down: further than a box is off, even one that
        // kept only the band of small letters.
        let reach: CGFloat = max(6, (seed.height * 0.6).rounded(.up))
        let window: CGRect = seed.insetBy(dx: 0, dy: -reach).intersection(bounds)
        guard let edges = changes(in: image, window: window) else { return nil }
        let first = Int(seed.minY - window.minY)
        let last = Int(seed.maxY - window.minY) - 1
        // A row has ink when something on it stands out a fifth as sharply as the text does.
        let sharpest: Int = edges[first...last].max() ?? 0
        let limit: Int = max(10, sharpest / 5)
        // From the middle of the box, which is on the text if any of it is: the nearest row
        // with ink, then up and down for as long as there's ink. The first empty row is the
        // gap to the next line, however far into that line the box reached.
        let middle: Int = (first + last) / 2
        var start: Int?
        for offset in 0...(last - first) {
            let above: Int = middle - offset
            let below: Int = middle + offset
            if above >= first, edges[above] > limit { start = above; break }
            if below <= last, edges[below] > limit { start = below; break }
        }
        guard let start else { return nil }
        var top: Int = start
        while top > 0, edges[top - 1] > limit { top -= 1 }
        var bottom: Int = start
        while bottom < edges.count - 1, edges[bottom + 1] > limit { bottom += 1 }
        // Ink as far as was looked (a rule down through the line, a picture behind it, lines
        // with no gap between them): no telling where the text ends, so Vision's edge stands.
        if top == 0, window.minY > bounds.minY { top = first }
        if bottom == edges.count - 1, window.maxY < bounds.maxY { bottom = last }
        // The tails and tops of the lines either side may be in the box too. Half as much ink
        // again is more than that: two lines read as one, perhaps, and no telling which is meant.
        var elsewhere = 0
        for row in first...last where (row < top || row > bottom) && edges[row] > limit { elsewhere += 1 }
        let height: Int = bottom + 1 - top
        guard elsewhere * 2 <= height else { return nil }
        return CGRect(x: line.minX, y: window.minY + CGFloat(top), width: line.width, height: CGFloat(height))
    }

    /// `rect`, part of a line whose ink is `line`, with its ends moved out past any glyph they
    /// cut through. Vision's boxes for words sit on the same coarse grid as its lines, coarser
    /// the bigger the picture: on a whole screen an end can be a few pixels inside the first or
    /// last letter. An end that's between letters stays where it is.
    static func reaching(_ rect: CGRect, on line: CGRect, in image: CGImage) -> CGRect {
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        // Two rows past the ink, so a stroke the whole height of the line still has ends.
        let rows: CGRect = line.integral.insetBy(dx: 0, dy: -2)
        let span = CGRect(x: rect.minX, y: rows.minY, width: rect.width, height: rows.height)
        let seed: CGRect = span.integral.intersection(bounds)
        guard !seed.isNull, seed.width >= 2, seed.height >= 3 else { return rect }
        // As far as a wide letter.
        let reach: CGFloat = max(6, (line.height * 0.6).rounded(.up))
        let window: CGRect = seed.insetBy(dx: -reach, dy: 0).intersection(bounds)
        guard let edges = changes(in: image, window: window, down: true) else { return rect }
        let first = Int(seed.minX - window.minX)
        let last = Int(seed.maxX - window.minX) - 1
        let sharpest: Int = edges[first...last].max() ?? 0
        let limit: Int = max(10, sharpest / 5)
        var left: Int = first
        if edges[left] > limit {
            while left > 0, edges[left - 1] > limit { left -= 1 }
            // Ink as far as was looked (an underline, letters that touch): the end stays.
            if left == 0, window.minX > bounds.minX { left = first }
        }
        var right: Int = last
        if edges[right] > limit {
            while right < edges.count - 1, edges[right + 1] > limit { right += 1 }
            if right == edges.count - 1, window.maxX < bounds.maxX { right = last }
        }
        let minX: CGFloat = left < first ? window.minX + CGFloat(left) : rect.minX
        let maxX: CGFloat = right > last ? window.minX + CGFloat(right + 1) : rect.maxX
        return CGRect(x: minX, y: rect.minY, width: maxX - minX, height: rect.height)
    }

    /// For each row of `window` (whole pixels, inside the image), the sharpest change along it;
    /// with `down`, for each column, the sharpest change down it. Next to nothing on plain
    /// background, high where glyphs cross. Taken two pixels apart, so the soft edge of
    /// smoothed text counts and a slow gradient doesn't.
    private static func changes(in image: CGImage, window: CGRect, down: Bool = false) -> [Int]? {
        let width = Int(window.width)
        let height = Int(window.height)
        let bytes: [UInt8] = ImageSampler.rgba(in: image, rect: window)
        guard width >= 1, height >= 1, bytes.count == width * height * 4 else { return nil }
        guard (down ? height : width) >= 3 else { return nil }
        var edges = [Int](repeating: 0, count: down ? width : height)
        let back: Int = down ? 2 * width * 4 : 8
        for y in (down ? 2 : 0)..<height {
            for x in (down ? 0 : 2)..<width {
                let here: Int = (y * width + x) * 4
                let there: Int = here - back
                let red: Int = abs(Int(bytes[here]) - Int(bytes[there]))
                let green: Int = abs(Int(bytes[here + 1]) - Int(bytes[there + 1]))
                let blue: Int = abs(Int(bytes[here + 2]) - Int(bytes[there + 2]))
                let index: Int = down ? x : y
                edges[index] = max(edges[index], red, green, blue)
            }
        }
        return edges
    }

    /// Groups lines into blocks: same left edge (within half a line), and
    /// each starting less than 0.8 of a line below the last.
    static func blocks(of lines: [CGRect]) -> [CGRect] {
        var blocks: [CGRect] = []
        var last: [CGRect] = []
        for line in lines.sorted(by: { $0.minY < $1.minY }) {
            if let index = blocks.indices.first(where: { index in
                let previous = last[index]
                return abs(previous.minX - line.minX) < previous.height * 0.5
                    && line.minY - previous.maxY < previous.height * 0.8
                    && line.minY >= previous.minY
            }) {
                blocks[index] = blocks[index].union(line)
                last[index] = line
            } else {
                blocks.append(line)
                last.append(line)
            }
        }
        return blocks
    }

    // MARK: Classifying text

    /// The parts of a line worth hiding. Pure, so it can be tested without images.
    static func classify(_ text: String) -> [(Range<String.Index>, Kind)] {
        var found: [(range: Range<String.Index>, kind: Kind)] = []
        func add(_ range: Range<String.Index>, _ kind: Kind) {
            guard !range.isEmpty else { return }
            // Overlaps merge, keeping the more sensitive kind.
            if let index = found.firstIndex(where: { $0.range.overlaps(range) }) {
                let existing = found[index]
                let merged = min(existing.range.lowerBound, range.lowerBound)..<max(existing.range.upperBound, range.upperBound)
                found[index] = (merged, existing.kind.tier >= kind.tier ? existing.kind : kind)
            } else {
                found.append((range, kind))
            }
        }
        for rule in rules {
            for range in rule.matches(text) { add(range, rule.kind) }
        }
        for range in cards(in: text) { add(range, .card) }
        for range in phones(in: text) where !found.contains(where: { $0.range.overlaps(range) }) {
            add(range, .phone)
        }
        return found.sorted { $0.range.lowerBound < $1.range.lowerBound }.map { ($0.range, $0.kind) }
    }

    private struct Rule {
        let pattern: NSRegularExpression
        let kind: Kind
        /// Which capture group is the private part (0 is the whole match).
        var group = 0
        /// Gets the match and up to a dozen characters before it.
        var accept: (String, Substring) -> Bool = { _, _ in true }

        init(_ pattern: String, _ kind: Kind, group: Int = 0, accept: @escaping (String) -> Bool = { _ in true }) {
            self.init(pattern, kind, group: group) { match, _ in accept(match) }
        }

        init(_ pattern: String, _ kind: Kind, group: Int = 0, context: @escaping (String, Substring) -> Bool) {
            // The patterns are fixed and tested; a typo should fail loudly.
            self.pattern = try! NSRegularExpression(pattern: pattern, options: [])
            self.kind = kind
            self.group = group
            self.accept = context
        }

        func matches(_ text: String) -> [Range<String.Index>] {
            pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
                guard let range = Range(match.range(at: group), in: text) else { return nil }
                let before = text[..<range.lowerBound].suffix(12)
                return accept(String(text[range]), before) ? range : nil
            }
        }
    }

    // Order matters only for readability: overlaps keep the most sensitive kind.
    nonisolated(unsafe) private static let rules: [Rule] = [
        Rule(#"-----BEGIN [A-Z ]*PRIVATE KEY-----"#, .privateKey),
        Rule(#"\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}"#, .key),
        Rule(#"\bsk-(?:proj-|ant-)?[A-Za-z0-9_-]{20,}"#, .key, accept: { looksRandom($0, minimum: 3.0) }),
        Rule(#"\bgh[pousr][_ ][A-Za-z0-9]{30,}"#, .key),
        Rule(#"\bgithub_pat_[A-Za-z0-9_]{20,}"#, .key),
        Rule(#"\b(?:AKIA|ASIA)[0-9A-Z]{16}\b"#, .key),
        Rule(#"\bxox[abprs]-[A-Za-z0-9-]{10,}"#, .key),
        Rule(#"hooks\.slack\.com/services/[A-Za-z0-9/]+"#, .key),
        Rule(#"\bAIza[0-9A-Za-z_-]{30,}"#, .key),
        Rule(#"\b(?:sk|pk|rk)_(?:live|test)_[A-Za-z0-9]{16,}"#, .key),
        // "PASSWORD=…", "api_key: …", "aws_secret_access_key = …": only the value, named by its label.
        Rule(#"(?i)\b[\w.-]*pass(?:word|wd)?\b["']?\s*[:=]\s*["']?([^\s"',;]{6,})"#, .password, group: 1),
        Rule(#"(?i)\b[\w.-]*(?:secret|token|api[_-]?key|access[_-]?key|client[_-]?secret)\b["']?\s*[:=]\s*["']?([^\s"',;]{6,})"#,
             .key, group: 1),
        Rule(#"(?i)\bbearer\s+([A-Za-z0-9._~+/=-]{12,})"#, .key, group: 1),
        // user:password@ in a link: everything up to the @.
        Rule(#"\b[a-z][a-z0-9+.-]*://([^\s/:@]+:[^\s/@]+)@"#, .credentialLink, group: 1),
        // Long, random-looking strings with mixed characters: tokens nobody named.
        Rule(#"(?<![A-Za-z0-9])[A-Za-z0-9_+/=-]{32,}(?![A-Za-z0-9])"#, .key, accept: { looksRandom($0, minimum: 3.5) && classes($0) >= 3 }),
        Rule(#"[A-Za-z0-9._%+-]+ ?@ ?[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}\b"#, .email, accept: isEmail),
        Rule(#"\b[A-Z]{2}\d{2}(?: ?[A-Z0-9]{4}){2,7}(?: ?[A-Z0-9]{1,4})?\b"#, .iban, accept: isIBAN),
        Rule(#"\b\d{6} ?\d{5}\b"#, .nationalID, accept: isNorwegianID),
        Rule(#"\b\d{3}-\d{2}-\d{4}\b"#, .nationalID),
        Rule(#"/Users/([^/\s]+)"#, .homeFolder, group: 1, accept: { $0 != "Shared" }),
        Rule(#"[?&](?:token|access_token|api_key|key|sig|signature|auth|code|session|password|secret)=[^\s&]{6,}"#, .link),
        Rule(#"(?<![\d.])(?:\d{1,3}\.){3}\d{1,3}(?![\d.])"#, .ipAddress) { match, before in
            // "Version 1.2.3.4", "v10.0.0.1", "build 2.3.4.5" are versions.
            let word = before.lowercased().trimmingCharacters(in: .whitespaces)
            let isVersion = word.hasSuffix("version") || word.hasSuffix("build") || word.hasSuffix("v")
            return !isVersion && isPublicIP(match)
        },
    ]

    // MARK: Checks

    static func isEmail(_ text: String) -> Bool {
        let compact = text.replacingOccurrences(of: " ", with: "")
        guard let at = compact.firstIndex(of: "@") else { return false }
        let local = compact[..<at], domain = compact[compact.index(after: at)...]
        // AppIcon@2x.png, git@github.com
        if domain.first?.isNumber == true, domain.dropFirst().hasPrefix("x") { return false }
        if local == "git" { return false }
        let fileEndings: Set<String> = ["png", "jpg", "jpeg", "gif", "svg", "webp", "pdf", "heic", "mov", "mp4", "swift", "json"]
        return !fileEndings.contains(String(domain.split(separator: ".").last ?? "").lowercased())
    }

    static func isPublicIP(_ text: String) -> Bool {
        let parts = text.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4, parts.allSatisfy({ (0...255).contains($0) }) else { return false }
        switch (parts[0], parts[1]) {
        case (10, _), (127, _), (0, _), (169, 254), (192, 168): return false
        case (172, 16...31): return false
        default: return true
        }
    }

    /// Card numbers: a known issuer, the right length, and the Luhn check. A
    /// run of digit groups (a card followed by its CVC) is tried group by group.
    static func cards(in text: String) -> [Range<String.Index>] {
        let run = try! NSRegularExpression(pattern: #"(?<!\d)\d(?:[ -]?\d){11,26}(?!\d)"#)
        var result: [Range<String.Index>] = []
        for match in run.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let range = Range(match.range, in: text) else { continue }
            // Where a group ends: before each separator, and the end.
            var ends = text[range].indices.filter { index in
                text[range][index] == " " || text[range][index] == "-"
            }
            ends.append(range.upperBound)
            for end in ends.reversed() {
                let candidate = String(text[range.lowerBound..<end])
                if isCard(candidate) { result.append(range.lowerBound..<end); break }
            }
        }
        return result
    }

    static func isCard(_ text: String) -> Bool {
        let digits = text.compactMap(\.wholeNumberValue)
        guard let first = digits.first, Set(digits).count > 1 else { return false }
        let prefix2 = digits.prefix(2).reduce(0) { $0 * 10 + $1 }
        let prefix4 = digits.prefix(4).reduce(0) { $0 * 10 + $1 }
        let issuer: Bool
        switch (first, digits.count) {
        case (4, 13), (4, 16), (4, 19): issuer = true                                   // Visa
        case (5, 16): issuer = (51...55).contains(prefix2)                              // Mastercard
        case (2, 16): issuer = (2221...2720).contains(prefix4)
        case (3, 15): issuer = prefix2 == 34 || prefix2 == 37                           // Amex
        case (6, 16...19): issuer = prefix4 == 6011 || prefix2 == 65                    // Discover
        default: issuer = false
        }
        return issuer && luhn(digits)
    }

    static func luhn(_ digits: [Int]) -> Bool {
        var sum = 0
        for (index, digit) in digits.reversed().enumerated() {
            if index % 2 == 1 {
                let doubled = digit * 2
                sum += doubled > 9 ? doubled - 9 : doubled
            } else {
                sum += digit
            }
        }
        return sum % 10 == 0
    }

    static func isIBAN(_ text: String) -> Bool {
        let compact = text.replacingOccurrences(of: " ", with: "")
        guard (15...34).contains(compact.count) else { return false }
        let rearranged = compact.dropFirst(4) + compact.prefix(4)
        var remainder = 0
        for character in rearranged {
            guard let value = character.isNumber ? character.wholeNumberValue
                    : character.isLetter ? Int(character.asciiValue ?? 0) - 55 : nil else { return false }
            for digit in String(value) {
                remainder = (remainder * 10 + (digit.wholeNumberValue ?? 0)) % 97
            }
        }
        return remainder == 1
    }

    /// A Norwegian fødselsnummer: a valid date and both mod-11 control digits.
    static func isNorwegianID(_ text: String) -> Bool {
        let d = text.compactMap(\.wholeNumberValue)
        guard d.count == 11, (1...71).contains(d[0] * 10 + d[1]), (1...12).contains((d[2] * 10 + d[3]) % 40) else {
            return false
        }
        func control(_ weights: [Int], _ count: Int) -> Int? {
            let sum = zip(d.prefix(count), weights).reduce(0) { $0 + $1.0 * $1.1 }
            let value = 11 - sum % 11
            return value == 11 ? 0 : value == 10 ? nil : value
        }
        guard let k1 = control([3, 7, 6, 1, 8, 9, 4, 5, 2], 9), k1 == d[9],
              let k2 = control([5, 4, 3, 2, 7, 6, 5, 4, 3, 2], 10), k2 == d[10] else { return false }
        return true
    }

    /// Phone numbers from the system's data detector, without long unbroken
    /// digit runs (timestamps, IDs) or dates and times.
    static func phones(in text: String) -> [Range<String.Index>] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.phoneNumber.rawValue) else { return [] }
        return detector.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { result in
            guard let range = Range(result.range, in: text) else { return nil }
            let number = text[range]
            let digits = number.filter(\.isNumber).count
            let unbroken = !number.contains { $0 == " " || $0 == "-" || $0 == "(" || $0 == "+" }
            // No phone number has more than 15 digits (E.164), or only one digit repeated.
            if digits < 7 || digits > 15 || (unbroken && digits >= 11) { return nil }
            if Set(number.filter(\.isNumber)).count == 1 { return nil }
            if number.contains(":") || number.contains(".") { return nil }
            return range
        }
    }

    /// Shannon entropy in bits per character.
    static func entropy(_ text: String) -> Double {
        let counts = Dictionary(grouping: text, by: { $0 }).mapValues(\.count)
        let total = Double(text.count)
        return counts.values.reduce(0) { sum, count in
            let p = Double(count) / total
            return sum - p * log2(p)
        }
    }

    static func classes(_ text: String) -> Int {
        [text.contains(where: \.isLowercase), text.contains(where: \.isUppercase), text.contains(where: \.isNumber)]
            .filter { $0 }.count
    }

    /// Mixed characters with enough randomness, unlike words-with-hyphens.
    static func looksRandom(_ text: String, minimum: Double) -> Bool {
        text.contains(where: \.isNumber) && entropy(text) >= minimum
    }
}
