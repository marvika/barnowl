import AppKit
import Observation

/// What the history window shows: the kept captures, the search, and the days they fall in.
/// Files are read off the main thread; everything here is read on it.
@MainActor
@Observable
final class CaptureHistoryModel {
    enum State: Equatable {
        case loading, off, empty, noResults, grid
    }

    let root: URL
    private(set) var all: [CaptureHistory.Item] = []
    /// The captures that match the search, under their days.
    private(set) var days: [CaptureHistory.Day<CaptureHistory.Item>] = []
    private(set) var isLoaded = false
    var keepDays: Int
    var query = "" {
        didSet { if query != oldValue { regroup() } }
    }

    @ObservationIgnored var now: () -> Date = { Date() }
    @ObservationIgnored var calendar = Calendar.autoupdatingCurrent
    @ObservationIgnored var locale = Locale.autoupdatingCurrent
    /// After the days change, for the grid.
    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored private var byID: [UUID: CaptureHistory.Item] = [:]
    @ObservationIgnored private var loading: Task<Void, Never>?
    @ObservationIgnored private var afterLoading: [() -> Void] = []

    init(root: URL = CaptureLibrary.folder, keepDays: Int = CaptureLibrary.keepDays) {
        self.root = root
        self.keepDays = keepDays
    }

    var state: State {
        if keepDays == 0 { return .off }
        if !isLoaded { return .loading }
        if all.isEmpty { return .empty }
        return days.isEmpty ? .noResults : .grid
    }

    var isSearching: Bool { !CaptureHistory.terms(of: query).isEmpty }

    /// Under the window's title: how many, and for how long.
    var subtitle: String { subtitle(compact: false) }

    /// Just how many, for a narrow window.
    func subtitle(compact: Bool) -> String {
        switch state {
        case .off: return "Not keeping captures"
        case .loading: return ""
        case .empty: return "Kept for \(HistoryEmptyState.days(keepDays))"
        case .noResults, .grid:
            let shown = days.reduce(0) { $0 + $1.items.count }
            if isSearching { return "\(shown) of \(Self.count(all.count))" }
            if compact { return Self.count(all.count) }
            return "\(Self.count(all.count)) · kept for \(HistoryEmptyState.days(keepDays))"
        }
    }

    static func count(_ number: Int) -> String { number == 1 ? "1 capture" : "\(number) captures" }

    func item(_ id: UUID) -> CaptureHistory.Item? { byID[id] }

    /// Reads the library again, then calls `done`.
    func reload(then done: (() -> Void)? = nil) {
        if let done { afterLoading.append(done) }
        loading?.cancel()
        let root = root, now = now(), calendar = calendar, locale = locale
        loading = Task { [weak self] in
            let items = await Task.detached(priority: .userInitiated) {
                CaptureHistory.load(in: root, now: now, calendar: calendar, locale: locale)
            }.value
            guard let self, !Task.isCancelled else { return }
            self.loading = nil
            self.show(items)
            let waiting = self.afterLoading
            self.afterLoading = []
            for done in waiting { done() }
        }
    }

    func show(_ items: [CaptureHistory.Item]) {
        all = items
        byID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        isLoaded = true
        regroup()
    }

    /// Takes captures out at once, before the library has said so.
    func drop(_ ids: Set<UUID>) {
        show(all.filter { !ids.contains($0.id) })
    }

    /// Lets go of what was read, while the window is closed.
    func forget() {
        loading?.cancel()
        loading = nil
        afterLoading = []
        all = []
        byID = [:]
        days = []
        isLoaded = false
    }

    private func regroup() {
        let namer = CaptureHistory.DayNamer(now: now(), calendar: calendar, locale: locale)
        let found = CaptureHistory.filter(all, query: query)
        days = CaptureHistory.days(found, date: \.date, namer: namer)
        onChange?()
    }
}

/// History's small pictures, decoded off the main thread and kept while there's room.
@MainActor
final class HistoryThumbnails {
    let root: URL
    /// Enough for the widest tile on a Retina screen.
    let pixels: Int
    /// A picture arrived, for the tile showing it.
    var onLoad: ((UUID, NSImage) -> Void)?
    private let cache = NSCache<NSUUID, NSImage>()
    private var loading: Set<UUID> = []
    /// Bumped when a capture's picture changes, so a load already under way is ignored.
    private var generation: [UUID: Int] = [:]
    private var stale: Set<UUID> = []

    init(root: URL, pixels: Int = 560) {
        self.root = root
        self.pixels = pixels
        cache.totalCostLimit = 120 << 20
    }

    func image(_ id: UUID) -> NSImage? { cache.object(forKey: id as NSUUID) }

    /// Loads it, unless it's here and current or on its way.
    func want(_ id: UUID) {
        guard image(id) == nil || stale.contains(id), !loading.contains(id) else { return }
        stale.remove(id)
        loading.insert(id)
        let root = root, pixels = pixels, version = generation[id, default: 0]
        Task { [weak self] in
            let picture = await Task.detached(priority: .userInitiated) {
                CaptureLibrary.smallPicture(id, pixels: pixels, in: root)
            }.value
            guard let self, self.generation[id, default: 0] == version else { return }
            self.loading.remove(id)
            guard let picture else { return }
            let image = NSImage(cgImage: picture, size: NSSize(width: picture.width, height: picture.height))
            self.cache.setObject(image, forKey: id as NSUUID, cost: picture.width * picture.height * 4)
            self.onLoad?(id, image)
        }
    }

    /// Its picture changed (marks, Hide): the old one shows until the new one is in.
    func refresh(_ id: UUID) {
        generation[id, default: 0] += 1
        loading.remove(id)
        if image(id) != nil { stale.insert(id) }
    }

    func clear() {
        cache.removeAllObjects()
        for id in loading { generation[id, default: 0] += 1 }
        loading = []
        stale = []
    }
}
