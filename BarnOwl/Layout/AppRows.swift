import Foundation

/// macOS 27: which row each app's icons are in.
///
/// macOS 27 shows or hides an app's icons together, so the layout there is a
/// table of apps (bundle identifiers) rather than of icons, and it no longer
/// depends on where an icon sits in the menu bar. Pure, so it can be tested.
struct AppRows: Equatable, Sendable {
    /// Visible, hidden or always hidden. Groups are kept by `GroupStore`.
    var rows: [String: MenuBarSection] = [:]

    init(rows: [String: MenuBarSection] = [:]) {
        self.rows = rows
    }

    /// From the per-icon layout saved on macOS 26. An app with icons in several
    /// rows takes the most visible one, so nothing the user kept in view goes
    /// missing. Grouped icons are left out: their group says where they are.
    init(itemRows: [String: LayoutRow]) {
        for (key, row) in itemRows {
            guard let section = row.section else { continue }
            let app = Self.app(ofKey: key)
            rows[app] = max(rows[app] ?? section, section)
        }
    }

    /// The app part of an icon's key ("com.example.app/Item-0").
    static func app(ofKey key: String) -> String {
        key.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? key
    }

    /// The row an app's icons are in. An app that isn't in the table yet goes
    /// where new icons go. With the always-hidden row switched off, what was
    /// in it is just hidden.
    func section(of app: String, newIcons: NewIconPlacement, alwaysHiddenEnabled: Bool) -> MenuBarSection {
        let section = rows[app] ?? (newIcons == .visible ? .visible : .hidden)
        return section == .alwaysHidden && !alwaysHiddenEnabled ? .hidden : section
    }

    /// The apps macOS may show while only `showing` rows are in view, or nil
    /// when that leaves nothing out, so nothing needs hiding.
    ///
    /// - `running`: every running app, so one Barn Owl hasn't listed yet
    ///   still goes where new icons go.
    /// - `grouped`: apps whose icons wait behind a group's icon. They only
    ///   come out when everything is shown.
    func allowed(showing: Set<MenuBarSection>, running: Set<String>, grouped: Set<String>,
                 newIcons: NewIconPlacement, alwaysHiddenEnabled: Bool) -> Set<String>? {
        let known = running.union(rows.keys).union(grouped)
        let allowed = known.filter { app in
            !grouped.contains(app)
                && showing.contains(section(of: app, newIcons: newIcons, alwaysHiddenEnabled: alwaysHiddenEnabled))
        }
        return allowed.count == known.count ? nil : allowed
    }

    // MARK: Saving

    init(storage: [String: String]) {
        rows = storage.compactMapValues { LayoutRow(storageValue: $0)?.section }
    }

    var storage: [String: String] {
        rows.mapValues { LayoutRow($0).storageValue }
    }
}

extension LayoutRow {
    /// The section this row is, or nil for a group's row.
    var section: MenuBarSection? {
        switch self {
        case .visible: .visible
        case .hidden: .hidden
        case .alwaysHidden: .alwaysHidden
        case .group: nil
        }
    }
}

extension DisplayProfile {
    /// Where macOS 27's table of apps is saved for this profile.
    var appRowsKey: String {
        self == .single ? "appRows" : "appRows.\(rawValue)"
    }
}
