import CoreGraphics

/// Transitional: lets a host written for the first editor keep compiling and working until it
/// adopts `editor(_:didChange:)` and `editorDidClose(_:edited:)`. Delete this file then.
extension CaptureEditorHost {
    func editor(_ editor: CaptureEditor, didChange document: EditorDocument) {}

    func editorDidClose(_ editor: CaptureEditor, edited: Bool) {
        (self as? LegacyCaptureEditorHost)?.editorDidClose(editor)
    }
}

/// The first editor's close callback, still answered while hosts move over.
@MainActor
protocol LegacyCaptureEditorHost: AnyObject {
    func editorDidClose(_ editor: CaptureEditor)
}

extension CaptureCoordinator: LegacyCaptureEditorHost {}
