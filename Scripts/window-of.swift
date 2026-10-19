// Finds one of Barn Owl's on-screen windows for the screenshot scripts, by
// shape rather than title (window titles need Screen Recording permission).
//
//   swift Scripts/window-of.swift largest|panel|island
//
// Prints "id x y width height" (points, top-left origin), or nothing.
import CoreGraphics
import Foundation

let mode = CommandLine.arguments.dropFirst().first ?? "largest"
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []

struct Window {
    let id: Int
    let frame: CGRect
}

let windows: [Window] = list.compactMap { info in
    guard info[kCGWindowOwnerName as String] as? String == "Barn Owl",
          let id = info[kCGWindowNumber as String] as? Int,
          let bounds = info[kCGWindowBounds as String] as? [String: CGFloat] else { return nil }
    let frame = CGRect(x: bounds["X"] ?? 0, y: bounds["Y"] ?? 0, width: bounds["Width"] ?? 0, height: bounds["Height"] ?? 0)
    // Status items and the Perch are thin strips, and the demo's stage fills
    // the screen; skip them.
    guard frame.height > 60, frame.width < (CGDisplayBounds(CGMainDisplayID()).width - 40) else { return nil }
    return Window(id: id, frame: frame)
}

let pick: Window? = switch mode {
case "panel": windows.filter { $0.frame.width < 460 && $0.frame.height > 300 && $0.frame.minY < 60 }
    .max { $0.frame.height < $1.frame.height }
case "island": windows.first { $0.frame.minY < 120 && $0.frame.width >= 500 && $0.frame.width < 600 }
default: windows.max { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
}

if let pick {
    let f = pick.frame
    print(pick.id, Int(f.minX), Int(f.minY), Int(f.width), Int(f.height))
}
