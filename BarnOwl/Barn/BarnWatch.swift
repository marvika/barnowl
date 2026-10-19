import AppKit
import UserNotifications

/// Keeps an eye on the disk without scanning it: every 15 minutes it reads
/// how much is free (one quick call), and warns once a day when the disk is
/// nearly full. If you ask it to, it also looks for things to tidy once a
/// week. It never cleans anything by itself.
@MainActor
final class BarnWatch: NSObject, UNUserNotificationCenterDelegate {
    private let barn: BarnModel
    private let openBarn: () -> Void
    private var task: Task<Void, Never>?

    nonisolated static let lowSpaceCategory = "barn"

    init(barn: BarnModel, openBarn: @escaping () -> Void) {
        self.barn = barn
        self.openBarn = openBarn
    }

    func start() {
        guard !DemoMode.isOn else { return }
        UNUserNotificationCenter.current().delegate = self
        task = Task { [weak self] in
            try? await Task.sleep(for: .seconds(60))
            while !Task.isCancelled {
                await self?.check()
                try? await Task.sleep(for: .seconds(15 * 60))
            }
        }
    }

    /// Nearly full: under a twentieth of the disk, or under 10 GB.
    static func isLow(_ space: DiskSpace) -> Bool {
        space.available < max(10_000_000_000, space.total / 20)
    }

    private func check() async {
        if Preferences.barnLowSpaceWarning, let space = DiskSpace.current(), Self.isLow(space),
           OwlOccasions.firstTime("lowSpace", period: OwlOccasions.today) {
            notify(title: "Your Mac is nearly full",
                   body: "Only \(Bytes.format(space.available)) left. Open the Barn and the owl will help you make room.")
        }
        if Preferences.barnWeeklyCheck, OwlOccasions.firstTime("weeklyCheck", period: Self.thisWeek) {
            barn.measure()
            while barn.isMeasuring { try? await Task.sleep(for: .seconds(2)) }
            let total = barn.safeTotal
            if total >= 2_000_000_000 {
                notify(title: "The owl found \(Bytes.format(total)) to tidy",
                       body: "Caches and build files that are safe to clean. Open the Barn to look.")
            }
        }
    }

    private static var thisWeek: String {
        let week = Calendar.current.dateComponents([.yearForWeekOfYear, .weekOfYear], from: .now)
        return "\(week.yearForWeekOfYear ?? 0)-\(week.weekOfYear ?? 0)"
    }

    private func notify(title: String, body: String) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.categoryIdentifier = Self.lowSpaceCategory
            center.add(UNNotificationRequest(identifier: "barn-\(title)", content: content, trigger: nil))
        }
    }

    // MARK: Notifications

    /// Clicking a Barn notification opens the Barn.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        switch response.notification.request.content.categoryIdentifier {
        case Self.lowSpaceCategory: await MainActor.run { openBarn() }
        // The update window is already showing, behind: bring it forward.
        case UpdateNotice.category: await MainActor.run { NSApp.activate() }
        default: break
        }
    }

    /// Shown even while Barn Owl is the active app.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }
}
