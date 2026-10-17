import AppKit
import Observation
import SwiftUI

/// A colour that can be saved: RGBA components.
struct StoredColor: Codable, Hashable, Sendable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    init(_ color: Color) {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .black
        self.init(red: ns.redComponent, green: ns.greenComponent, blue: ns.blueComponent, alpha: ns.alphaComponent)
    }

    var color: Color { Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha) }
}

/// How the menu bar looks behind the icons.
struct MenuBarStyle: Codable, Hashable, Sendable {
    enum Shape: String, Codable, CaseIterable, Sendable {
        /// Edge to edge.
        case full
        /// One rounded pill, inset from the edges.
        case rounded
        /// Two pills, one each side of the notch (or of the middle).
        case split
    }

    var isEnabled = false
    var shape = Shape.rounded
    var tint = StoredColor(red: 0.18, green: 0.2, blue: 0.28, alpha: 0.55)
    var usesGradient = false
    var gradientEnd = StoredColor(red: 0.45, green: 0.25, blue: 0.55, alpha: 0.55)
    var hasBorder = false
    var border = StoredColor(red: 1, green: 1, blue: 1, alpha: 0.25)
    var hasShadow = true
}

/// Saves the style and draws it behind the menu bar on every display.
@MainActor
@Observable
final class MenuBarAppearance {
    var style: MenuBarStyle {
        didSet {
            save()
            apply()
        }
    }

    @ObservationIgnored private var windows: [NSWindow] = []
    @ObservationIgnored private let defaultsKey = "menuBarStyle"
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    init() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let saved = try? JSONDecoder().decode(MenuBarStyle.self, from: data) {
            style = saved
        } else {
            style = MenuBarStyle()
        }
    }

    func start() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil,
                                            queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.apply() }
        })
        // Full-screen apps hide the menu bar; the tint goes with it.
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.apply() }
        })
        apply()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(style) { UserDefaults.standard.set(data, forKey: defaultsKey) }
    }

    /// One click-through window per display, just below the menu bar's own
    /// level, so the icons and menus draw on top of it.
    func apply() {
        windows.forEach { $0.orderOut(nil) }
        windows = []
        guard style.isEnabled else { return }
        for screen in NSScreen.screens {
            let height = max(screen.frame.maxY - screen.visibleFrame.maxY, 24)
            let frame = NSRect(x: screen.frame.minX, y: screen.frame.maxY - height, width: screen.frame.width,
                               height: height)
            let notch = NotchGeometry.of(screen).map { ($0.minX - screen.frame.minX, $0.maxX - screen.frame.minX) }
            let window = TintWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.ignoresMouseEvents = true
            window.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue - 1)
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
            window.contentView = NSHostingView(rootView: MenuBarBackdrop(style: style, notch: notch)
                .frame(width: frame.width, height: frame.height))
            window.setFrame(frame, display: true)
            window.orderFrontRegardless()
            windows.append(window)
        }
    }
}

/// macOS keeps ordinary windows out of the menu bar's strip; the tint has to
/// sit exactly there.
private final class TintWindow: NSWindow {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// The shapes drawn behind the menu bar.
struct MenuBarBackdrop: View {
    let style: MenuBarStyle
    /// The notch's x range within the screen, if it has one.
    var notch: (CGFloat, CGFloat)?

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                switch style.shape {
                case .full:
                    piece(CGRect(origin: .zero, size: size), radius: 0)
                case .rounded:
                    piece(CGRect(origin: .zero, size: size).insetBy(dx: 6, dy: 3), radius: (size.height - 6) / 2)
                case .split:
                    let gapStart = notch?.0 ?? size.width / 2 - 60
                    let gapEnd = notch?.1 ?? size.width / 2 + 60
                    piece(CGRect(x: 6, y: 3, width: gapStart - 12, height: size.height - 6),
                          radius: (size.height - 6) / 2)
                    piece(CGRect(x: gapEnd + 6, y: 3, width: size.width - gapEnd - 12, height: size.height - 6),
                          radius: (size.height - 6) / 2)
                }
            }
        }
    }

    private func piece(_ rect: CGRect, radius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return shape
            .fill(fill)
            .overlay(shape.strokeBorder(style.hasBorder ? style.border.color : .clear, lineWidth: 1))
            .shadow(color: style.hasShadow ? .black.opacity(0.25) : .clear, radius: 3, y: 1)
            .frame(width: max(rect.width, 0), height: max(rect.height, 0))
            .position(x: rect.midX, y: rect.midY)
    }

    private var fill: AnyShapeStyle {
        style.usesGradient
            ? AnyShapeStyle(LinearGradient(colors: [style.tint.color, style.gradientEnd.color],
                                           startPoint: .leading, endPoint: .trailing))
            : AnyShapeStyle(style.tint.color)
    }
}

/// Space between menu bar icons, a system-wide setting that apps read when
/// they start (so it applies as apps relaunch, or everywhere after logging out).
enum IconSpacing {
    private static var spacingKey: CFString { "NSStatusItemSpacing" as CFString }
    private static var paddingKey: CFString { "NSStatusItemSelectionPadding" as CFString }
    /// macOS's own values.
    static let defaultSpacing = 16
    static let defaultPadding = 16

    static var current: Int {
        (CFPreferencesCopyValue(spacingKey, kCFPreferencesAnyApplication, kCFPreferencesCurrentUser,
                                kCFPreferencesCurrentHost) as? Int) ?? defaultSpacing
    }

    /// Sets spacing (and the matching click padding); nil resets to macOS's default.
    static func set(_ spacing: Int?) {
        let value = spacing.map { $0 as CFNumber }
        let padding = spacing.map { max(4, min($0, defaultPadding)) as CFNumber }
        CFPreferencesSetValue(spacingKey, value, kCFPreferencesAnyApplication, kCFPreferencesCurrentUser,
                              kCFPreferencesCurrentHost)
        CFPreferencesSetValue(paddingKey, padding, kCFPreferencesAnyApplication, kCFPreferencesCurrentUser,
                              kCFPreferencesCurrentHost)
        CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
    }

    /// Restarts the processes that draw the system's own icons, so they pick
    /// up the new spacing. Other apps follow when they next start.
    static func restartSystemMenuBar() {
        for name in ["ControlCenter", "SystemUIServer"] {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
            process.arguments = [name]
            try? process.run()
        }
    }
}
