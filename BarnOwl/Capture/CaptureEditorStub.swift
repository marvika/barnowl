import AppKit

// Stands in for the editor until it's merged; replaced by BarnOwl/Capture/Editor.

@MainActor
protocol CaptureEditorHost: AnyObject {
    func editor(_ editor: CaptureEditor, copy image: CGImage)
    func editor(_ editor: CaptureEditor, save image: CGImage)
    func editor(_ editor: CaptureEditor, pin image: CGImage)
    func editor(_ editor: CaptureEditor, finish image: CGImage)
    func editorDidClose(_ editor: CaptureEditor)
}

@MainActor
final class CaptureEditor {
    init(image: CGImage, scale: CGFloat, title: String, host: CaptureEditorHost) {}
    func show() {}
    func close() {}
    func render() -> CGImage? { nil }
}
