import Foundation

/// When the agents' island shows at the notch.
enum IslandMode: String, CaseIterable, Identifiable, Sendable {
    case off
    /// When an agent needs you or finishes a long task, then it tucks away.
    case attention
    /// While any agent works, quietly; it grows when one needs you.
    case always

    var id: Self { self }

    var title: String {
        switch self {
        case .off: "Off"
        case .attention: "When One Needs You"
        case .always: "While Agents Work"
        }
    }
}
