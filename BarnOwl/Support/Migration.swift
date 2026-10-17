import Foundation

/// Barn Owl used to be called Barkeep, with its own bundle ID. On first
/// launch this copies Barkeep's settings and files over, so nothing has to
/// be set up again (macOS still asks for the permissions anew).
enum Migration {
    static let oldDomain = "io.github.marvika.Barkeep"
    private static let doneKey = "migratedFromBarkeep"

    static func runIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: doneKey) else { return }
        defer { defaults.set(true, forKey: doneKey) }
        guard let old = UserDefaults(suiteName: oldDomain)?.persistentDomain(forName: oldDomain), !old.isEmpty
        else { return }
        for (key, value) in old {
            defaults.set(translated(value, for: key), forKey: translated(key))
        }
        copyFiles()
        Log.app.info("Carried over \(old.count) settings from Barkeep")
    }

    /// Barkeep's status items were named "Barkeep…"; their saved positions
    /// follow under the new names.
    static func translated(_ key: String) -> String {
        key.replacingOccurrences(of: "Barkeep", with: "BarnOwl")
    }

    static func translated(_ value: Any, for key: String) -> Any {
        if key == PrefKey.hiddenIconsDisplay, (value as? String) == "barkeepBar" { return "perch" }
        return value
    }

    /// Saved icon pictures and clipboard history.
    private static func copyFiles() {
        let fileManager = FileManager.default
        guard let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        let old = support.appending(path: "Barkeep", directoryHint: .isDirectory)
        let new = support.appending(path: "Barn Owl", directoryHint: .isDirectory)
        guard fileManager.fileExists(atPath: old.path), !fileManager.fileExists(atPath: new.path) else { return }
        try? fileManager.copyItem(at: old, to: new)
    }
}
