import QuickLook
import SwiftUI
import UniformTypeIdentifiers

/// A map of everything on the disk: rings of folders, biggest first, to click
/// into; a list beside it; and a basket for what you decide can go.
struct ExploreView: View {
    @Bindable var barn: BarnModel

    var body: some View {
        switch barn.scan {
        case .idle: start
        case .scanning(let progress): scanning(progress)
        case .done(let scan): ExploreResults(barn: barn, scan: scan)
        }
    }

    private var start: some View {
        VStack(spacing: 14) {
            Image(systemName: "binoculars.fill").font(.system(size: 40)).foregroundStyle(Brand.amber)
            Text("See what takes up space").font(.title2.bold())
            Text("The owl looks through the whole disk, usually in under a minute, and draws you a map. Nothing is changed until you say so.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary).frame(maxWidth: 420)
            Button("Look Through the Disk") { barn.startScan() }
                .buttonStyle(.borderedProminent).controlSize(.large)
            if !barn.fullDiskAccess {
                Text("Without Full Disk Access, some folders show as locked.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func scanning(_ progress: DiskScanner.Progress) -> some View {
        VStack(spacing: 14) {
            ProgressView().controlSize(.large)
            Text("\(progress.files.formatted()) files · \(Bytes.format(progress.bytes))")
                .font(.title2.weight(.semibold)).monospacedDigit()
            Text(progress.folder).font(.caption).foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.middle).frame(maxWidth: 480)
            Button("Stop") { barn.cancelScan() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ExploreResults: View {
    @Bindable var barn: BarnModel
    let scan: DiskScan
    @State private var focus: Int32 = 0
    @State private var hovered: Int32?
    @State private var selected: Int32?
    @State private var showing = Listing.folder
    @State private var preview: URL?
    @State private var largest: [Int32] = []
    @State private var kind = FileKind.all
    @State private var home: Int32?

    enum Listing: String, CaseIterable { case folder = "This Folder", largest = "Biggest Files" }

    /// What sort of file, for narrowing the biggest-files list.
    enum FileKind: String, CaseIterable {
        case all = "All Kinds", videos = "Videos", images = "Disk Images and Archives", audio = "Music and Audio",
             pictures = "Pictures", documents = "Documents"

        func matches(_ name: String) -> Bool {
            guard self != .all else { return true }
            guard let type = UTType(filenameExtension: (name as NSString).pathExtension) else { return false }
            return switch self {
            case .all: true
            case .videos: type.conforms(to: .movie)
            case .images: type.conforms(to: .archive) || type.conforms(to: .diskImage)
                || ["xip", "iso", "dmg", "pkg"].contains((name as NSString).pathExtension.lowercased())
            case .audio: type.conforms(to: .audio)
            case .pictures: type.conforms(to: .image)
            case .documents: type.conforms(to: .pdf) || type.conforms(to: .presentation)
                || type.conforms(to: .spreadsheet) || type.conforms(to: .text)
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 20) {
                VStack(spacing: 10) {
                    RingMap(scan: scan, focus: focus, hovered: $hovered) { index in
                        if scan.nodes[Int(index)].isFolder, !scan.nodes[Int(index)].children.isEmpty {
                            withAnimation(.spring(duration: 0.4)) { focus = index }
                        } else {
                            selected = index
                        }
                    } goUp: {
                        if focus != 0 { withAnimation(.spring(duration: 0.4)) { focus = scan.nodes[Int(focus)].parent } }
                    }
                    .frame(width: 340, height: 340)
                    .id(focus)
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
                    footnote
                }
                VStack(alignment: .leading, spacing: 8) {
                    Breadcrumbs(scan: scan, focus: $focus, home: home)
                    HStack {
                        Picker("", selection: $showing) {
                            ForEach(Listing.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented).labelsHidden().frame(width: 240)
                        Spacer()
                        if showing == .largest {
                            Picker("", selection: $kind) {
                                ForEach(FileKind.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                            }
                            .labelsHidden().fixedSize()
                        }
                    }
                    list
                }
            }
            .padding(20)
            Spacer(minLength: 0)
            if !barn.basket.isEmpty { BasketBar(barn: barn) }
        }
        .quickLookPreview($preview)
        .task(id: scan.finished) {
            largest = scan.largestFiles(limit: 1_000)
            // Start at home, where your things are; the whole disk is one click out.
            home = scan.index(of: DiskScanner.dataVolume + FileManager.default.homeDirectoryForCurrentUser.path)
                ?? scan.index(of: DiskScanner.dataVolume + "/Users/you")
            if focus == 0, let home { focus = home }
        }
        .onKeyPress(.space) {
            if let selected { preview = URL(fileURLWithPath: scan.path(of: selected)) }
            return .handled
        }
        .onKeyPress(.leftArrow) {
            guard focus != 0 else { return .ignored }
            withAnimation(.spring(duration: 0.4)) { selected = focus; focus = scan.nodes[Int(focus)].parent }
            return .handled
        }
        .onKeyPress(.rightArrow) {
            guard let selected, scan.nodes[Int(selected)].isFolder, !scan.nodes[Int(selected)].children.isEmpty else { return .ignored }
            withAnimation(.spring(duration: 0.4)) { focus = selected; showing = .folder }
            return .handled
        }
        .onKeyPress(.delete) {
            guard let selected else { return .ignored }
            collect(selected)
            return .handled
        }
    }

    private var rows: [Int32] {
        switch showing {
        case .folder: scan.children(of: focus)
        case .largest: Array(largest.lazy.filter { kind.matches(scan.nodes[Int($0)].name) }.prefix(100))
        }
    }

    private func collect(_ index: Int32) {
        let path = scan.path(of: index)
        let node = scan.nodes[Int(index)]
        guard barn.canCollect(path), node.kind != .unreadable, !node.inCloud else { NSSound.beep(); return }
        withAnimation(.spring(duration: 0.3)) {
            barn.collect(BarnModel.Item(path: path, name: node.name, size: node.reclaimable, modified: nil))
        }
    }

    private var list: some View {
        let parentSize = max(1, scan.nodes[Int(focus)].size)
        return List(selection: $selected) {
            ForEach(rows, id: \.self) { index in
                let node = scan.nodes[Int(index)]
                ItemRow(node: node, path: showing == .largest ? scan.displayPath(of: index) : nil,
                        fraction: Double(node.size) / Double(showing == .largest ? scan.total.size : parentSize),
                        highlighted: hovered == index, inBasket: barn.basket.contains { $0.path == scan.path(of: index) },
                        note: FolderNotes.note(for: scan.displayPath(of: index)))
                    .tag(index)
                    .onHover { inside in
                        if inside { hovered = index } else if hovered == index { hovered = nil }
                    }
                    .onTapGesture(count: 2) {
                        if node.isFolder, !node.children.isEmpty { withAnimation { focus = index; showing = .folder } }
                        else { preview = URL(fileURLWithPath: scan.path(of: index)) }
                    }
                    .contextMenu { menu(for: index) }
            }
            if showing == .folder, scan.nodes[Int(focus)].smallCount > 0 {
                let node = scan.nodes[Int(focus)]
                HStack {
                    Image(systemName: "doc.on.doc").foregroundStyle(.secondary).frame(width: 20)
                    Text(node.smallCount == 1 ? "1 smaller file" : "\(node.smallCount) smaller files").foregroundStyle(.secondary)
                    Spacer()
                    Text(Bytes.format(node.smallSize)).monospacedDigit().foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.inset)
    }

    @ViewBuilder private func menu(for index: Int32) -> some View {
        let path = scan.path(of: index)
        let node = scan.nodes[Int(index)]
        Button("Quick Look") { preview = URL(fileURLWithPath: path) }
        Button("Show in Finder") { NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "") }
        Button("Copy Path") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(DiskScanner.displayPath(path), forType: .string)
        }
        Divider()
        Button("Put in Basket") { collect(index) }
            .keyboardShortcut(.delete, modifiers: [])
            .disabled(!barn.canCollect(path) || node.kind == .unreadable || node.inCloud)
        if let refusal = BarnModel.basketRefusal(DiskScanner.displayPath(path)) {
            Text("Can't go in the basket: \(refusal)")
        }
    }

    private var footnote: some View {
        let unreadable = scan.unreadable.count
        return VStack(spacing: 4) {
            Text("Scanned \(scan.total.files.formatted()) files in \(Int(scan.duration.rounded())) s")
            if unreadable > 0 {
                Text("\(unreadable) \(unreadable == 1 ? "folder was" : "folders were") locked\(barn.fullDiskAccess ? "" : ": Full Disk Access shows them")")
            }
            Button("Look Again") { barn.startScan() }.buttonStyle(.link)
        }
        .font(.caption).foregroundStyle(.secondary)
    }
}

private struct ItemRow: View {
    let node: DiskScan.Node
    /// Shown for the biggest-files list, where items come from everywhere.
    let path: String?
    let fraction: Double
    let highlighted: Bool
    var inBasket = false
    /// What a system folder is, for the ones with names nobody knows.
    var note: String?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: inBasket ? "basket.fill" : symbol)
                .foregroundStyle(node.kind == .unreadable ? .secondary : Brand.amber).frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(node.name).lineLimit(1).truncationMode(.middle)
                if let path {
                    Text(path).font(.caption2).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
                } else if let note {
                    Text(note).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            Capsule().fill(Brand.golden.opacity(0.7))
                .frame(width: max(2, 70 * fraction), height: 6)
                .frame(width: 70, alignment: .leading)
            Text(node.kind == .unreadable ? "locked" : Bytes.format(node.size))
                .monospacedDigit().frame(width: 76, alignment: .trailing)
        }
        .padding(.vertical, 2)
        .background(highlighted ? Brand.lavender.opacity(0.15) : .clear, in: .rect(cornerRadius: 6))
        .opacity(inBasket ? 0.55 : 1)
    }

    private var symbol: String {
        switch node.kind {
        case .folder: "folder.fill"
        case .package: "shippingbox.fill"
        case .file: node.inCloud ? "icloud" : "doc.fill"
        case .unreadable: "lock.fill"
        }
    }
}

/// What the folders at the top of the disk are, in a few words.
enum FolderNotes {
    static func note(for path: String) -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return switch path {
        case "/Applications": "Apps installed for everyone"
        case "/Library": "Settings and support files shared by all accounts"
        case "/private": "macOS's working files: swap, caches, temporary files. Leave to macOS."
        case "/opt": "Command-line tools, usually Homebrew"
        case "/usr": "Command-line tools that came with macOS or that you added"
        case "/Users": "Everyone's home folders"
        case "/System": "More of macOS itself"
        case "/cores": "Memory dumps from crashed programs"
        case home + "/Library": "Your apps' settings, caches and data. Tidy Up handles the safe parts."
        case home + "/Library/Containers", home + "/Library/Group Containers": "Sandboxed apps' own data"
        case home + "/Library/Application Support": "Apps' data, often things you'd miss"
        case home + "/Library/Developer": "Xcode and simulators"
        case home + "/Library/Mobile Documents": "iCloud Drive: removing here removes it everywhere"
        default: nil
        }
    }
}

private struct Breadcrumbs: View {
    let scan: DiskScan
    @Binding var focus: Int32
    var home: Int32?

    var body: some View {
        var chain: [Int32] = []
        var current = focus
        while current >= 0 {
            chain.insert(current, at: 0)
            current = scan.nodes[Int(current)].parent
        }
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(chain, id: \.self) { index in
                    Button(index == 0 ? "Whole Disk" : index == home ? "Home" : scan.nodes[Int(index)].name) {
                        withAnimation(.spring(duration: 0.4)) { focus = index }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(index == focus ? .primary : .secondary)
                    if index != focus { Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary) }
                }
            }
            .font(.callout.weight(.medium))
        }
    }
}

private struct BasketBar: View {
    @Bindable var barn: BarnModel
    @State private var confirming = false

    private var total: Int64 { barn.basket.map(\.size).reduce(0, +) }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "basket.fill").font(.title2).foregroundStyle(Brand.amber)
            VStack(alignment: .leading, spacing: 1) {
                Text("Basket: \(barn.basket.count) \(barn.basket.count == 1 ? "item" : "items"), \(Bytes.format(total))")
                    .font(.headline)
                Text(barn.basket.map(\.name).joined(separator: ", ")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Menu("Basket") {
                ForEach(barn.basket) { item in
                    Button("Take Out \(item.name) (\(Bytes.format(item.size)))") {
                        withAnimation { barn.basket.removeAll { $0.path == item.path } }
                    }
                }
                Divider()
                Button("Take Everything Out") { withAnimation { barn.basket = [] } }
            }
            .fixedSize()
            Button("Move to Trash…") { confirming = true }.buttonStyle(.borderedProminent)
        }
        .alert("Move \(barn.basket.count == 1 ? "this" : "these \(barn.basket.count)") to the Trash?", isPresented: $confirming) {
            Button("Move to Trash") { barn.trashBasket() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(barn.basket.prefix(12).map { "\($0.name) (\(Bytes.format($0.size)))" }.joined(separator: "\n")
                 + (barn.basket.count > 12 ? "\n…and \(barn.basket.count - 12) more" : "")
                 + "\n\nYou can undo, or put them back from the Trash.")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }
}

// MARK: - The ring map

/// Rings of folders around a centre: each ring a level deeper, each slice as
/// wide as its share of the space. Hover to see what it is; click a folder to
/// go in; click the centre to go back out.
struct RingMap: View {
    let scan: DiskScan
    let focus: Int32
    @Binding var hovered: Int32?
    let open: (Int32) -> Void
    let goUp: () -> Void

    private struct Slice {
        let index: Int32
        let depth: Int
        let start: Double
        let end: Double
        let hue: Int
        /// Its place among its siblings, for a shade of the family colour.
        let position: Int
    }

    private static let levels = 4
    private static let hues: [Color] = [Brand.amber, Brand.lavender, Color(hex: 0x5ED3B5), Color(hex: 0xFF8A7A),
                                        Color(hex: 0x6FB4FF), Color(hex: 0xE9A6FF), Brand.golden, Color(hex: 0x9AD872)]

    /// Worked out once per folder, not on every hover.
    private let slices: [Slice]

    init(scan: DiskScan, focus: Int32, hovered: Binding<Int32?>, open: @escaping (Int32) -> Void,
         goUp: @escaping () -> Void) {
        self.scan = scan
        self.focus = focus
        _hovered = hovered
        self.open = open
        self.goUp = goUp
        slices = Self.slices(of: scan, around: focus)
    }

    private static func slices(of scan: DiskScan, around focus: Int32) -> [Slice] {
        var result: [Slice] = []
        // Colours are given out at the first ring that really splits, so a
        // folder holding one big folder isn't drawn all in one colour.
        func add(_ index: Int32, depth: Int, start: Double, end: Double, hue: Int) {
            let node = scan.nodes[Int(index)]
            guard node.size > 0 else { return }
            var angle = start
            let children = scan.children(of: index)
            let splits = children.prefix(2).count == 2
                && Double(scan.nodes[Int(children[1])].size) / Double(node.size) > 0.02
            for (position, child) in children.enumerated() {
                let childNode = scan.nodes[Int(child)]
                let span = (end - start) * Double(childNode.size) / Double(node.size)
                // Too thin to see or point at: leave it to the list.
                guard span > 0.6 / 360 else { break }
                let childHue = hue < 0 && splits ? position % hues.count : hue
                result.append(Slice(index: child, depth: depth + 1, start: angle, end: angle + span, hue: childHue,
                                    position: position))
                if depth + 1 < levels, childNode.isFolder { add(child, depth: depth + 1, start: angle, end: angle + span, hue: childHue) }
                angle += span
            }
        }
        add(focus, depth: 0, start: 0, end: 1, hue: -1)
        return result
    }

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let centre = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            let hole = size * 0.17
            let ring = (size / 2 - hole) / CGFloat(Self.levels)
            ZStack {
                Canvas { context, _ in
                    for slice in slices {
                        let inner = hole + ring * CGFloat(slice.depth - 1) + 1
                        let outer = inner + ring - 2
                        var path = Path()
                        let from = Angle(degrees: slice.start * 360 - 90), to = Angle(degrees: slice.end * 360 - 90)
                        path.addArc(center: centre, radius: outer, startAngle: from, endAngle: to, clockwise: false)
                        path.addArc(center: centre, radius: inner, startAngle: to, endAngle: from, clockwise: true)
                        path.closeSubpath()
                        let node = scan.nodes[Int(slice.index)]
                        var colour = Self.shade(slice)
                        if node.kind == .file { colour = Color.gray.opacity(0.45) }
                        if node.kind == .unreadable { colour = Color.gray.opacity(0.2) }
                        context.fill(path, with: .color(colour))
                        if hovered == slice.index { context.stroke(path, with: .color(.primary), lineWidth: 2) }
                    }
                }
                centreLabel.frame(width: hole * 2 - 10)
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let point): hovered = slice(at: point, centre: centre, hole: hole, ring: ring, in: slices)?.index
                case .ended: hovered = nil
                }
            }
            .gesture(SpatialTapGesture().onEnded { tap in
                if hypot(tap.location.x - centre.x, tap.location.y - centre.y) < hole { goUp() }
                else if let slice = slice(at: tap.location, centre: centre, hole: hole, ring: ring, in: slices) { open(slice.index) }
            })
        }
        .accessibilityLabel("Map of \(scan.nodes[Int(focus)].name)")
    }

    /// The family colour, a little lighter or darker for each sibling and
    /// fainter further out, so neighbours stay apart even inside one big folder.
    private static func shade(_ slice: Slice) -> Color {
        let base = NSColor(slice.hue < 0 ? Color.gray : hues[slice.hue]).usingColorSpace(.sRGB) ?? .gray
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        base.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        let step = CGFloat(slice.position % 4) - 1.5
        let shifted = NSColor(hue: (hue + step * 0.018 + 1).truncatingRemainder(dividingBy: 1),
                              saturation: max(0, min(1, saturation - step * 0.06)),
                              brightness: max(0, min(1, brightness + step * 0.07)), alpha: 1)
        return Color(nsColor: shifted).opacity(1 - Double(slice.depth - 1) * 0.15)
    }

    private var centreLabel: some View {
        let shown = scan.nodes[Int(hovered ?? focus)]
        return VStack(spacing: 2) {
            Text(hovered == nil && focus == 0 ? "Disk" : shown.name)
                .font(.caption.weight(.semibold)).lineLimit(2).multilineTextAlignment(.center)
            Text(Bytes.format(shown.size)).font(.callout.weight(.bold)).monospacedDigit()
            if hovered == nil && focus != 0 {
                Image(systemName: "arrow.up.circle").foregroundStyle(.secondary)
            }
        }
    }

    private func slice(at point: CGPoint, centre: CGPoint, hole: CGFloat, ring: CGFloat, in slices: [Slice]) -> Slice? {
        let dx = point.x - centre.x, dy = point.y - centre.y
        let distance = hypot(dx, dy)
        guard distance > hole else { return nil }
        let depth = Int((distance - hole) / ring) + 1
        var angle = atan2(dy, dx) * 180 / .pi + 90
        if angle < 0 { angle += 360 }
        let fraction = angle / 360
        return slices.first { $0.depth == depth && fraction >= $0.start && fraction < $0.end }
    }
}
