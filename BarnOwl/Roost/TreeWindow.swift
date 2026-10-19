import AppKit
import Observation
import SwiftUI

/// The Roost's tree on its own, in a window you can keep beside your work.
/// Its views are let go when it closes, and the owlets hold still while it's
/// hidden behind other windows, so it costs nothing when you can't see it.
@MainActor
final class TreeWindowController {
    private let model: AppModel
    private let state = TreeWindowState()
    private var window: NSWindow?
    private var observers: [NSObjectProtocol] = []

    private static let keepOnTopKey = "roostTreeKeepOnTop"

    init(model: AppModel) {
        self.model = model
        state.keepOnTop = UserDefaults.standard.bool(forKey: Self.keepOnTopKey)
        state.onKeepOnTopChange = { [weak self] onTop in
            UserDefaults.standard.set(onTop, forKey: Self.keepOnTopKey)
            self?.window?.level = onTop ? .floating : .normal
        }
    }

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        if window.contentViewController == nil {
            let host = NSHostingController(rootView: TreeWindowView(model: model, state: state))
            // The window keeps the size you gave it; SwiftUI would shrink it to the content's minimum.
            host.sizingOptions = []
            let frame = window.frame
            window.contentViewController = host
            window.setFrame(frame, display: false)
        }
        window.level = state.keepOnTop ? .floating : .normal
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: true)
        window.title = "Roost Tree"
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.minSize = NSSize(width: 480, height: 360)
        window.collectionBehavior.insert(.fullScreenAuxiliary)
        if !window.setFrameUsingName("BarnOwlRoostTree") { window.center() }
        window.setFrameAutosaveName("BarnOwlRoostTree")
        let centre = NotificationCenter.default
        observers.append(centre.addObserver(forName: NSWindow.willCloseNotification, object: window,
                                            queue: .main) { [weak window] _ in
            MainActor.assumeIsolated { window?.contentViewController = nil }
        })
        observers.append(centre.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: window,
                                            queue: .main) { [weak window, state] _ in
            MainActor.assumeIsolated {
                state.isVisible = window?.occlusionState.contains(.visible) ?? false
            }
        })
        return window
    }
}

/// What the tree window's view needs from its controller.
@MainActor
@Observable
final class TreeWindowState {
    var isVisible = true
    var keepOnTop = false {
        didSet { if keepOnTop != oldValue { onKeepOnTopChange(keepOnTop) } }
    }
    @ObservationIgnored var onKeepOnTopChange: (Bool) -> Void = { _ in }
}

private struct TreeWindowView: View {
    let model: AppModel
    @Bindable var state: TreeWindowState
    @State private var selected: String?
    @AppStorage(PrefKey.roostSky) private var sky = RoostSky.follow

    var body: some View {
        RoostTreeView(model: model, sessions: model.agents.visible, cameHome: model.agents.cameHome, sky: sky,
                      selected: $selected, scrolls: false)
            .ignoresSafeArea()
            .frame(minWidth: 480, minHeight: 360)
            .background(Brand.indigoDeep)
            .environment(\.owletsMove, state.isVisible && Preferences.owlMoves
                         && !ProcessInfo.processInfo.isLowPowerModeEnabled)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    let on = state.keepOnTop
                    Button {
                        state.keepOnTop.toggle()
                    } label: {
                        Image(systemName: on ? "pin.fill" : "pin")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(on ? Color.white : Color.secondary)
                            .frame(width: 30, height: 22)
                            .background(on ? Brand.accent : Color.clear, in: .capsule)
                            .contentShape(.capsule)
                    }
                    .buttonStyle(.plain)
                    .help(on ? "Kept above other windows. Click to stop." : "Keep on Top: stay above other windows")
                    .accessibilityLabel("Keep on Top")
                    .accessibilityValue(on ? "On" : "Off")
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
    }
}
