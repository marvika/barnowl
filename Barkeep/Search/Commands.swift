import Foundation

/// Something Barkeep can do from search.
enum BarkeepCommand: Hashable, Sendable, Identifiable {
    case keepAwake(minutes: Int)
    case extendKeepAwake(minutes: Int)
    case stopKeepAwake
    case presenter
    case darkMode
    case microphone
    case desktopIcons
    case hiddenFiles
    case sleepDisplay
    case clipboard
    case showAllIcons
    case settings(SettingsPaneID)

    var id: Self { self }

    var title: String {
        switch self {
        case .keepAwake(let minutes):
            minutes == 0 ? "Keep awake indefinitely" : "Keep awake for \(KeepAwakeFormatter.durationLabel(minutes: minutes))"
        case .extendKeepAwake(let minutes): "Keep awake \(KeepAwakeFormatter.durationLabel(minutes: minutes)) longer"
        case .stopKeepAwake: "Stop keeping awake"
        case .presenter: "Presenter mode"
        case .darkMode: "Dark mode"
        case .microphone: "Mute or unmute microphone"
        case .desktopIcons: "Hide or show desktop icons"
        case .hiddenFiles: "Show or hide hidden files"
        case .sleepDisplay: "Sleep display"
        case .clipboard: "Clipboard history"
        case .showAllIcons: "Show all menu bar icons"
        case .settings(let pane): pane == .layout ? "Arrange menu bar icons" : "\(pane.title) settings"
        }
    }

    var symbol: String {
        switch self {
        case .keepAwake, .extendKeepAwake: "cup.and.heat.waves.fill"
        case .stopKeepAwake: "cup.and.saucer"
        case .presenter: "rectangle.on.rectangle"
        case .darkMode: "circle.lefthalf.filled"
        case .microphone: "mic.slash.fill"
        case .desktopIcons: "menubar.dock.rectangle"
        case .hiddenFiles: "eye.fill"
        case .sleepDisplay: "moon.fill"
        case .clipboard: "doc.on.clipboard"
        case .showAllIcons: "eye.circle"
        case .settings(let pane): pane == .layout ? "square.grid.3x1.below.line.grid.1x2" : "gearshape"
        }
    }

    /// Words that find the command; the first word of the query must start
    /// one of them.
    var keywords: [String] {
        switch self {
        case .keepAwake, .extendKeepAwake: ["awake", "keep", "caffeinate", "amphetamine", "coffee", "nosleep"]
        case .stopKeepAwake: ["stop", "sleep", "awake"]
        case .presenter: ["presenter", "present", "presentation", "share", "screen"]
        case .darkMode: ["dark", "light", "appearance", "theme"]
        case .microphone: ["mute", "microphone", "mic", "unmute"]
        case .desktopIcons: ["desktop", "icons", "clean"]
        case .hiddenFiles: ["hidden", "files", "dotfiles", "finder"]
        case .sleepDisplay: ["sleep", "display", "screen", "lock"]
        case .clipboard: ["clipboard", "paste", "copy", "history", "shelf"]
        case .showAllIcons: ["show", "all", "icons", "reveal"]
        case .settings(let pane): ["settings", "preferences", pane.rawValue.lowercased()] + pane.extraKeywords
        }
    }
}

/// The Settings panes search can open (a mirror of SettingsPane without the
/// UI types, so the parser stays testable).
enum SettingsPaneID: String, Sendable, CaseIterable {
    case layout, general, menuBar, appearance, keepAwake, toggles, clipboard, shortcuts

    var title: String {
        switch self {
        case .layout: "Layout"
        case .general: "General"
        case .menuBar: "Menu bar"
        case .appearance: "Appearance"
        case .clipboard: "Clipboard"
        case .keepAwake: "Keep awake"
        case .toggles: "Toggles"
        case .shortcuts: "Shortcuts"
        }
    }

    var extraKeywords: [String] {
        switch self {
        case .layout: ["arrange", "groups", "layout", "move"]
        case .menuBar: ["menubar", "bar"]
        case .appearance: ["tint", "colour", "color", "spacing", "style", "look"]
        case .clipboard: []
        case .keepAwake: ["rules", "awake"]
        case .shortcuts: ["hotkeys", "keyboard"]
        case .general, .toggles: []
        }
    }
}

enum CommandParser {
    static let defaultDurations = [60, 120, 0]

    /// Commands for a query, best first. "awake 2h", "awake 90m" and
    /// "awake 45" get a matching duration.
    static func commands(for query: String) -> [BarkeepCommand] {
        let words = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard let first = words.first, first.count >= 2 || words.count > 1 else { return [] }

        var all: [BarkeepCommand] = [.stopKeepAwake, .presenter, .darkMode, .microphone, .desktopIcons,
                                     .hiddenFiles, .sleepDisplay, .clipboard, .showAllIcons]
        all += SettingsPaneID.allCases.map(BarkeepCommand.settings)

        var results: [BarkeepCommand] = []
        let wantsAwake = ["awake", "keep", "caffeinate", "amphetamine", "coffee", "nosleep"]
            .contains { $0.hasPrefix(first) }
        if wantsAwake {
            // "awake +30" adds to a running session.
            if let extra = words.dropFirst().first(where: { $0.hasPrefix("+") }),
               let minutes = duration(from: String(extra.dropFirst())), minutes > 0 {
                return [.extendKeepAwake(minutes: minutes)]
            }
            if let minutes = words.dropFirst().compactMap(duration(from:)).first {
                results.append(.keepAwake(minutes: minutes))
            } else {
                results += defaultDurations.map { .keepAwake(minutes: $0) }
            }
        }
        for command in all where command.keywords.contains(where: { $0.hasPrefix(first) }) {
            // Every further word must appear somewhere in the command.
            let rest = words.dropFirst()
            let haystack = (command.keywords + [command.title.lowercased()]).joined(separator: " ")
            if wantsAwake, case .stopKeepAwake = command, !rest.isEmpty { continue }
            if rest.allSatisfy({ duration(from: $0) != nil || haystack.contains($0) }) {
                results.append(command)
            }
        }
        return results
    }

    /// "2h", "2 h", "90m", "45", "1.5h", "forever" → minutes (0 = indefinitely).
    static func duration(from word: String) -> Int? {
        if ["forever", "indefinitely", "always", "∞"].contains(word) { return 0 }
        let lower = word.lowercased()
        let number = lower.prefix { $0.isNumber || $0 == "." || $0 == "," }.replacingOccurrences(of: ",", with: ".")
        guard let value = Double(number), value > 0 else { return nil }
        let unit = lower.dropFirst(number.count)
        switch unit {
        case "", "m", "min", "mins", "minutes": return Int(value.rounded())
        case "h", "hr", "hrs", "hour", "hours", "t", "time", "timer": return Int((value * 60).rounded())
        default: return nil
        }
    }
}
