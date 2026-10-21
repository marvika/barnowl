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
    static let captureSameArea = Self("captureSameArea")
    /// ⌘⇧4 and ⌘⇧3, set only while you've handed them over from macOS.
    static let captureAreaApple = Self("captureAreaApple")
    static let captureScreenApple = Self("captureScreenApple")
}
