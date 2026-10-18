import Foundation

/// Made-up disk contents for demo mode (Scripts/demo.sh), so screenshots of
/// the Barn never show anyone's real files.
enum BarnDemo {
    static let space = DiskSpace(total: 494_000_000_000, free: 41_300_000_000, purgeable: 3_100_000_000,
                                 system: 12_600_000_000, data: 425_400_000_000)

    static func suggestions() -> [BarnModel.Suggestion] {
        let sizes: [String: Int64] = [
            "xcode-derived-data": 8_420_000_000, "simulator-caches": 2_130_000_000, "homebrew": 3_270_000_000,
            "npm": 1_830_000_000, "pnpm": 2_060_000_000, "cocoapods": 1_480_000_000, "chrome": 1_210_000_000,
            "device-support": 6_900_000_000, "app-caches": 4_400_000_000, "installers": 2_700_000_000,
            "iphone-backups": 38_500_000_000, "xcode-archives": 5_200_000_000, "docker": 24_000_000_000,
            "macos-installers": 13_400_000_000, "unused-apps": 4_900_000_000, "big-downloads": 9_100_000_000,
            "ios-updates": 6_300_000_000, "photos-library": 61_000_000_000,
        ]
        return CleanupRule.all.compactMap { rule in
            guard let size = sizes[rule.id] else { return nil }
            var suggestion = BarnModel.Suggestion(rule: rule, size: size)
            if rule.pickItems {
                suggestion.items = items(for: rule.id, total: size)
            }
            if rule.id == "chrome" { suggestion.blockedBy = "Quit Google Chrome first" }
            return suggestion
        }
        .sorted { ($0.rule.safety, -$0.size) < ($1.rule.safety, -$1.size) }
    }

    private static func items(for rule: String, total: Int64) -> [BarnModel.Item] {
        let names: [String] = switch rule {
        case "device-support": ["iPhone17,1 26.0 (23A341)", "iPhone16,2 18.6 (22G86)", "Watch7,3 11.5 (22T572)"]
        case "installers": ["Figma-125.4.dmg", "Docker.dmg", "Zoom.pkg", "Xcode_26.xip"]
        case "app-caches": ["com.spotify.client", "com.tinyspeck.slackmacgap", "com.microsoft.VSCode", "JetBrains"]
        case "macos-installers": ["Install macOS Tahoe.app"]
        case "unused-apps": ["GarageBand.app", "Blender.app", "Unity Hub.app"]
        case "big-downloads": ["dataset.zip", "Conference talk.mov", "Ubuntu 24.04.img"]
        default: []
        }
        let share = total / Int64(max(1, names.count))
        return names.enumerated().map { index, name in
            BarnModel.Item(path: "/demo/\(name)", name: name, size: share + Int64(index) * 50_000_000,
                           modified: Date().addingTimeInterval(-Double(index + 2) * 86_400 * 9))
        }
    }

    /// A believable disk: a home folder with projects, media and caches.
    static func scan() -> DiskScan {
        var nodes: [DiskScan.Node] = [DiskScan.Node(name: DiskScanner.dataVolume, parent: -1, kind: .folder)]
        func add(_ name: String, under parent: Int32, size: Int64 = 0, kind: DiskScan.Node.Kind = .folder,
                 files: Int64 = 0) -> Int32 {
            let index = Int32(nodes.count)
            nodes.append(DiskScan.Node(name: name, parent: parent, kind: kind, size: size, reclaimable: size,
                                       files: kind == .file ? 1 : files))
            nodes[Int(parent)].children.append(index)
            // A file's size counts towards its folder straight away, as in a real scan.
            if kind == .file {
                nodes[Int(parent)].size += size
                nodes[Int(parent)].reclaimable += size
                nodes[Int(parent)].files += 1
            }
            return index
        }
        let users = add("Users", under: 0)
        let home = add("you", under: users)
        let projects = add("Projects", under: home)
        for (name, size) in [("barnowl", 3_400_000_000), ("website", 6_800_000_000), ("ios-app", 12_100_000_000),
                             ("ml-experiments", 21_500_000_000)] as [(String, Int64)] {
            let project = add(name, under: projects)
            _ = add("node_modules", under: project, size: size / 2, files: 40_000)
            _ = add("build", under: project, size: size / 3, files: 3_000)
            nodes[Int(project)].smallSize = size / 6
            nodes[Int(project)].size = size / 6
        }
        let movies = add("Movies", under: home)
        _ = add("Holiday 2026.mov", under: movies, size: 18_400_000_000, kind: .file)
        _ = add("Screen recording.mov", under: movies, size: 4_200_000_000, kind: .file)
        _ = add("Final Cut Library.fcpbundle", under: movies, size: 46_000_000_000, kind: .package, files: 2_100)
        let pictures = add("Pictures", under: home)
        _ = add("Photos Library.photoslibrary", under: pictures, size: 61_000_000_000, kind: .package, files: 48_000)
        let library = add("Library", under: home)
        _ = add("Caches", under: library, size: 14_900_000_000, files: 120_000)
        _ = add("Application Support", under: library, size: 39_000_000_000, files: 210_000)
        let developer = add("Developer", under: library)
        _ = add("Xcode", under: developer, size: 22_700_000_000, files: 300_000)
        _ = add("CoreSimulator", under: developer, size: 31_200_000_000, files: 410_000)
        _ = add("Containers", under: library, size: 0, kind: .unreadable)
        let downloads = add("Downloads", under: home)
        _ = add("Xcode_26.xip", under: downloads, size: 11_800_000_000, kind: .file)
        _ = add("dataset.zip", under: downloads, size: 7_300_000_000, kind: .file)
        nodes[Int(downloads)].smallSize = 2_100_000_000
        nodes[Int(downloads)].smallCount = 812
        nodes[Int(downloads)].size = 2_100_000_000
        let documents = add("Documents", under: home)
        nodes[Int(documents)].smallSize = 9_400_000_000
        nodes[Int(documents)].smallCount = 6_420
        nodes[Int(documents)].size = 9_400_000_000
        _ = add("Applications", under: 0, size: 41_000_000_000, files: 520_000)
        _ = add("Library", under: 0, size: 13_900_000_000, files: 160_000)
        _ = add("opt", under: 0, size: 7_200_000_000, files: 90_000)
        _ = add("private", under: 0, size: 18_500_000_000, files: 70_000)
        // Totals from the deepest up, as a real scan does.
        for index in nodes.indices.dropFirst().reversed() where nodes[index].isFolder {
            let parent = Int(nodes[index].parent)
            nodes[parent].size += nodes[index].size
            nodes[parent].reclaimable += nodes[index].size
            nodes[parent].files += nodes[index].files
        }
        return DiskScan(root: DiskScanner.dataVolume, nodes: nodes, finished: Date(), duration: 28)
    }
}
