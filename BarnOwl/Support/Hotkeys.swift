import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let toggleHiddenItems = Self("toggleHiddenItems", default: .init(.b, modifiers: [.control, .option, .command]))
    static let showAllItems = Self("showAllItems")
    static let toggleKeepAwake = Self("toggleKeepAwake")
    static let togglePresenter = Self("togglePresenter")
    static let clipboard = Self("clipboard", default: .init(.v, modifiers: [.control, .option, .command]))
    static let searchItems = Self("searchItems", default: .init(.m, modifiers: [.control, .option, .command]))
    static let captureArea = Self("captureArea", default: .init(.four, modifiers: [.control, .option, .command]))
    static let captureScreen = Self("captureScreen", default: .init(.three, modifiers: [.control, .option, .command]))
    static let captureSameArea = Self("captureSameArea", default: .init(.r, modifiers: [.control, .option, .command]))
    /// Select something on screen and its words go to the clipboard.
    static let captureText = Self("captureText", default: .init(.t, modifiers: [.control, .option, .command]))
    /// Reopens the last capture in the editor, its marks still editable.
    static let editLastCapture = Self("editLastCapture", default: .init(.e, modifiers: [.control, .option, .command]))
    /// Opens Capture History; no key until you choose one.
    static let captureHistory = Self("captureHistory")
    /// Select something to record; pressed again, stops the recording.
    static let recordScreen = Self("recordScreen", default: .init(.five, modifiers: [.control, .option, .command]))
    /// Select an area for a scrolling capture; pressed again, finishes it.
    static let captureScrolling = Self("captureScrolling", default: .init(.s, modifiers: [.control, .option, .command]))
    /// ⇧⌘4 and ⇧⌘3, set only while you've handed them over from macOS.
    static let captureAreaApple = Self("captureAreaApple")
    static let captureScreenApple = Self("captureScreenApple")
}
