import Foundation

enum ItemSearch {
    /// Items whose name, app or title contain every word of the query. Names
    /// starting with the first word rank first; otherwise items keep the order
    /// they're given in. Bundle IDs aren't searched: "com.electron…" would
    /// match far too much.
    static func filter(_ items: [MenuBarItem], query: String) -> [MenuBarItem] {
        let words = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return items }
        return items
            .filter { item in
                let haystack = [item.name, item.appName, item.title ?? ""].joined(separator: " ").lowercased()
                return words.allSatisfy(haystack.contains)
            }
            .enumerated()
            .sorted { lhs, rhs in
                let l = lhs.element.name.lowercased().hasPrefix(words[0])
                let r = rhs.element.name.lowercased().hasPrefix(words[0])
                return l != r ? l : lhs.offset < rhs.offset
            }
            .map(\.element)
    }
}
