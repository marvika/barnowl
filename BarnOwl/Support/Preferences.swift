import AppKit

/// UserDefaults keys shared by the controllers and the SwiftUI settings
/// (which read them through @AppStorage).
enum PrefKey {
    static let autoRehide = "autoRehide"
    static let autoRehideDelay = "autoRehideDelay"
    static let alwaysHiddenEnabled = "alwaysHiddenEnabled"
    static let keepAwakeAllowDisplaySleep = "keepAwakeAllowDisplaySleep"
    static let keepAwakeHotkeyMinutes = "keepAwakeHotkeyMinutes"
    static let hasShownWelcome = "hasShownWelcome"
    static let menuShowsDarkMode = "menuShowsDarkMode"
    static let menuShowsDesktopIcons = "menuShowsDesktopIcons"
    static let menuShowsHiddenFiles = "menuShowsHiddenFiles"
    static let menuShowsMicrophone = "menuShowsMicrophone"
    static let menuShowsSleepDisplay = "menuShowsSleepDisplay"
    static let hiddenIconsDisplay = "hiddenIconsDisplay"
    static let owlPalette = "owlPalette"
    static let owlPersonality = "owlPersonality"
    static let barnLowSpaceWarning = "barnLowSpaceWarning"
    static let barnWeeklyCheck = "barnWeeklyCheck"
    static let newIconPlacement = "newIconPlacement"
    static let keepAwakeStopBelowBattery = "keepAwakeStopBelowBattery"
    static let keepAwakeKeepAvailable = "keepAwakeKeepAvailable"
    static let keepAwakeNotify = "keepAwakeNotify"
    static let showKeepAwakeIcon = "showKeepAwakeIcon"
    static let closedLidMode = "closedLidMode"
    static let closedLidLocks = "closedLidLocks"
    static let changeShowDuration = "changeShowDuration"
    static let changeLookInterval = "changeLookInterval"
    static let presenterAutomatic = "presenterAutomatic"
    static let presenterKeepAwake = "presenterKeepAwake"
    static let presenterHideDesktopIcons = "presenterHideDesktopIcons"
    static let displayProfiles = "displayProfiles"
    static let revealOnHover = "revealOnHover"
    static let revealOnScroll = "revealOnScroll"
    static let clipboardEnabled = "clipboardEnabled"
    static let clipboardLimit = "clipboardLimit"
    static let clipboardRemember = "clipboardRemember"
    static let dropTrayEnabled = "dropTrayEnabled"
    static let dropTrayTab = "dropTrayTab"
    static let nestKeepsDraggedFiles = "nestKeepsDraggedFiles"
    static let keepAwakeCountdown = "keepAwakeCountdown"
    static let agentsEnabled = "agentsEnabled"
    static let agentsMenuBar = "agentsMenuBar"
    static let agentsNotifyNeedsYou = "agentsNotifyNeedsYou"
    static let agentsNotifyDone = "agentsNotifyDone"
    static let agentsNotifyAfterMinutes = "agentsNotifyAfterMinutes"
    static let agentsEditor = "agentsEditor"
    static let agentsHideScripted = "agentsHideScripted"
    static let agentsHideScratch = "agentsHideScratch"
    static let agentsRuleAdded = "agentsRuleAdded"
    static let agentsRuleKeepsScreen = "agentsRuleKeepsScreen"
    static let agentsShowLimits = "agentsShowLimits"
    static let agentsLimitAlerts = "agentsLimitAlerts"
    static let agentsIsland = "agentsIsland"
    static let roostSky = "roostSky"
    static let captureEnabled = "captureEnabled"
    static let captureAppleKeys = "captureAppleKeys"
    static let captureCopies = "captureCopies"
    static let captureSaves = "captureSaves"
    static let captureThen = "captureThen"
    static let captureAdjusts = "captureAdjusts"
    static let capturePrivateInfo = "capturePrivateInfo"
    static let captureHintCount = "captureHintCount"
    static let captureKeepDays = "captureKeepDays"
    static let captureFolder = "captureFolder"
    static let captureNamePrefix = "captureNamePrefix"
    static let captureNameIncludesApp = "captureNameIncludesApp"
    static let captureFormat = "captureFormat"
    static let captureAtOneX = "captureAtOneX"
    static let captureCleanMenuBar = "captureCleanMenuBar"
    static let captureHidesDesktopIcons = "captureHidesDesktopIcons"
    static let captureWindowShadow = "captureWindowShadow"
    static let captureShowsPointer = "captureShowsPointer"
    static let captureSound = "captureSound"
    static let captureCardCorner = "captureCardCorner"
    static let captureCardSeconds = "captureCardSeconds"
    static let captureLastArea = "captureLastArea"
}

enum Preferences {
    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            PrefKey.autoRehide: true,
            PrefKey.autoRehideDelay: 10.0,
            PrefKey.alwaysHiddenEnabled: false,
            PrefKey.keepAwakeAllowDisplaySleep: false,
            PrefKey.keepAwakeHotkeyMinutes: 0,
            PrefKey.hasShownWelcome: false,
            PrefKey.menuShowsDarkMode: true,
            PrefKey.menuShowsDesktopIcons: true,
            PrefKey.menuShowsHiddenFiles: true,
            PrefKey.menuShowsMicrophone: true,
            PrefKey.menuShowsSleepDisplay: true,
            PrefKey.hiddenIconsDisplay: HiddenIconsDisplay.automatic.rawValue,
            PrefKey.owlPalette: OwlPalette.golden.rawValue,
            PrefKey.owlPersonality: OwlPersonality.lively.rawValue,
            PrefKey.barnLowSpaceWarning: true,
            PrefKey.barnWeeklyCheck: false,
            PrefKey.newIconPlacement: NewIconPlacement.hidden.rawValue,
            PrefKey.keepAwakeStopBelowBattery: 10,
            PrefKey.keepAwakeKeepAvailable: false,
            PrefKey.keepAwakeNotify: false,
            PrefKey.showKeepAwakeIcon: true,
            PrefKey.changeShowDuration: 30.0,
            PrefKey.changeLookInterval: 0,
            PrefKey.presenterAutomatic: true,
            PrefKey.presenterKeepAwake: true,
            PrefKey.presenterHideDesktopIcons: false,
            PrefKey.displayProfiles: false,
            PrefKey.revealOnHover: false,
            PrefKey.revealOnScroll: false,
            PrefKey.clipboardEnabled: true,
            PrefKey.clipboardLimit: 50,
            PrefKey.clipboardRemember: true,
            PrefKey.dropTrayEnabled: true,
            PrefKey.dropTrayTab: true,
            PrefKey.nestKeepsDraggedFiles: false,
            PrefKey.keepAwakeCountdown: true,
            PrefKey.agentsEnabled: true,
            PrefKey.agentsMenuBar: true,
            PrefKey.agentsNotifyNeedsYou: true,
            PrefKey.agentsNotifyDone: true,
            PrefKey.agentsNotifyAfterMinutes: 3,
            PrefKey.agentsEditor: "",
            PrefKey.agentsHideScripted: true,
            PrefKey.agentsHideScratch: true,
            PrefKey.agentsRuleAdded: false,
            PrefKey.agentsShowLimits: true,
            PrefKey.agentsLimitAlerts: true,
            PrefKey.agentsIsland: IslandMode.attention.rawValue,
            PrefKey.roostSky: RoostSky.follow.rawValue,
            // Off until you choose it, in the setup guide or Settings: you may
            // already have a capture app on these shortcuts.
            PrefKey.captureEnabled: false,
            PrefKey.captureAppleKeys: false,
            PrefKey.captureCopies: true,
            PrefKey.captureSaves: true,
            PrefKey.captureThen: CaptureThen.card.rawValue,
            PrefKey.captureAdjusts: true,
            PrefKey.capturePrivateInfo: true,
            PrefKey.captureHintCount: 0,
            PrefKey.captureKeepDays: 30,
            PrefKey.captureFolder: "",
            PrefKey.captureNamePrefix: "Screenshot",
            PrefKey.captureNameIncludesApp: false,
            PrefKey.captureFormat: CaptureFormat.png.rawValue,
            PrefKey.captureAtOneX: false,
            PrefKey.captureCleanMenuBar: true,
            PrefKey.captureHidesDesktopIcons: true,
            PrefKey.captureWindowShadow: true,
            PrefKey.captureShowsPointer: false,
            PrefKey.captureSound: true,
            PrefKey.captureCardCorner: CardCorner.bottomRight.rawValue,
            PrefKey.captureCardSeconds: 8,
        ])
    }

    private static var defaults: UserDefaults { .standard }

    static var autoRehide: Bool { defaults.bool(forKey: PrefKey.autoRehide) }
    static var autoRehideDelay: TimeInterval { max(2, defaults.double(forKey: PrefKey.autoRehideDelay)) }
    static var alwaysHiddenEnabled: Bool { defaults.bool(forKey: PrefKey.alwaysHiddenEnabled) }
    static var keepAwakeAllowDisplaySleep: Bool {
        get { defaults.bool(forKey: PrefKey.keepAwakeAllowDisplaySleep) }
        set { defaults.set(newValue, forKey: PrefKey.keepAwakeAllowDisplaySleep) }
    }
    /// 0 means "indefinitely".
    static var keepAwakeHotkeyMinutes: Int { defaults.integer(forKey: PrefKey.keepAwakeHotkeyMinutes) }
    static var menuShowsDarkMode: Bool { defaults.bool(forKey: PrefKey.menuShowsDarkMode) }
    static var menuShowsDesktopIcons: Bool { defaults.bool(forKey: PrefKey.menuShowsDesktopIcons) }
    static var menuShowsHiddenFiles: Bool { defaults.bool(forKey: PrefKey.menuShowsHiddenFiles) }
    static var hiddenIconsDisplay: HiddenIconsDisplay {
        HiddenIconsDisplay(rawValue: defaults.string(forKey: PrefKey.hiddenIconsDisplay) ?? "") ?? .automatic
    }
    static var newIconPlacement: NewIconPlacement {
        NewIconPlacement(rawValue: defaults.string(forKey: PrefKey.newIconPlacement) ?? "") ?? .hidden
    }
    /// 0 means never.
    static var keepAwakeStopBelowBattery: Int { defaults.integer(forKey: PrefKey.keepAwakeStopBelowBattery) }
    static var keepAwakeKeepAvailable: Bool { defaults.bool(forKey: PrefKey.keepAwakeKeepAvailable) }
    static var keepAwakeNotify: Bool { defaults.bool(forKey: PrefKey.keepAwakeNotify) }
    static var showKeepAwakeIcon: Bool { defaults.bool(forKey: PrefKey.showKeepAwakeIcon) }
    /// Whether Barn Owl turned closed-lid mode on (so it should turn it off again).
    /// Lock the screen when the lid closes in closed-lid mode. Off by
    /// default, as in Amphetamine.
    static var closedLidLocks: Bool { defaults.bool(forKey: PrefKey.closedLidLocks) }
    static var closedLidMode: Bool {
        get { defaults.bool(forKey: PrefKey.closedLidMode) }
        set { defaults.set(newValue, forKey: PrefKey.closedLidMode) }
    }
    /// How long a changed icon stays in view, in seconds.
    static var changeShowDuration: TimeInterval { max(5, defaults.double(forKey: PrefKey.changeShowDuration)) }
    /// Minutes between looks at watched icons' pictures; 0 = only after network changes.
    static var changeLookInterval: Int { defaults.integer(forKey: PrefKey.changeLookInterval) }
    static var presenterAutomatic: Bool { defaults.bool(forKey: PrefKey.presenterAutomatic) }
    static var presenterKeepAwake: Bool { defaults.bool(forKey: PrefKey.presenterKeepAwake) }
    static var presenterHideDesktopIcons: Bool { defaults.bool(forKey: PrefKey.presenterHideDesktopIcons) }
    /// A separate layout while an external display is connected.
    static var displayProfiles: Bool { defaults.bool(forKey: PrefKey.displayProfiles) }
    static var revealOnHover: Bool { defaults.bool(forKey: PrefKey.revealOnHover) }
    static var revealOnScroll: Bool { defaults.bool(forKey: PrefKey.revealOnScroll) }
    static var clipboardEnabled: Bool { defaults.bool(forKey: PrefKey.clipboardEnabled) }
    static var clipboardLimit: Int { max(5, defaults.integer(forKey: PrefKey.clipboardLimit)) }
    /// Keep text history across restarts (images are never saved to disk).
    static var clipboardRemember: Bool { defaults.bool(forKey: PrefKey.clipboardRemember) }
    /// Show the drop tray under the notch while dragging files.
    static var dropTrayEnabled: Bool { defaults.bool(forKey: PrefKey.dropTrayEnabled) }
    /// Keep a small tab under the notch while the shelf holds files.
    static var dropTrayTab: Bool { defaults.bool(forKey: PrefKey.dropTrayTab) }
    /// Warn once a day when the disk is nearly full.
    static var barnLowSpaceWarning: Bool { defaults.bool(forKey: PrefKey.barnLowSpaceWarning) }
    /// Look for things to tidy once a week.
    static var barnWeeklyCheck: Bool { defaults.bool(forKey: PrefKey.barnWeeklyCheck) }
    static var owlPersonality: OwlPersonality {
        OwlPersonality(rawValue: defaults.string(forKey: PrefKey.owlPersonality) ?? "") ?? .lively
    }
    /// Whether owls may move: not with Reduce Motion, and not when told to keep still.
    @MainActor static var owlMoves: Bool {
        !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion && owlPersonality != .still
    }
    /// Keep files in the Nest after you drag them out, instead of letting go.
    static var nestKeepsDraggedFiles: Bool { defaults.bool(forKey: PrefKey.nestKeepsDraggedFiles) }
    /// Show the time left next to the owl during a timed session.
    static var keepAwakeCountdown: Bool { defaults.bool(forKey: PrefKey.keepAwakeCountdown) }
    /// Show coding agents as owlets, and keep awake while they work.
    static var agentsEnabled: Bool { defaults.bool(forKey: PrefKey.agentsEnabled) }
    /// A small owlet beside the owl in the menu bar while agents are out.
    static var agentsMenuBar: Bool { defaults.bool(forKey: PrefKey.agentsMenuBar) }
    static var agentsNotifyNeedsYou: Bool { defaults.bool(forKey: PrefKey.agentsNotifyNeedsYou) }
    static var agentsNotifyDone: Bool { defaults.bool(forKey: PrefKey.agentsNotifyDone) }
    /// Only tasks at least this long get a "done" notification.
    static var agentsNotifyAfterMinutes: Int { max(0, defaults.integer(forKey: PrefKey.agentsNotifyAfterMinutes)) }
    /// The bundle ID of the editor that opens projects; empty means the first installed.
    static var agentsEditor: String { defaults.string(forKey: PrefKey.agentsEditor) ?? "" }
    /// Hide sessions run from scripts, CI and the Agent SDK.
    static var agentsHideScripted: Bool { defaults.bool(forKey: PrefKey.agentsHideScripted) }
    /// Hide sessions in temporary folders and the Claude app's scratch workspaces.
    static var agentsHideScratch: Bool { defaults.bool(forKey: PrefKey.agentsHideScratch) }
    /// Whether the "an agent is working" rule has been offered once already.
    static var agentsRuleAdded: Bool {
        get { defaults.bool(forKey: PrefKey.agentsRuleAdded) }
        set { defaults.set(newValue, forKey: PrefKey.agentsRuleAdded) }
    }
    static var agentsRuleKeepsScreen: Bool {
        get { defaults.bool(forKey: PrefKey.agentsRuleKeepsScreen) }
        set { defaults.set(newValue, forKey: PrefKey.agentsRuleKeepsScreen) }
    }
    /// Show plan limits (Claude's and Codex's 5-hour and weekly windows).
    static var agentsShowLimits: Bool { defaults.bool(forKey: PrefKey.agentsShowLimits) }
    /// Tell me at 80% and when a window resets.
    static var agentsLimitAlerts: Bool { defaults.bool(forKey: PrefKey.agentsLimitAlerts) }
    static var agentsIsland: IslandMode {
        IslandMode(rawValue: defaults.string(forKey: PrefKey.agentsIsland) ?? "") ?? .attention
    }
    /// Screenshots and markup, on Barn Owl's shortcuts.
    static var captureEnabled: Bool {
        get { defaults.bool(forKey: PrefKey.captureEnabled) }
        set { defaults.set(newValue, forKey: PrefKey.captureEnabled) }
    }
    /// Also answer ⌘⇧3 and ⌘⇧4, once macOS's own screenshot shortcuts are off.
    static var captureAppleKeys: Bool { defaults.bool(forKey: PrefKey.captureAppleKeys) }
    static var captureCopies: Bool { defaults.bool(forKey: PrefKey.captureCopies) }
    static var captureSaves: Bool { defaults.bool(forKey: PrefKey.captureSaves) }
    /// What follows a capture: the card, the editor, or nothing.
    static var captureThen: CaptureThen {
        CaptureThen(rawValue: defaults.string(forKey: PrefKey.captureThen) ?? "") ?? .card
    }
    /// Keep the selection adjustable after you let go, rather than capturing at once.
    static var captureAdjusts: Bool { defaults.bool(forKey: PrefKey.captureAdjusts) }
    /// Read each capture's text in the background, to offer hiding what looks private.
    static var capturePrivateInfo: Bool { defaults.bool(forKey: PrefKey.capturePrivateInfo) }
    /// How long captures stay editable; 0 keeps none.
    static var captureKeepDays: Int { max(0, defaults.integer(forKey: PrefKey.captureKeepDays)) }
    /// How many captures have shown the hints; they stop after ten.
    static var captureHintCount: Int {
        get { defaults.integer(forKey: PrefKey.captureHintCount) }
        set { defaults.set(newValue, forKey: PrefKey.captureHintCount) }
    }
    /// Empty means wherever macOS saves its own screenshots.
    static var captureFolder: String { defaults.string(forKey: PrefKey.captureFolder) ?? "" }
    static var captureNamePrefix: String {
        let prefix = (defaults.string(forKey: PrefKey.captureNamePrefix) ?? "").trimmingCharacters(in: .whitespaces)
        return prefix.isEmpty ? "Screenshot" : prefix
    }
    static var captureNameIncludesApp: Bool { defaults.bool(forKey: PrefKey.captureNameIncludesApp) }
    static var captureFormat: CaptureFormat {
        CaptureFormat(rawValue: defaults.string(forKey: PrefKey.captureFormat) ?? "") ?? .png
    }
    /// Save Retina captures at half their pixels, the size they look on screen.
    static var captureAtOneX: Bool { defaults.bool(forKey: PrefKey.captureAtOneX) }
    static var captureCleanMenuBar: Bool { defaults.bool(forKey: PrefKey.captureCleanMenuBar) }
    static var captureHidesDesktopIcons: Bool { defaults.bool(forKey: PrefKey.captureHidesDesktopIcons) }
    static var captureWindowShadow: Bool { defaults.bool(forKey: PrefKey.captureWindowShadow) }
    static var captureShowsPointer: Bool { defaults.bool(forKey: PrefKey.captureShowsPointer) }
    static var captureSound: Bool { defaults.bool(forKey: PrefKey.captureSound) }
    static var captureCardCorner: CardCorner {
        CardCorner(rawValue: defaults.string(forKey: PrefKey.captureCardCorner) ?? "") ?? .bottomRight
    }
    /// 0 keeps cards until you close them.
    static var captureCardSeconds: Int { max(0, defaults.integer(forKey: PrefKey.captureCardSeconds)) }
    /// The last area captured, as "x,y,width,height" in screen points, for "the same area again".
    static var captureLastArea: CGRect? {
        get {
            let parts = (defaults.string(forKey: PrefKey.captureLastArea) ?? "").split(separator: ",").compactMap { Double($0) }
            guard parts.count == 4 else { return nil }
            return CGRect(x: parts[0], y: parts[1], width: parts[2], height: parts[3])
        }
        set {
            let value = newValue.map { "\($0.minX),\($0.minY),\($0.width),\($0.height)" }
            defaults.set(value, forKey: PrefKey.captureLastArea)
        }
    }
    static var hasShownWelcome: Bool {
        get { defaults.bool(forKey: PrefKey.hasShownWelcome) }
        set { defaults.set(newValue, forKey: PrefKey.hasShownWelcome) }
    }
}
