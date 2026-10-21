import CoreGraphics
import Foundation
import Vision

/// Reads the text in a capture on the device, to find what's worth hiding
/// (emails, phone numbers, keys and tokens, card numbers) and where the
/// lines of text are, so a highlighter can snap to them. Nothing leaves the Mac.
enum SensitiveTextFinder {
    enum Kind: String, Sendable, CaseIterable {
        case email, phone, link, key, card, ipAddress

        var title: String {
            switch self {
            case .email: "Email address"
            case .phone: "Phone number"
            case .link: "Link"
            case .key: "Key or token"
            case .card: "Card number"
            case .ipAddress: "IP address"
            }
        }
    }

    struct Finding: Sendable, Equatable {
        /// In image pixels, from the top left.
        let rect: CGRect
        let kind: Kind
        let text: String
    }

    /// One recognised line of text and its box (image pixels, from the top left).
    struct Line: Sendable, Equatable {
        let rect: CGRect
        let text: String
    }

    /// Every line of text Vision can read.
    static func lines(in image: CGImage) async -> [Line] {
        await recognise(image).map { Line(rect: $0.rect, text: $0.text) }
    }

    /// What's worth hiding, each with its own box. Links count only when they
    /// carry something private (a token or key in the address).
    static func find(in image: CGImage) async -> [Finding] {
        var findings: [Finding] = []
        for line in await recognise(image) {
            for (range, kind) in classify(line.text) {
                let rect = line.box(range) ?? line.rect
                findings.append(Finding(rect: rect, kind: kind, text: String(line.text[range])))
            }
        }
        return findings
    }

    // MARK: Classifying text

    /// The parts of a line worth hiding. Pure, so it can be tested without images.
    static func classify(_ text: String) -> [(Range<String.Index>, Kind)] {
        var found: [(Range<String.Index>, Kind)] = []
        func add(_ range: Range<String.Index>, _ kind: Kind) {
            // The first (most specific) match wins where they overlap.
            guard !found.contains(where: { $0.0.overlaps(range) }) else { return }
            found.append((range, kind))
        }
        for (pattern, kind) in patterns {
            for match in text.ranges(of: pattern) where kind != .card || luhn(String(text[match])) {
                add(match, kind)
            }
        }
        let whole = NSRange(text.startIndex..., in: text)
        let types: NSTextCheckingResult.CheckingType = [.link, .phoneNumber]
        if let detector = try? NSDataDetector(types: types.rawValue) {
            for result in detector.matches(in: text, range: whole) {
                guard let range = Range(result.range, in: text) else { continue }
                if result.resultType == .phoneNumber {
                    // Short numbers are usually versions, times or counts.
                    if text[range].filter(\.isNumber).count >= 7 { add(range, .phone) }
                } else if let url = result.url {
                    if url.scheme == "mailto" {
                        add(range, .email)
                    } else if url.query?.isEmpty == false || url.user != nil {
                        add(range, .link)
                    }
                }
            }
        }
        return found.sorted { $0.0.lowerBound < $1.0.lowerBound }
    }

    /// Keys and tokens first: they're the most specific.
    nonisolated(unsafe) private static let patterns: [(Regex<Substring>, Kind)] = [
        (/eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}/, .key),            // JWT
        (/sk-(?:proj-|ant-)?[A-Za-z0-9_-]{16,}/, .key),                                   // OpenAI, Anthropic
        (/gh[pousr]_[A-Za-z0-9]{20,}/, .key),                                             // GitHub
        (/github_pat_[A-Za-z0-9_]{20,}/, .key),
        (/AKIA[0-9A-Z]{16}/, .key),                                                       // AWS
        (/xox[abprs]-[A-Za-z0-9-]{10,}/, .key),                                           // Slack
        (/AIza[0-9A-Za-z_-]{30,}/, .key),                                                 // Google
        (/(?:sk|pk|rk)_(?:live|test)_[A-Za-z0-9]{16,}/, .key),                            // Stripe
        (/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/, .email),
        (/\b(?:\d[ -]?){12,18}\d\b/, .card),
        (/\b(?:25[0-5]|2[0-4]\d|1?\d?\d)(?:\.(?:25[0-5]|2[0-4]\d|1?\d?\d)){3}\b/, .ipAddress),
    ]

    /// Card numbers pass the Luhn check; other long numbers usually don't.
    static func luhn(_ text: String) -> Bool {
        let digits = text.compactMap(\.wholeNumberValue)
        guard (13...19).contains(digits.count) else { return false }
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

    // MARK: Vision

    private struct Recognised {
        let text: String
        let rect: CGRect
        let box: (Range<String.Index>) -> CGRect?
    }

    private static func recognise(_ image: CGImage) async -> [Recognised] {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        // Keys and addresses aren't words: don't "correct" them.
        request.usesLanguageCorrection = false
        request.automaticallyDetectsLanguage = true
        guard let observations = try? await request.perform(on: image) else { return [] }
        let size = CGSize(width: image.width, height: image.height)
        return observations.compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let rect = observation.boundingBox.toImageCoordinates(size, origin: .upperLeft)
            return Recognised(text: candidate.string, rect: rect) { range in
                candidate.boundingBox(for: range)?.boundingBox.toImageCoordinates(size, origin: .upperLeft)
            }
        }
    }
}
