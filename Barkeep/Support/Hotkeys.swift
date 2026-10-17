import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let toggleHiddenItems = Self("toggleHiddenItems", default: .init(.b, modifiers: [.control, .option, .command]))
    static let showAllItems = Self("showAllItems")
    static let toggleKeepAwake = Self("toggleKeepAwake")
    static let searchItems = Self("searchItems", default: .init(.m, modifiers: [.control, .option, .command]))
}
