import CoreGraphics

/// What Barn Owl learned about a capture when it was taken, worked out in
/// the background: its text (and what in it looks private) and the windows
/// inside it. The editor uses it for its smart tools.
struct CaptureInsight: Sendable, Equatable {
    var text: CaptureText = .empty
    /// Windows inside the capture, in image pixels from the top left.
    var windowRects: [CGRect] = []
    /// False if the text couldn't be read: never say "nothing private" then.
    var textWasRead = false

    /// Reads the capture's text; `windowRects` comes from the capture itself.
    static func make(image: CGImage, windowRects: [CGRect]) async -> CaptureInsight {
        do {
            let text = try await SensitiveTextFinder.scan(image)
            return CaptureInsight(text: text, windowRects: windowRects, textWasRead: true)
        } catch {
            return CaptureInsight(windowRects: windowRects)
        }
    }
}
