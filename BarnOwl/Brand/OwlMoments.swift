import Observation
import SwiftUI

/// How much the owl does by itself (Settings → Appearance).
enum OwlPersonality: String, CaseIterable, Identifiable {
    /// Everything: reactions, idle tricks, dozing off, surprises.
    case lively
    /// Reacts to what you do, but never starts anything itself.
    case calm
    /// Keeps still.
    case still

    var id: Self { self }

    var title: String {
        switch self {
        case .lively: "Lively"
        case .calm: "Calm"
        case .still: "Still"
        }
    }

    var summary: String {
        switch self {
        case .lively: "Reacts to what you do and gets up to things on its own."
        case .calm: "Reacts to what you do, and otherwise sits quietly."
        case .still: "Keeps still. Its eyes still show when your Mac is kept awake."
        }
    }
}

/// Something for an owl to react to, sent from wherever it happened. A new
/// cue (a new id) plays the reaction once.
struct OwlCue: Equatable {
    enum Kind: Equatable {
        case hoot, dance, found
        /// Quick toggles.
        case lightsOut, lightsOn, shush, listening, peekaboo, backAgain, secrets, unseen, nightNight
        /// The Nest.
        case caught, bye, sweep, nom
        /// Clipboard.
        case didntSee, colour(Color)
        case charged, thrown
        /// The Barn.
        case cleaned(String), bigFind(String)
    }

    let kind: Kind
    let id = UUID()

    init(_ kind: Kind) { self.kind = kind }

    static func == (lhs: OwlCue, rhs: OwlCue) -> Bool { lhs.id == rhs.id }
}

/// Every owl moment there is to discover. Settings → About shows which
/// you've met.
enum OwlMoment: String, CaseIterable, Identifiable {
    case hoot, petted, turnaround, dizzy, wideAwake, yawn, caughtNapping, dance, stretch
    case presenting, onCall, coffee, doubleShot, allNighter, lidClosed, atTheDesk, runningLow, chargedUp
    case lightsOut, shush, peekaboo, secrets, found, puzzled, bye, sweep, nom, didntSee, pretty
    case sweetDreams, hooray, santa, witch, newYear, birthday, morning, nightOwl, thrown
    case springCleaning, bigFind

    var id: Self { self }

    var title: String {
        switch self {
        case .hoot: "Hoo!"
        case .petted: "Petted"
        case .turnaround: "All the way round"
        case .dizzy: "Dizzy"
        case .wideAwake: "Wide awake"
        case .yawn: "Big yawn"
        case .caughtNapping: "Caught napping"
        case .dance: "Little dance"
        case .stretch: "Stretch"
        case .presenting: "Incognito"
        case .onCall: "On a call"
        case .coffee: "Coffee break"
        case .doubleShot: "Double shot"
        case .allNighter: "All-nighter"
        case .lidClosed: "Lid closed"
        case .atTheDesk: "At the desk"
        case .runningLow: "Running low"
        case .chargedUp: "Charged up"
        case .lightsOut: "Lights out"
        case .shush: "Shh!"
        case .peekaboo: "Peekaboo"
        case .secrets: "Secrets"
        case .found: "Found it!"
        case .puzzled: "Hmm?"
        case .bye: "Bye!"
        case .sweep: "All clear"
        case .nom: "Nom!"
        case .didntSee: "Didn't see that"
        case .pretty: "Pretty colour"
        case .sweetDreams: "Sweet dreams"
        case .hooray: "Hoo-ray!"
        case .santa: "Ho ho hoo"
        case .witch: "Spooky"
        case .newYear: "Happy New Year"
        case .birthday: "Birthday owl"
        case .morning: "Morning!"
        case .nightOwl: "Night owl"
        case .thrown: "Whee!"
        case .springCleaning: "Spring cleaning"
        case .bigFind: "Big find"
        }
    }

    /// How to find it, shown once it's been met.
    var hint: String {
        switch self {
        case .hoot: "Click an owl."
        case .petted: "Press and hold an owl."
        case .turnaround: "Click an owl three times, quickly."
        case .dizzy: "Keep clicking."
        case .wideAwake: "Start keeping your Mac awake."
        case .yawn: "Stop keeping your Mac awake."
        case .caughtNapping: "Leave it alone for a while, then move the mouse."
        case .dance, .stretch: "It does this by itself, now and then."
        case .presenting: "Start presenting."
        case .onCall: "Keep awake during a call."
        case .coffee: "Keep awake for two hours."
        case .doubleShot: "Keep awake for five hours."
        case .allNighter: "Keep awake for ten hours."
        case .lidClosed: "Turn on closed-lid mode."
        case .atTheDesk: "Use the desk layout with an external display."
        case .runningLow: "Let the battery run low."
        case .chargedUp: "Plug in."
        case .lightsOut: "Turn on Dark Mode from the quick panel."
        case .shush: "Mute the microphone."
        case .peekaboo: "Hide the desktop."
        case .secrets: "Show hidden files."
        case .found: "Search for exactly one thing."
        case .puzzled: "Search for something that isn't there."
        case .bye: "Drag a file out of the Nest."
        case .sweep: "Clear the Nest."
        case .nom: "Drop a file right on the Nest's owl."
        case .didntSee: "Copy a password."
        case .pretty: "Copy a colour, like #F5A633."
        case .sweetDreams: "Hide nothing, then open the Perch."
        case .hooray: "Finish the setup guide."
        case .santa: "Come back in December."
        case .witch: "Come back on 31 October."
        case .newYear: "Open Barn Owl in the new year."
        case .birthday: "Barn Owl's birthday is 17 October."
        case .morning: "Say good morning."
        case .nightOwl: "Stay up past midnight."
        case .thrown: "Throw the owl in About."
        case .springCleaning: "Free up space in the Barn."
        case .bigFind: "Find something over 10 GB in the Barn."
        }
    }

    /// The owl as it looks in this moment, for the collection.
    var look: OwlView {
        switch self {
        case .hoot: OwlView(blinks: false, happy: true)
        case .petted: OwlView(blinks: false, hearts: true)
        case .turnaround: OwlView(blinks: false, turn: 1.1)
        case .dizzy: OwlView(blinks: false, dizzy: true)
        case .wideAwake: OwlView(blinks: false, surprised: true, wingLift: 1)
        case .yawn: OwlView(blinks: false, lids: 0.5, yawn: 1)
        case .caughtNapping: OwlView(blinks: false, surprised: true)
        case .dance: OwlView(blinks: false, happy: true, tilt: 12)
        case .stretch: OwlView(blinks: false, wingLift: 1.25)
        case .presenting: OwlView(blinks: false, accessory: .sunglasses)
        case .onCall: OwlView(blinks: false, accessory: .headset)
        case .coffee: OwlView(blinks: false, accessory: .coffee)
        case .doubleShot: OwlView(blinks: false, accessory: .twoCoffees)
        case .allNighter: OwlView(blinks: false, lids: 0.35, accessory: .thermos, tired: true)
        case .lidClosed: OwlView(blinks: false, accessory: .blanket)
        case .atTheDesk: OwlView(look: CGVector(dx: 0, dy: -0.6), blinks: false, accessory: .glasses)
        case .runningLow: OwlView(blinks: false, lids: 0.45, tired: true)
        case .chargedUp: OwlView(blinks: false, surprised: true, wingLift: 0.6)
        case .lightsOut: OwlView(blinks: false, glowEyes: true)
        case .shush: OwlView(blinks: false, shush: true)
        case .peekaboo: OwlView(look: CGVector(dx: 0.6, dy: -0.4), blinks: false, faceDip: 0.6)
        case .secrets: OwlView(blinks: false, surprised: true, tilt: -8)
        case .found: OwlView(blinks: false, happy: true, wingLift: 0.5)
        case .puzzled: OwlView(blinks: false, tilt: 14)
        case .bye: OwlView(blinks: false, wingLift: 0.7)
        case .sweep: OwlView(blinks: false, wingLift: 0.8, tilt: -10)
        case .nom: OwlView(blinks: false, happy: true, yawn: 0.7)
        case .didntSee: OwlView(blinks: false, coverEyes: true)
        case .pretty: OwlView(blinks: false, happy: true, bellyTint: Color(hex: 0xFF8FB8))
        case .sweetDreams: OwlView(eyesOpen: false, blinks: false, accessory: .nightcap)
        case .hooray: OwlView(blinks: false, happy: true, accessory: .partyHat)
        case .santa: OwlView(blinks: false, accessory: .santaHat)
        case .witch: OwlView(blinks: false, accessory: .witchHat)
        case .newYear: OwlView(blinks: false, happy: true, accessory: .partyHat)
        case .birthday: OwlView(blinks: false, hearts: true, accessory: .partyHat)
        case .morning: OwlView(blinks: false, lids: 0.4, yawn: 0.8)
        case .nightOwl: OwlView(blinks: false, tilt: 8, glowEyes: true)
        case .thrown: OwlView(blinks: false, happy: true, wingLift: 1.1, tilt: 18)
        case .springCleaning: OwlView(blinks: false, happy: true, wingLift: 0.8, tilt: -10)
        case .bigFind: OwlView(blinks: false, surprised: true, wingLift: 0.9)
        }
    }

    /// Notes that you've met this moment.
    @MainActor
    func meet() { OwlCollection.shared.meet(self) }
}

/// The owl moments you've met, kept across launches.
@MainActor
@Observable
final class OwlCollection {
    static let shared = OwlCollection()

    private(set) var met: Set<OwlMoment>
    private static let key = "owlMomentsMet"

    private init() {
        let saved = UserDefaults.standard.stringArray(forKey: Self.key) ?? []
        met = Set(saved.compactMap(OwlMoment.init(rawValue:)))
    }

    func meet(_ moment: OwlMoment) {
        guard !met.contains(moment) else { return }
        met.insert(moment)
        UserDefaults.standard.set(met.map(\.rawValue).sorted(), forKey: Self.key)
    }
}

/// Once-a-day and once-a-year greetings, so only the first owl you see does
/// them.
@MainActor
enum OwlOccasions {
    /// Returns true the first time it's asked for this key and period.
    static func firstTime(_ key: String, period: String) -> Bool {
        let defaultsKey = "owlOccasion.\(key)"
        guard UserDefaults.standard.string(forKey: defaultsKey) != period else { return false }
        UserDefaults.standard.set(period, forKey: defaultsKey)
        return true
    }

    static var today: String {
        let day = Calendar.current.dateComponents([.year, .month, .day], from: .now)
        return "\(day.year ?? 0)-\(day.month ?? 0)-\(day.day ?? 0)"
    }

    static var thisYear: String { String(Calendar.current.component(.year, from: .now)) }
}

/// "#F5A633", "f5a633" or "#fa3" as a colour.
func colourFromHex(_ text: String) -> Color? {
    var hex = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if hex.hasPrefix("#") { hex.removeFirst() }
    guard [3, 6].contains(hex.count), hex.allSatisfy(\.isHexDigit) else { return nil }
    if hex.count == 3 { hex = hex.map { "\($0)\($0)" }.joined() }
    guard let value = UInt32(hex, radix: 16) else { return nil }
    return Color(hex: value)
}

/// Where parts of the app send cues to the owl that's showing there.
@MainActor
@Observable
final class OwlCues {
    static let shared = OwlCues()

    /// The owl in the quick panel.
    var quickPanel: OwlCue?

    func quickPanel(_ kind: OwlCue.Kind) { quickPanel = OwlCue(kind) }
}
