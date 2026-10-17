import AppIntents
import AppKit

/// Shortcuts actions. They run inside Barkeep, which must be running.
enum IntentBridge {
    @MainActor static weak var model: AppModel?
    @MainActor static var revealHiddenIcons: () -> Void = {}

    @MainActor
    static func requireModel() throws -> AppModel {
        guard let model else { throw IntentError.notRunning }
        return model
    }
}

enum IntentError: Error, CustomLocalizedStringResourceConvertible {
    case notRunning
    case iconNotFound(String)

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .notRunning: "Barkeep isn't running."
        case .iconNotFound(let name): "No menu bar icon called \(name)."
        }
    }
}

struct ToggleHiddenIconsIntent: AppIntent {
    static let title: LocalizedStringResource = "Show or Hide Menu Bar Icons"
    static let description = IntentDescription("Shows Barkeep's hidden menu bar icons, or hides them again.")

    @MainActor
    func perform() async throws -> some IntentResult {
        _ = try IntentBridge.requireModel()
        IntentBridge.revealHiddenIcons()
        return .result()
    }
}

struct KeepAwakeIntent: AppIntent {
    static let title: LocalizedStringResource = "Keep Mac Awake"
    static let description = IntentDescription("Keeps your Mac awake for a while, or until you stop it.")

    @Parameter(title: "Minutes", description: "0 keeps it awake until you stop it.", default: 60)
    var minutes: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Keep Mac awake for \(\.$minutes) minutes")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        try IntentBridge.requireModel().keepAwake.start(minutes: max(0, minutes))
        return .result()
    }
}

struct StopKeepAwakeIntent: AppIntent {
    static let title: LocalizedStringResource = "Stop Keeping Mac Awake"

    @MainActor
    func perform() async throws -> some IntentResult {
        try IntentBridge.requireModel().keepAwake.stop()
        return .result()
    }
}

struct PresenterModeIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Presenter Mode"
    static let description = IntentDescription("Hides every menu bar icon for presenting, or brings them back.")

    @Parameter(title: "On", default: true)
    var isOn: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("Turn presenter mode \(\.$isOn)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        try await IntentBridge.requireModel().presenter.set(isOn, automatically: false)
        return .result()
    }
}

struct OpenMenuBarIconIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Menu Bar Icon"
    static let description = IntentDescription("Opens an app's menu bar icon, even a hidden one.")

    @Parameter(title: "App name", description: "For example OneDrive or Zscaler.")
    var name: String

    static var parameterSummary: some ParameterSummary {
        Summary("Open the \(\.$name) menu bar icon")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        let model = try IntentBridge.requireModel()
        let wanted = name.lowercased()
        let items = await model.scanner.freshItems()
        guard let item = items.first(where: {
            $0.appName.lowercased() == wanted || $0.name.lowercased() == wanted
                || $0.bundleIdentifier?.lowercased() == wanted
        }) ?? items.first(where: { $0.appName.lowercased().contains(wanted) }) else {
            throw IntentError.iconNotFound(name)
        }
        model.opener.open(item)
        return .result()
    }
}

struct OpenClipboardIntent: AppIntent {
    static let title: LocalizedStringResource = "Show Clipboard History"

    @MainActor
    func perform() async throws -> some IntentResult {
        try IntentBridge.requireModel().showClipboard()
        return .result()
    }
}

struct BarkeepShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: KeepAwakeIntent(), phrases: ["Keep my Mac awake with \(.applicationName)"],
                    shortTitle: "Keep Awake", systemImageName: "cup.and.heat.waves.fill")
        AppShortcut(intent: StopKeepAwakeIntent(), phrases: ["Stop keeping awake with \(.applicationName)"],
                    shortTitle: "Stop Keep Awake", systemImageName: "cup.and.saucer")
        AppShortcut(intent: PresenterModeIntent(), phrases: ["Start presenting with \(.applicationName)"],
                    shortTitle: "Presenter Mode", systemImageName: "rectangle.on.rectangle")
        AppShortcut(intent: ToggleHiddenIconsIntent(), phrases: ["Show hidden icons with \(.applicationName)"],
                    shortTitle: "Hidden Icons", systemImageName: "chevron.left.2")
        AppShortcut(intent: OpenClipboardIntent(), phrases: ["Show clipboard history in \(.applicationName)"],
                    shortTitle: "Clipboard", systemImageName: "doc.on.clipboard")
    }
}
