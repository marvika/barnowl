import AppKit
import Observation

/// What the SwiftUI windows (setup, Settings) need from the controllers.
@MainActor
@Observable
final class AppModel {
    @ObservationIgnored let sections: SectionController
    @ObservationIgnored let keepAwake: KeepAwakeController
    @ObservationIgnored var showSetup: () -> Void = {}

    /// Mirrors SectionController.state so views can react to it.
    var sectionState: SectionState = .expanded

    init(sections: SectionController, keepAwake: KeepAwakeController) {
        self.sections = sections
        self.keepAwake = keepAwake
    }

    var engineName: String { sections.engine.displayName }
    var engineNeedsAccessibility: Bool { sections.engine.needsAccessibility }

    /// Shows every icon and keeps them up so the user can ⌘-drag them.
    func beginArranging() {
        sections.holdOpen = true
        sections.showAll()
    }

    func endArranging(collapse: Bool) {
        sections.holdOpen = false
        if collapse { sections.collapse() }
    }
}
