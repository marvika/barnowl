import AppKit
import KeyboardShortcuts
import SwiftUI

/// History's colours and measurements.
enum HistoryStyle {
    /// Behind the grid: the same quiet page Photos and Finder use.
    static let background = NSColor.textBackgroundColor
    static let tileRadius: CGFloat = 10
    /// The thumbnail's box is 16:10; the caption sits under it.
    static let pictureRatio: CGFloat = 1.6
    static let captionHeight: CGFloat = 30
    static let minimumTileWidth: CGFloat = 200
    static let spacing: CGFloat = 18
    static let lineSpacing: CGFloat = 14
    static let sideInset: CGFloat = 22
    static let headerHeight: CGFloat = 44
    static let sectionGap: CGFloat = 16

    static func tileHeight(forWidth width: CGFloat) -> CGFloat {
        (width / pictureRatio).rounded() + captionHeight
    }
}

/// One capture in the grid: its picture on a soft mat, the time, the app, and whether it's
/// been marked up or saved.
struct HistoryTileView: View {
    var item: CaptureHistory.Item?
    var thumbnail: NSImage?
    var selected = false
    /// The grid has the keyboard: the selection is lavender, otherwise grey, as in Finder.
    var focused = true

    private var ring: Color { focused ? Brand.lavender : Color.secondary.opacity(0.6) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            picture
            caption
        }
    }

    private var picture: some View {
        ZStack {
            RoundedRectangle(cornerRadius: HistoryStyle.tileRadius, style: .continuous)
                .fill(selected ? AnyShapeStyle(ring.opacity(focused ? 0.16 : 0.12)) : AnyShapeStyle(.primary.opacity(0.045)))
            if let thumbnail {
                let window = item?.isWindow ?? false
                Image(nsImage: thumbnail)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    // Area and screen captures get a hairline, so a white page doesn't melt into the mat.
                    .clipShape(.rect(cornerRadius: window ? 0 : 3))
                    .overlay {
                        if !window {
                            RoundedRectangle(cornerRadius: 3).strokeBorder(.primary.opacity(0.1), lineWidth: 0.5)
                        }
                    }
                    .overlay(alignment: .bottomTrailing) {
                        if let media = item?.media, media.isMovie { MovieBadge(media: media, compact: true).padding(5) }
                    }
                    .padding(window ? 6 : 12)
                    .transition(.opacity)
            }
        }
        .aspectRatio(HistoryStyle.pictureRatio, contentMode: .fit)
        .overlay {
            RoundedRectangle(cornerRadius: HistoryStyle.tileRadius, style: .continuous)
                .strokeBorder(selected ? ring : Color.primary.opacity(0.06), lineWidth: selected ? 2.5 : 0.5)
        }
        .animation(.easeOut(duration: 0.18), value: thumbnail == nil)
    }

    private var caption: some View {
        HStack(spacing: 5) {
            if let item {
                Text(item.date, format: .dateTime.hour().minute())
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                Text(item.subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(-1)
                Spacer(minLength: 2)
                if item.isEdited { HistoryBadge(symbol: "pencil", label: "Marked up") }
                if item.isSaved { HistoryBadge(symbol: "folder", label: "Saved") }
            }
        }
        .padding(.horizontal, 3)
        .frame(height: HistoryStyle.captionHeight)
    }
}

/// A small sign on a tile: marked up, or saved to a file.
struct HistoryBadge: View {
    let symbol: String
    let label: String

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: 16, height: 16)
            .accessibilityLabel(label)
    }
}

/// A line at the foot of history after Copy or Copy Text, or when something can't be done,
/// gone again in a moment. VoiceOver says it too.
@MainActor
@Observable
final class HistoryNotice {
    enum Tone: Equatable {
        /// Done, with a lavender tick.
        case done
        /// Under way, with a spinner; stays until something replaces it.
        case working
        /// Nothing went wrong, but nothing happened either.
        case info
        /// Something failed, in amber.
        case warning
    }

    struct Note: Equatable {
        let text: String
        let tone: Tone
        var symbol: String?
        /// The same words again still count as new, so they show again.
        let serial: Int
    }

    private(set) var note: Note?
    @ObservationIgnored private var serial = 0
    @ObservationIgnored private var hiding: Task<Void, Never>?

    func show(_ text: String, tone: Tone = .done, symbol: String? = nil) {
        serial += 1
        note = Note(text: text, tone: tone, symbol: symbol, serial: serial)
        hiding?.cancel()
        guard tone != .working else { return }
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                             userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.high.rawValue])
        hiding = Task { [weak self] in
            try? await Task.sleep(for: .seconds(tone == .done ? 1.6 : 2.8))
            guard !Task.isCancelled else { return }
            self?.note = nil
        }
    }

    func hide() {
        hiding?.cancel()
        note = nil
    }
}

/// The notice, in a glass capsule at the bottom centre of the window.
struct HistoryNoticeView: View {
    let notice: HistoryNotice
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The strip it sits in, along the bottom of the window.
    static let height: CGFloat = 72

    var body: some View {
        ZStack {
            if let note = notice.note {
                HStack(spacing: 7) {
                    icon(note)
                    Text(note.text)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                }
                .padding(.leading, 12)
                .padding(.trailing, 15)
                .frame(height: 34)
                .glassEffect(.regular, in: .capsule)
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 8)))
                .id(note.serial)
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, 22)
        .animation(reduceMotion ? nil : .smooth(duration: 0.22), value: notice.note)
    }

    @ViewBuilder
    private func icon(_ note: HistoryNotice.Note) -> some View {
        switch note.tone {
        case .working:
            ProgressView().controlSize(.small).frame(width: 16, height: 16)
        case .done:
            symbol(note.symbol ?? "checkmark.circle.fill", colour: Brand.lavender)
        case .info:
            symbol(note.symbol ?? "info.circle", colour: .secondary)
        case .warning:
            symbol(note.symbol ?? "exclamationmark.triangle.fill", colour: Brand.amber)
        }
    }

    private func symbol(_ name: String, colour: Color) -> some View {
        Image(systemName: name)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(colour)
            .frame(width: 16, height: 16)
            .accessibilityHidden(true)
    }
}

/// Shows the notice over the grid without taking any of its clicks.
final class HistoryNoticeHost: NSHostingView<HistoryNoticeView> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// Above each day: its name and how many captures it has.
struct HistoryDayHeaderView: View {
    var title = ""
    var count = 0

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title).font(.system(size: 15, weight: .bold))
            Text(count == 1 ? "1 capture" : "\(count) captures")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, HistoryStyle.sideInset + 2)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .background(Color(nsColor: HistoryStyle.background))
    }
}

/// What history says when there's nothing to show: none yet, history off, or no match.
struct HistoryEmptyState: View {
    let model: CaptureHistoryModel
    var turnOn: () -> Void = {}

    var body: some View {
        Group {
            switch model.state {
            case .off: off
            case .empty: empty
            case .noResults: noResults
            case .loading, .grid: Color.clear
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: HistoryStyle.background))
    }

    private var empty: some View {
        message(owl: WatchingOwl(snores: false, talks: false),
                title: "No captures yet",
                detail: "Captures you take show up here for \(Self.days(model.keepDays)), ready to copy, drag or mark up again.") {
            // Only while Capture is on: otherwise the shortcut does nothing.
            if model.captureEnabled, let shortcut = KeyboardShortcuts.getShortcut(for: .captureArea) {
                HStack(spacing: 10) {
                    KeyCaps(shortcut.description)
                    Text("Capture an area or a window").font(.callout).foregroundStyle(.secondary)
                }
                .padding(.top, 6)
            }
        }
    }

    private var off: some View {
        message(owl: WatchingOwl(eyesOpen: false, talks: false),
                title: "Barn Owl isn't keeping captures",
                detail: "Keep them to find a capture by the words in it, copy it again, or reopen it with its marks still movable. They stay on your Mac.") {
            Button(action: turnOn) {
                Text("Keep Captures for 30 Days")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 7)
                    .background(Brand.lavenderFill, in: .capsule)
            }
            .buttonStyle(PressableStyle())
            .padding(.top, 6)
        }
    }

    private var noResults: some View {
        message(owl: WatchingOwl(snores: false, talks: false, entrance: .puzzled),
                title: "No results for “\(model.query.trimmingCharacters(in: .whitespaces))”",
                detail: "Search finds the words in a capture, the app it was taken in, or its day, like “Safari” or “Monday”.") {
            EmptyView()
        }
    }

    private func message<Owl: View, Extra: View>(owl: Owl, title: String, detail: String,
                                                  @ViewBuilder extra: () -> Extra) -> some View {
        VStack(spacing: 10) {
            owl.frame(width: 64, height: 64).padding(.bottom, 6)
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .multilineTextAlignment(.center)
            Text(detail)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            extra()
        }
        .frame(maxWidth: 360)
        .padding(32)
        // Sits a little above the middle, where the eye lands.
        .offset(y: -20)
    }

    static func days(_ count: Int) -> String { count == 1 ? "a day" : "\(count) days" }
}

/// A shortcut as keys: ⌃ ⌥ ⌘ 4, each in its own cap.
struct KeyCaps: View {
    let keys: [String]

    init(_ shortcut: String) {
        keys = Self.split(shortcut)
    }

    /// Modifier glyphs one by one, then the key itself: "⌃⌥⌘F5" → ⌃, ⌥, ⌘, F5.
    nonisolated static func split(_ shortcut: String) -> [String] {
        let modifiers: Set<Character> = ["⌃", "⌥", "⇧", "⌘", "🌐"]
        var keys = shortcut.prefix { modifiers.contains($0) }.map(String.init)
        let rest = shortcut.drop { modifiers.contains($0) }
        if !rest.isEmpty { keys.append(String(rest)) }
        return keys
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                Text(key)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .frame(minWidth: 22, minHeight: 22)
                    .padding(.horizontal, key.count > 1 ? 5 : 0)
                    .background {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor))
                            .shadow(color: .black.opacity(0.18), radius: 0, y: 1)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(.primary.opacity(0.14), lineWidth: 0.5)
                    }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(keys.joined(separator: " "))
    }
}
