import AppKit
import Observation
import Sparkle
import UserNotifications

/// Checks for new releases with Sparkle. The feed (appcast.xml in the
/// repository) and the key that signs updates are in Info.plist.
@MainActor
@Observable
final class Updater: NSObject {
    @ObservationIgnored private var controller: SPUStandardUpdaterController?
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []

    /// False while Sparkle is already checking or showing an update.
    private(set) var canCheck = true

    /// Off until the user says yes to Sparkle's question on the second launch,
    /// or switches it on in Settings.
    var checksAutomatically = false {
        didSet {
            guard let updater = controller?.updater, updater.automaticallyChecksForUpdates != checksAutomatically
            else { return }
            updater.automaticallyChecksForUpdates = checksAutomatically
        }
    }

    /// Not called in demo mode or under tests, so screenshots and test runs
    /// never reach the network or show an update.
    func start() {
        guard controller == nil else { return }
        let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self,
                                                      userDriverDelegate: self)
        self.controller = controller
        observations = [
            controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
                MainActor.assumeIsolated { self?.canCheck = updater.canCheckForUpdates }
            },
            // Sparkle's own question changes it too.
            controller.updater.observe(\.automaticallyChecksForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
                MainActor.assumeIsolated { self?.checksAutomatically = updater.automaticallyChecksForUpdates }
            },
        ]
    }

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }
}

extension Bundle {
    var shortVersion: String { object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?" }
}

extension Updater: SPUUpdaterDelegate {
    // Nothing about the Mac goes with the check, even if someone ticks
    // "Include anonymous system profile" in Sparkle's first prompt.
    nonisolated func allowedSystemProfileKeys(for updater: SPUUpdater) -> [String]? { [] }

    // Quitting to install an update and open the new version: settings that
    // are switched off on quit, like closed-lid mode, stay as they are.
    nonisolated func updaterWillRelaunchApplication(_ updater: SPUUpdater) {
        MainActor.assumeIsolated { ClosedLidMode.keepOnQuit = true }
    }

    #if DEBUG
    // A development build checks only when asked, so a release never offers
    // to replace the copy being worked on.
    nonisolated func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        guard updateCheck == .updates else { throw CocoaError(.userCancelled) }
    }
    #endif
}

extension Updater: SPUStandardUserDriverDelegate {
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    // Barn Owl has no Dock icon to badge, so an update found in the background
    // would sit unseen behind other windows. Pulling it to the front would
    // take the keyboard mid-sentence (a Return could hit Install), so it says
    // so in a notification instead; clicking that brings the window forward.
    nonisolated func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem,
                                                               state: SPUUserUpdateState) {
        guard handleShowingUpdate, !state.userInitiated else { return }
        let version = update.displayVersionString
        MainActor.assumeIsolated { UpdateNotice.post(version: version) }
    }

    // Quitting to install an update: keep awake carries on in the new version.
    nonisolated func updaterWillRelaunchApplication(_ updater: SPUUpdater) {
        MainActor.assumeIsolated { KeepAwakeController.saveSessionOnQuit = true }
    }
}

/// "Barn Owl 1.2 is ready", as a notification rather than a window that
/// takes the keyboard. Clicking it brings the update window forward.
enum UpdateNotice {
    nonisolated static let category = "update"

    @MainActor static func post(version: String) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "Barn Owl \(version) is ready"
            content.body = "Click to see what's new and install it."
            content.categoryIdentifier = category
            center.add(UNNotificationRequest(identifier: "update-\(version)", content: content, trigger: nil))
        }
    }
}
