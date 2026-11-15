import AppKit
import ScreenCaptureKit

/// macOS 27: a clean menu bar for a capture.
///
/// Up to macOS 26 every icon has a window of its own, and a capture simply
/// leaves those windows out. macOS 27 draws the whole menu bar in one window,
/// so there's nothing to leave out. Other apps' icons are taken out of view
/// instead, the way presenting does it (`SectionController.holdClean`): for
/// the moment a picture is taken, or for as long as a recording runs. Then
/// the menu bar goes back to what the rows, presenting and peeks say.
///
/// What that can't do: macOS's own Sound, Battery, Wi‑Fi, Control Center and
/// clock always show. Barn Owl's own icons stay too, the stop button of a
/// recording among them: hiding them would make every picture wait for the
/// menu bar, where now only one with another app's icon in view does.
@MainActor
final class CleanMenuBar {
    /// One capture's claim on a clean menu bar. Made before anything is
    /// asked of the menu bar, so it can be ended at any moment, even before
    /// the icons have gone.
    @MainActor
    final class Hold {
        fileprivate let reason = UUID().uuidString
        fileprivate var isEnded = false
        fileprivate var isHolding = false
    }

    /// How long a picture waits for the menu bar at most. Icons take up to a
    /// second to fade out and close ranks, a few at a time.
    static let patience: Duration = .seconds(2)

    private let sections: SectionController

    init(sections: SectionController) {
        self.sections = sections
    }

    /// Runs `work` (taking a picture) with other apps' icons out of view,
    /// and puts them back whether it succeeds or throws.
    func during<T>(_ work: () async throws -> T) async rethrows -> T {
        let hold = Hold()
        await begin(hold)
        do {
            let result = try await work()
            await end(hold)
            return result
        } catch {
            await end(hold)
            throw error
        }
    }

    /// Takes other apps' icons out of view and waits until the menu bar has
    /// stopped moving, two seconds at most.
    ///
    /// A picture leaves the menu bar alone when no other app's icon is in
    /// view, so it's taken at once, and when a menu hangs from an icon:
    /// hiding icons then would close the menu, or slide its icon away from
    /// over it. A recording (`lasting`) always asks, as an icon may turn up
    /// while it runs.
    func begin(_ hold: Hold, lasting: Bool = false) async {
        // Nothing can be hidden: the capture is made at once, of the menu bar as it is.
        guard sections.canHoldClean else { return }
        let started = ContinuousClock.now
        let icons = await Task.detached { AgentBar.iconsInView() }.value
        let others = Self.others(among: icons, own: ProcessInfo.processInfo.processIdentifier, agent: Self.agentPID)
        if !lasting {
            guard !others.isEmpty else { return }
            guard !Self.menuHangs(from: icons) else {
                Log.app.info("A menu is open in the menu bar: its icons stay in this capture")
                return
            }
        }
        // How the bar looks now, to tell when it has changed and come to rest.
        let bar = others.isEmpty ? nil : await BarStrip.find()
        let before = await bar?.picture()
        guard !hold.isEnded else { return }
        hold.isHolding = true
        await sections.holdClean(for: hold.reason)
        // Ended while that was asked for: `end` may have run before there was anything to end.
        guard !hold.isEnded else { return await sections.endClean(for: hold.reason) }
        guard !others.isEmpty else { return }
        let settled = await waitUntilSettled(hold, bar: bar, before: before)
        let took = Int(Self.seconds(ContinuousClock.now - started) * 1000)
        if settled {
            Log.app.info("Menu bar clean for a capture after \(took, privacy: .public) ms")
        } else if !hold.isEnded {
            Log.app.error("The menu bar didn't come to rest in \(took, privacy: .public) ms; capturing it as it is")
        }
    }

    private static func seconds(_ duration: Duration) -> TimeInterval {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }

    /// Lets the menu bar go back to what it would show without this capture.
    func end(_ hold: Hold) async {
        hold.isEnded = true
        guard hold.isHolding else { return }
        hold.isHolding = false
        await sections.endClean(for: hold.reason)
    }

    private func waitUntilSettled(_ hold: Hold, bar: BarStrip?, before: Data?) async -> Bool {
        var settling = BarSettling(before: before)
        let start = ContinuousClock.now
        let own = ProcessInfo.processInfo.processIdentifier, agent = Self.agentPID
        while ContinuousClock.now - start < Self.patience, !hold.isEnded {
            try? await Task.sleep(for: .milliseconds(40))
            let picture = await bar?.picture()
            guard settling.looksAtRest(picture, at: Self.seconds(ContinuousClock.now - start)) else { continue }
            // Only now: the bar answers slowly while it's moving. An icon still
            // laid out hasn't begun to go, or is one of several going in turn.
            let othersInView = await Task.detached {
                !Self.others(among: AgentBar.iconsInView(), own: own, agent: agent).isEmpty
            }.value
            if !othersInView { return true }
        }
        return false
    }

    /// Whether a rect in AppKit screen coordinates takes in some of a menu
    /// bar. One that doesn't has no icons in it to hide.
    static func reachesMenuBar(_ rect: CGRect) -> Bool {
        reaches(rect, menuBars: NSScreen.screens.map { screen in
            // A hidden menu bar (a full-screen app's) still has its height when it slides down.
            let height = max(screen.frame.maxY - screen.visibleFrame.maxY, screen.safeAreaInsets.top,
                             NSStatusBar.system.thickness)
            return CGRect(x: screen.frame.minX, y: screen.frame.maxY - height, width: screen.frame.width, height: height)
        })
    }

    nonisolated static func reaches(_ rect: CGRect, menuBars: [CGRect]) -> Bool {
        menuBars.contains { $0.intersects(rect) }
    }

    private static var agentPID: pid_t? {
        NSRunningApplication.runningApplications(withBundleIdentifier: MenuBarPlatform.agentBundle).first?.processIdentifier
    }

    /// The other apps with an icon in view: not Barn Owl, and not MenuBarAgent,
    /// which owns the icons macOS always shows.
    nonisolated static func others(among icons: [AgentBar.Icon], own: pid_t, agent: pid_t?) -> Set<pid_t> {
        Set(icons.map(\.pid).filter { $0 > 0 && $0 != own && $0 != agent })
    }

    /// Whether a menu or popover hangs from one of the icons in view. Barn
    /// Owl's own don't count: its windows aren't in the picture.
    private static func menuHangs(from icons: [AgentBar.Icon]) -> Bool {
        let own = ProcessInfo.processInfo.processIdentifier
        let icons = icons.filter { $0.pid != own }
        guard !icons.isEmpty,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]],
              let primary = NSScreen.screens.first else { return false }
        // Window bounds are top-left based, from the top of the main screen.
        let tops = NSScreen.screens.map { primary.frame.maxY - $0.frame.maxY }
        return list.contains { hangsFromAnIcon($0, icons: icons, screenTops: tops) }
    }

    /// Whether a window is a menu or popover hanging from one of `icons`: it
    /// belongs to the icon's app, floats above ordinary windows, starts just
    /// under the menu bar and sits under its icon. A window that only lives
    /// at the top of the screen (a notch app's panel) isn't one, nor is one
    /// further along the bar.
    nonisolated static func hangsFromAnIcon(_ info: [String: Any], icons: [AgentBar.Icon],
                                           screenTops: [CGFloat]) -> Bool {
        let owner = info[kCGWindowOwnerPID as String] as? pid_t ?? 0
        let layer = info[kCGWindowLayer as String] as? Int ?? 0
        let barLevels = [CGWindowLevelForKey(.mainMenuWindow), CGWindowLevelForKey(.statusWindow)].map(Int.init)
        let mine = icons.filter { $0.pid == owner }
        guard !mine.isEmpty, layer > 0, !barLevels.contains(layer),
              let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
              let x = bounds["X"], let y = bounds["Y"], let width = bounds["Width"] else { return false }
        // The menu bar is at least 24 points tall: a menu starts at its lower edge, or a little below.
        guard screenTops.contains(where: { y >= $0 + 20 && y <= $0 + 60 }) else { return false }
        return mine.contains { $0.frame.maxX >= x - 12 && $0.frame.minX <= x + width + 12 }
    }
}

/// Tells when a menu bar that's hiding icons looks at rest, so a picture
/// doesn't catch them halfway out. Pure, so it can be tested.
///
/// The bar says where its icons will end up before they get there, and
/// drops the ones that hide a few at a time, so its picture has to stop
/// changing; whether the icons have all gone is asked once it has.
struct BarSettling {
    /// How the bar looked before anything was hidden, if that could be seen.
    let before: Data?
    private var last: Data?
    /// How many looks in a row have shown the same picture.
    private var same = 0
    private var start: TimeInterval?

    /// How long icons take to fade out and close ranks, for when pictures
    /// can't say.
    static let fadeTime: TimeInterval = 0.8

    init(before: Data?) {
        self.before = before
    }

    /// One look at the bar: how it looks now (nil if that can't be seen), and
    /// when, in seconds on any steady clock. True while it looks at rest.
    mutating func looksAtRest(_ picture: Data?, at time: TimeInterval) -> Bool {
        let since = start ?? time
        start = since
        let waited = time - since
        // Nothing to compare: wait out the fade.
        guard let picture else {
            last = nil
            same = 0
            return waited >= Self.fadeTime
        }
        same = picture == last ? same + 1 : 0
        last = picture
        // The same three times running: a pause between two icons going is shorter.
        guard same >= 2 else { return false }
        // That's rest only once the bar has changed from how it was: looks
        // from before the fade starts match as well. An icon with nothing
        // drawn in it never changes the picture, so the fade's time settles that.
        if let before, picture != before { return true }
        return waited >= Self.fadeTime
    }
}

/// The menu bar's own drawing on macOS 27: MenuBarAgent's window on each
/// display, on a clear background, so what's behind the bar never counts as
/// a change. Small, as it's only compared.
@MainActor
private struct BarStrip {
    private let shots: [(filter: SCContentFilter, configuration: SCStreamConfiguration)]

    static func find() async -> BarStrip? {
        // MenuBarAgent's window says it's off screen, yet it's the one that draws the bar.
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        else { return nil }
        let bars = content.windows.filter {
            $0.owningApplication?.bundleIdentifier == MenuBarPlatform.agentBundle && $0.frame.height < 100
        }
        let shots = content.displays.compactMap { display -> (SCContentFilter, SCStreamConfiguration)? in
            let own = bars.filter { $0.frame.intersects(display.frame) }
            guard let height = own.map({ $0.frame.maxY - display.frame.minY }).max(), height > 0 else { return nil }
            let configuration = SCStreamConfiguration()
            // Whole points: a strip with a fractional height comes back scaled to fit.
            let strip = CGRect(x: 0, y: 0, width: display.frame.width.rounded(.up), height: height.rounded(.up))
            configuration.sourceRect = strip
            configuration.width = Int(strip.width)
            configuration.height = Int(strip.height)
            configuration.showsCursor = false
            configuration.backgroundColor = .clear
            return (SCContentFilter(display: display, including: own), configuration)
        }
        return shots.isEmpty ? nil : BarStrip(shots: shots)
    }

    /// The bars' pixels, or nil if one couldn't be captured.
    func picture() async -> Data? {
        var pixels = Data()
        OwnCaptures.last = Date()
        defer { OwnCaptures.last = Date() }
        for shot in shots {
            guard let image = try? await SCScreenshotManager.captureImage(contentFilter: shot.filter,
                                                                          configuration: shot.configuration),
                  let drawn = Self.pixels(of: image) else { return nil }
            pixels.append(drawn)
        }
        return pixels
    }

    /// Drawn afresh, so two captures of the same bar give the same bytes.
    private static func pixels(of image: CGImage) -> Data? {
        guard let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                      bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = context.data else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return Data(bytes: data, count: image.width * image.height * 4)
    }
}
