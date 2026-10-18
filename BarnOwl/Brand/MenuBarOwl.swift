import AppKit
import SwiftUI

/// The owl in the menu bar: a template image (so it follows the menu bar's
/// colour), with eyes from shut (0) to wide open (1).
enum MenuBarOwl {
    /// A solid owl with its heart-shaped face cut out, so it reads as an owl
    /// even at 16 points, and the eyes inside. Openness above 1 is a wide
    /// stare, for waking up. `look` (-1…1) moves the eyes sideways by up to a
    /// point; `winkRight` shuts one eye; `shades` puts on sunglasses.
    static func image(openness: CGFloat, look: CGFloat = 0, winkRight: Bool = false, shades: Bool = false,
                      height: CGFloat = 17) -> NSImage {
        let bounds = OwlGeometry.pebbleBounds
        let size = NSSize(width: (height * bounds.width / bounds.height).rounded(.up), height: height)
        let image = NSImage(size: size, flipped: true) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            // Map the owl's pebble onto the whole image.
            let scale = rect.height / bounds.height
            let unit = CGRect(x: -bounds.minX * scale + (rect.width - bounds.width * scale) / 2,
                              y: -bounds.minY * scale, width: scale, height: scale)
            context.addPath(OwlGeometry.pebble(in: unit))
            context.addPath(OwlGeometry.face(in: unit))
            context.setFillColor(NSColor.black.cgColor)
            context.fillPath(using: .evenOdd)

            let (leftEye, rightEye) = OwlGeometry.eyeCentres(in: unit)
            let shift = max(-1, min(1, look)) * scale * 0.035
            let left = CGPoint(x: leftEye.x + shift, y: leftEye.y), right = CGPoint(x: rightEye.x + shift, y: rightEye.y)
            if shades {
                for centre in [left, right] {
                    context.addPath(CGPath(roundedRect: CGRect(x: centre.x - scale * 0.085, y: centre.y - scale * 0.06,
                                                               width: scale * 0.17, height: scale * 0.12),
                                           cornerWidth: scale * 0.03, cornerHeight: scale * 0.03, transform: nil))
                }
                context.addRect(CGRect(x: left.x, y: left.y - scale * 0.045, width: right.x - left.x, height: scale * 0.025))
                context.fillPath()
            }
            for (index, centre) in [left, right].enumerated() where !shades {
                let open = index == 1 && winkRight ? 0 : openness
                if open > 0.15 {
                    let width = scale * 0.105 * max(1, sqrt(open))
                    let eyeHeight = scale * 0.115 * open
                    context.fillEllipse(in: CGRect(x: centre.x - width / 2, y: centre.y - eyeHeight / 2,
                                                   width: width, height: eyeHeight))
                } else {
                    context.move(to: CGPoint(x: centre.x - scale * 0.055, y: centre.y - scale * 0.005))
                    context.addQuadCurve(to: CGPoint(x: centre.x + scale * 0.055, y: centre.y - scale * 0.005),
                                         control: CGPoint(x: centre.x, y: centre.y + scale * 0.06))
                    context.setStrokeColor(NSColor.black.cgColor)
                    context.setLineWidth(1.3)
                    context.setLineCap(.round)
                    context.strokePath()
                }
            }
            context.addPath(OwlGeometry.beak(in: unit))
            context.fillPath()
            return true
        }
        image.isTemplate = true
        return image
    }
}

/// The app icon: the owl against a dusk sky with a crescent moon.
struct AppIconArtwork: View {
    var body: some View {
        GeometryReader { proxy in
            let side = proxy.size.width
            let inset = side * 100 / 1024
            ZStack {
                RoundedRectangle(cornerRadius: (side - inset * 2) * 0.225, style: .continuous)
                    .fill(LinearGradient(colors: [Color(red: 0.32, green: 0.30, blue: 0.68), Brand.indigoDeep],
                                         startPoint: .top, endPoint: .bottom))
                    .overlay {
                        // A few stars and a moon.
                        Canvas { context, size in
                            let stars: [(CGFloat, CGFloat, CGFloat)] = [
                                (0.18, 0.2, 0.012), (0.3, 0.12, 0.008), (0.82, 0.32, 0.01), (0.12, 0.42, 0.007),
                                (0.88, 0.62, 0.008), (0.24, 0.78, 0.006),
                            ]
                            for (x, y, r) in stars {
                                context.fill(Path(ellipseIn: CGRect(x: x * size.width, y: y * size.height,
                                                                     width: r * size.width * 2, height: r * size.width * 2)),
                                             with: .color(.white.opacity(0.75)))
                            }
                            var moon = Path(ellipseIn: CGRect(x: 0.68 * size.width, y: 0.09 * size.height,
                                                              width: 0.16 * size.width, height: 0.16 * size.width))
                            moon = moon.subtracting(Path(ellipseIn: CGRect(x: 0.725 * size.width, y: 0.075 * size.height,
                                                                           width: 0.15 * size.width, height: 0.15 * size.width)))
                            context.fill(moon, with: .color(Brand.amber))
                        }
                        .clipShape(RoundedRectangle(cornerRadius: (side - inset * 2) * 0.225, style: .continuous))
                    }
                    .shadow(color: .black.opacity(0.35), radius: side * 0.02, y: side * 0.012)
                    .padding(inset)
                OwlView(eyesOpen: true, look: CGVector(dx: 0.2, dy: 0.15), blinks: false, palette: .golden)
                    .frame(width: side * 0.66, height: side * 0.66)
                    .offset(x: -side * 0.02, y: side * 0.05)
                    .shadow(color: .black.opacity(0.3), radius: side * 0.015, y: side * 0.01)
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

/// `"Barn Owl" --render-icons <folder>` writes the app icon set and exits.
/// `--render-owls <file.png>` writes a sheet of the owl's looks, for checking
/// the drawing without clicking through the app. `--render-owl-strip` and
/// `--render-owl` draw the pictures in the README (Scripts/make-hero.sh).
/// Scripts/make-icon.sh uses it, so the icon is drawn by the same code as
/// the owl in the app.
@MainActor
enum IconRenderer {
    static func runIfRequested() {
        let arguments = CommandLine.arguments
        if let index = arguments.firstIndex(of: "--render-owls"), arguments.count > index + 1 {
            write(OwlSheet(), to: URL(fileURLWithPath: arguments[index + 1]), scale: 2)
            exit(0)
        }
        if let index = arguments.firstIndex(of: "--measure-scan"), arguments.count > index + 1 {
            // Times a scan and prints what it found, for tuning the scanner.
            let root = arguments[index + 1]
            let done = DispatchSemaphore(value: 0)
            Task.detached {
                if let scan = await DiskScanner().scan(root: root, progress: { _ in }) {
                    print("Scanned \(root) in \(String(format: "%.1f", scan.duration)) s")
                    print("  \(scan.total.files) files, \(Bytes.format(scan.total.size)) on disk, " +
                          "\(Bytes.format(scan.total.reclaimable)) reclaimable, \(scan.nodes.count) entries kept")
                    print("  \(scan.unreadable.count) folders not readable")
                    for child in scan.children(of: 0).prefix(8) {
                        print("  \(Bytes.format(scan.nodes[Int(child)].size))\t\(scan.displayPath(of: child))")
                    }
                }
                done.signal()
            }
            done.wait()
            exit(0)
        }
        if let index = arguments.firstIndex(of: "--render-owl-strip"), arguments.count > index + 1 {
            write(OwlStrip(), to: URL(fileURLWithPath: arguments[index + 1]), scale: 2)
            exit(0)
        }
        if let index = arguments.firstIndex(of: "--render-owl"), arguments.count > index + 1 {
            let owl = OwlView(look: CGVector(dx: 0.25, dy: 0.1), blinks: false, palette: .golden)
                .frame(width: 400, height: 400)
            write(owl, to: URL(fileURLWithPath: arguments[index + 1]), scale: 2)
            exit(0)
        }
        guard let index = arguments.firstIndex(of: "--render-icons"), arguments.count > index + 1 else { return }
        let folder = URL(fileURLWithPath: arguments[index + 1])
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var images: [[String: String]] = []
        for points in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let pixels = CGFloat(points * scale)
                let renderer = ImageRenderer(content: AppIconArtwork().frame(width: pixels, height: pixels))
                renderer.scale = 1
                let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
                if let image = renderer.nsImage, let tiff = image.tiffRepresentation,
                   let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                    try? png.write(to: folder.appending(path: name))
                    images.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": name])
                }
            }
        }
        let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
        if let data = try? JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: folder.appending(path: "Contents.json"))
        }
        print("Wrote \(images.count) icons to \(folder.path)")
        exit(0)
    }

    private static func write(_ view: some View, to url: URL, scale: CGFloat) {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        if let image = renderer.nsImage, let tiff = image.tiffRepresentation,
           let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            try? png.write(to: url)
            print("Wrote \(url.path)")
        }
    }
}

/// Every look of the owl, in every colour, on dusk, light and dark.
private struct OwlSheet: View {
    private let looks: [(String, OwlView)] = OwlMoment.allCases.map { ($0.title, $0.look) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(120)), count: 8), spacing: 10) {
                ForEach(looks.indices, id: \.self) { index in
                    VStack(spacing: 4) {
                        ZStack {
                            Brand.dusk
                            looks[index].1.frame(width: 100, height: 100)
                        }
                        .frame(width: 120, height: 116).clipShape(.rect(cornerRadius: 12))
                        Text(looks[index].0).font(.caption).foregroundStyle(.black)
                    }
                }
            }
            HStack(spacing: 10) {
                ForEach(OwlPalette.allCases) { palette in
                    VStack(spacing: 4) {
                        HStack(spacing: 0) {
                            ZStack { Brand.dusk; OwlView(blinks: false, palette: palette).frame(width: 70, height: 70) }
                            ZStack { Color(hex: 0xF5F5F7); OwlView(blinks: false, palette: palette).frame(width: 44, height: 44) }
                            ZStack { Color(hex: 0x1E1E1E); OwlView(blinks: false, palette: palette).frame(width: 24, height: 24) }
                        }
                        .frame(width: 240, height: 84).clipShape(.rect(cornerRadius: 12))
                        Text(palette.title).font(.caption).foregroundStyle(.black)
                    }
                }
            }
            HStack(spacing: 16) {
                ForEach([0, 0.5, 1, 1.35] as [CGFloat], id: \.self) { openness in
                    HStack(spacing: 4) {
                        Image(nsImage: MenuBarOwl.image(openness: openness)).renderingMode(.template).foregroundStyle(.black)
                        Image(nsImage: MenuBarOwl.image(openness: openness)).renderingMode(.template).foregroundStyle(.white)
                            .padding(3).background(Color(hex: 0x2A2A30))
                    }
                }
                AppIconArtwork().frame(width: 64, height: 64)
                AppIconArtwork().frame(width: 32, height: 32)
            }
        }
        .padding(14)
        .background(.white)
    }
}

/// A row of the owl's moods on a dusk sky, for the README.
private struct OwlStrip: View {
    private let moods: [(String, OwlView)] = [
        ("Wide awake", OwlView(blinks: false, surprised: true, wingLift: 0.9)),
        ("Hoo!", OwlView(look: CGVector(dx: 0.2, dy: 0.1), blinks: false, tilt: -10)),
        ("Presenting", OwlView(blinks: false, accessory: .sunglasses)),
        ("Petted", OwlView(blinks: false, hearts: true)),
        ("Done!", OwlView(blinks: false, happy: true, accessory: .partyHat)),
        ("Mac may sleep", OwlView(eyesOpen: false, blinks: false, accessory: .nightcap)),
    ]

    var body: some View {
        HStack(spacing: 18) {
            ForEach(moods.indices, id: \.self) { index in
                VStack(spacing: 10) {
                    moods[index].1.frame(width: 120, height: 120)
                    Text(moods[index].0)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.9))
                }
                .frame(width: 136)
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 44)
        .padding(.bottom, 22)
        .background(DuskSky())
        .clipShape(.rect(cornerRadius: 24, style: .continuous))
    }
}
