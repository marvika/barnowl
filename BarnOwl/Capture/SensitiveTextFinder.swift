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
        /// In image pixels, from the top left, padded to cover the whole line height.
        let rect: CGRect
        let kind: Kind
        let text: String
    }

    // MARK: Reading

    /// Reads the capture once. Throws rather than report "nothing private"
    /// when Vision fails.
    static func scan(_ image: CGImage) async throws -> CaptureText {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        // Keys and addresses aren't words: don't "correct" them.
        request.usesLanguageCorrection = false
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
            for (range, kind) in classify(string) {
                text.findings.append(Finding(rect: padded(box(range), line: lineRect), kind: kind,
                                             text: String(string[range])))
            }
        }
        text.blocks = blocks(of: text.lines.map(\.rect))
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

    /// A box covering the whole height of its line, with a little room either
    /// side: Vision's boxes for part of a line can leave descenders showing.
    static func padded(_ rect: CGRect, line: CGRect) -> CGRect {
        let height = line.height
        return CGRect(x: rect.minX - height * 0.25, y: line.minY - height * 0.1,
                      width: rect.width + height * 0.5, height: height * 1.2)
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
