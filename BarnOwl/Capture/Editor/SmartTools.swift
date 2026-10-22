import CoreGraphics
import Foundation

/// Hide Private Info's review: what was found, and which of it you're about to hide.
struct PrivateInfoReview: Equatable, Sendable {
    struct Item: Identifiable, Equatable, Sendable {
        let id: Int
        let finding: SensitiveTextFinder.Finding
        var included: Bool
    }

    var items: [Item]

    var includedCount: Int { items.filter(\.included).count }

    /// The kinds found, most sensitive first, with how many of each and how many are included.
    var categories: [(kind: SensitiveTextFinder.Kind, count: Int, included: Int)] {
        let kinds = SensitiveTextFinder.Kind.allCases.filter { kind in items.contains { $0.finding.kind == kind } }
        let sorted = kinds.sorted { $0.tier > $1.tier }
        return sorted.map { kind in
            let matching = items.filter { $0.finding.kind == kind }
            return (kind, matching.count, matching.filter(\.included).count)
        }
    }

    mutating func toggle(_ id: Int) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].included.toggle()
    }

    /// All of a kind on, or (when they're all on already) all off.
    mutating func toggle(kind: SensitiveTextFinder.Kind) {
        let matching = items.indices.filter { items[$0].finding.kind == kind }
        let allOn = matching.allSatisfy { items[$0].included }
        for index in matching { items[index].included = !allOn }
    }
}

/// Where a smart tool would put a mark, from what the capture's text and windows are.
/// Everything is in image pixels, from the top left.
enum SmartFit {
    /// A click (no drag) with Rectangle, Ellipse or Spotlight: the text block under the point,
    /// or failing that the window, with `padding` around it. The smallest that contains the
    /// point wins, so a click in a paragraph inside a window takes the paragraph.
    static func box(at point: CGPoint, insight: CaptureInsight, padding: CGFloat, within bounds: CGRect) -> CGRect? {
        let blocks = insight.text.blocks.filter { $0.insetBy(dx: -padding, dy: -padding).contains(point) }
        if let block = smallest(blocks) {
            return block.insetBy(dx: -padding, dy: -padding).intersection(bounds)
        }
        let windows = insight.windowRects.filter { $0.contains(point) }
        guard let window = smallest(windows) else { return nil }
        return window.insetBy(dx: -padding, dy: -padding).intersection(bounds)
    }

    /// A Highlighter click: the line under the point, a touch taller than its glyphs.
    static func line(at point: CGPoint, insight: CaptureInsight) -> CGRect? {
        let lines = insight.text.lines.filter { padded($0.rect).contains(point) }
        guard let line = lines.min(by: { $0.rect.height < $1.rect.height }) else { return nil }
        return padded(line.rect)
    }

    /// A Redact click: the private finding under the point, whole, or else the word.
    static func redaction(at point: CGPoint, insight: CaptureInsight) -> (rect: CGRect, finding: SensitiveTextFinder.Finding?)? {
        if let finding = insight.text.findings.first(where: { $0.rect.contains(point) }) {
            return (finding.rect, finding)
        }
        for line in insight.text.lines where padded(line.rect).contains(point) {
            if let word = line.words.first(where: { padded($0.rect, line: line.rect).contains(point) }) {
                return (SensitiveTextFinder.padded(word.rect, line: line.rect), nil)
            }
        }
        return nil
    }

    /// A Highlighter drag from `start` to `end`, word by word in reading order: one rectangle
    /// per line. Nil when the drag didn't start on text.
    static func highlights(from start: CGPoint, to end: CGPoint, insight: CaptureInsight) -> [CGRect]? {
        let lines = insight.text.lines.sorted { ($0.rect.minY, $0.rect.minX) < ($1.rect.minY, $1.rect.minX) }
        var words: [(line: Int, rect: CGRect)] = []
        for (index, line) in lines.enumerated() {
            for word in line.words { words.append((index, word.rect)) }
        }
        guard let first = wordIndex(at: start, words: words, lines: lines, strict: true),
              let last = wordIndex(at: end, words: words, lines: lines, strict: false) else { return nil }
        let range = min(first, last)...max(first, last)
        var byLine: [Int: CGRect] = [:]
        for index in range {
            let entry = words[index]
            byLine[entry.line] = (byLine[entry.line] ?? .null).union(entry.rect)
        }
        return byLine.keys.sorted().compactMap { index in
            byLine[index].map { rect in padded(rect, line: lines[index].rect) }
        }
    }

    /// The word at `point`; when not `strict`, the nearest word on the nearest line.
    private static func wordIndex(at point: CGPoint, words: [(line: Int, rect: CGRect)], lines: [CaptureText.Line],
                                  strict: Bool) -> Int? {
        if let hit = words.firstIndex(where: { padded($0.rect, line: lines[$0.line].rect).contains(point) }) { return hit }
        if strict {
            guard let line = lines.firstIndex(where: { padded($0.rect).contains(point) }) else { return nil }
            return nearest(point, in: words.indices.filter { words[$0].line == line }, words: words)
        }
        guard !words.isEmpty else { return nil }
        let lineDistances = lines.indices.map { abs(lines[$0].rect.midY - point.y) }
        guard let closest = lineDistances.indices.min(by: { lineDistances[$0] < lineDistances[$1] }) else { return nil }
        return nearest(point, in: words.indices.filter { words[$0].line == closest }, words: words)
    }

    private static func nearest(_ point: CGPoint, in indices: [Int], words: [(line: Int, rect: CGRect)]) -> Int? {
        indices.min { abs(words[$0].rect.midX - point.x) < abs(words[$1].rect.midX - point.x) }
    }

    /// A line's box, with room above and below for ascenders and descenders.
    static func padded(_ rect: CGRect) -> CGRect {
        rect.insetBy(dx: -rect.height * 0.12, dy: -rect.height * 0.12)
    }

    /// A word's box at its line's full height.
    static func padded(_ rect: CGRect, line: CGRect) -> CGRect {
        let grow: CGFloat = line.height * 0.12
        let width: CGFloat = rect.width + 2 * grow
        let height: CGFloat = line.height + 2 * grow
        return CGRect(x: rect.minX - grow, y: line.minY - grow, width: width, height: height)
    }

    private static func smallest(_ rects: [CGRect]) -> CGRect? {
        rects.min { $0.width * $0.height < $1.width * $1.height }
    }
}

extension EditorModel {
    /// What looks private and isn't hidden yet, inside the crop.
    func uncoveredFindings(minimum tier: SensitiveTextFinder.Tier) -> [SensitiveTextFinder.Finding] {
        guard let insight else { return [] }
        let redactions = document.marks.filter { $0.kind == .redact }.map(\.rect)
        return insight.text.findings.filter { finding in
            guard finding.kind.tier >= tier, finding.rect.intersects(document.crop) else { return false }
            return !redactions.contains { covers($0, finding.rect) }
        }
    }

    /// Keys, tokens, passwords and card numbers in view that aren't hidden yet.
    var visibleSecrets: [SensitiveTextFinder.Finding] { uncoveredFindings(minimum: .secret) }

    /// Secrets and personal things (emails, phones…) in view that aren't hidden yet: what's
    /// hidden unless you say otherwise.
    var visiblePrivate: [SensitiveTextFinder.Finding] { uncoveredFindings(minimum: .personal) }

    /// The count on the Redact tool.
    var privateCount: Int { visiblePrivate.count }

    /// "A key or token and an email address are visible.": secrets named first.
    var privateSentence: String {
        let findings = visiblePrivate
        let ordered = findings.filter { $0.kind.tier == .secret } + findings.filter { $0.kind.tier != .secret }
        return "\(CaptureCoordinator.describe(ordered)) \(findings.count == 1 ? "is" : "are") visible."
    }

    /// The banner's button: Hide, Hide Both or Hide All.
    var hidePrivateTitle: String {
        switch privateCount {
        case 1: "Hide"
        case 2: "Hide Both"
        default: "Hide All"
        }
    }

    /// Whether to show the banner: only a secret interrupts, though Hide covers everything private.
    var showsSecretBanner: Bool { !secretBannerDismissed && !visibleSecrets.isEmpty && review == nil }

    /// Whether Done should ask about a key first: there is one, and you haven't dealt with it.
    var asksAboutSecretsOnDone: Bool { !secretBannerDismissed && !visibleSecrets.isEmpty }

    private func covers(_ cover: CGRect, _ rect: CGRect) -> Bool {
        let overlap = cover.intersection(rect)
        guard !overlap.isNull, rect.width > 0, rect.height > 0 else { return false }
        return overlap.width * overlap.height >= rect.width * rect.height * 0.8
    }

    /// ⇧B: everything private that isn't hidden, ready to hide, with personal and secret
    /// things included and the rest offered.
    func beginReview() {
        endTextEditing?()
        let findings = uncoveredFindings(minimum: .info)
        let items = findings.enumerated().map { index, finding in
            PrivateInfoReview.Item(id: index, finding: finding, included: finding.kind.isDefault)
        }
        if tool != .redact { choose(.redact) }
        selection = []
        review = PrivateInfoReview(items: items)
    }

    /// Hides what the review includes, as one undo step.
    func applyReview() {
        guard let review else { return }
        hide(review.items.filter(\.included).map(\.finding), name: "Hide Private Info")
        self.review = nil
    }

    /// The banner's Hide: every visible secret and personal detail, at once.
    func hidePrivate() {
        // The bars quiet the banner and Done; undo them and both speak up again.
        hide(visiblePrivate, name: "Hide Private Info")
    }

    /// A solid redaction's colour over `rect`: the one you chose, or else the text's own colour,
    /// so the bar reads as hidden text (grey on dark areas, where ink would vanish). `quick`
    /// only looks at how light the area is, for while a bar is being dragged out.
    func redactionColour(over rect: CGRect, quick: Bool = false) -> MarkColour {
        if styleBook.redactColourChosen { return styleBook.redactColour }
        guard quick else { return ImageSampler.redactionColour(in: image, rect: rect) }
        return ImageSampler.plainRedaction(onLightness: renderer.luminance?.mean(in: rect) ?? 1)
    }

    /// Solid bars in the colour of the text under them, so they read as hidden text.
    func hide(_ findings: [SensitiveTextFinder.Finding], name: String) {
        let marks: [Mark] = findings.map { finding in
            var mark = newMark(.redact, at: finding.rect.origin)
            mark.end = CGPoint(x: finding.rect.maxX, y: finding.rect.maxY)
            mark.style.redact = .solid
            mark.colour = redactionColour(over: finding.rect)
            mark.origin = MarkOrigin(source: .privateInfo, category: finding.kind.rawValue)
            return mark
        }
        add(marks, name: name)
    }

    /// Where a click (no drag) with the current tool would put a mark, if smart fitting applies.
    func fitTarget(at point: CGPoint) -> CGRect? {
        guard let insight else { return nil }
        switch tool {
        case .rectangle, .ellipse, .spotlight:
            return SmartFit.box(at: point, insight: insight, padding: 6 * scale, within: document.imageBounds)
        case .highlighter:
            return SmartFit.line(at: point, insight: insight)
        case .redact:
            return SmartFit.redaction(at: point, insight: insight)?.rect
        default:
            return nil
        }
    }

    /// A click with a shape, highlighter or redaction tool: a mark fitted to what's under it.
    @discardableResult
    func placeFitted(at point: CGPoint) -> Mark? {
        guard let kind = tool.markKind, let rect = fitTarget(at: point) else { return nil }
        var mark = newMark(kind, at: rect.origin)
        mark.end = CGPoint(x: rect.maxX, y: rect.maxY)
        mark.origin = MarkOrigin(source: .fit, category: nil)
        if kind == .redact, mark.style.redact == .solid, let insight,
           let hit = SmartFit.redaction(at: point, insight: insight) {
            mark.colour = redactionColour(over: hit.rect)
            if let finding = hit.finding { mark.origin = MarkOrigin(source: .privateInfo, category: finding.kind.rawValue) }
        }
        add(mark)
        return mark
    }

    /// Text under a mark: its own words, or what the capture says beneath it.
    func text(under mark: Mark) -> String? {
        if mark.kind == .text, !mark.text.isEmpty { return mark.text }
        guard let insight else { return nil }
        let rect = MarkGeometry.bounds(mark, scale: scale)
        let lines = insight.text.lines.filter { rect.intersects($0.rect) }
        guard !lines.isEmpty else { return nil }
        return lines.map(\.text).joined(separator: "\n")
    }
}
