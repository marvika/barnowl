import AppKit
import Observation
import Sparkle

/// Checks for new releases with Sparkle. The feed (appcast.xml in the
/// repository) and the key that signs updates are in Info.plist.
@MainActor
@Observable
final class Updater: NSObject {
    @ObservationIgnored private var controller: SPUStandardUpdaterController?
    @ObservationIgnored private var observation: NSKeyValueObservation?

    /// False while Sparkle is already checking or showing an update.
    private(set) var canCheck = true

    var checksAutomatically = true {
        didSet {
            guard checksAutomatically != oldValue else { return }
            controller?.updater.automaticallyChecksForUpdates = checksAutomatically
        }
    }

    /// Not called in demo mode or under tests, so screenshots and test runs
    /// never reach the network or show an update.
    func start() {
        guard controller == nil else { return }
        let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self,
                                                      userDriverDelegate: self)
        self.controller = controller
        checksAutomatically = controller.updater.automaticallyChecksForUpdates
        observation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            MainActor.assumeIsolated { self?.canCheck = updater.canCheckForUpdates }
        }
    }

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }
}

extension Bundle {
    var shortVersion: String { object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?" }
}

extension Updater: SPUUpdaterDelegate {
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

    // Barn Owl has no Dock icon or main window to badge, so an update found in
    // the background would sit unseen behind other windows. Bring it forward.
    nonisolated func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem,
                                                               state: SPUUserUpdateState) {
        guard handleShowingUpdate, !state.userInitiated else { return }
        MainActor.assumeIsolated { NSApp.activate() }
    }
}
