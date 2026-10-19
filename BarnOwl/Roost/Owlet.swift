import Foundation

/// The coding agents Barn Owl knows how to watch.
enum AgentKind: String, Codable, CaseIterable, Sendable {
    case claude, codex, copilot, opencode, gemini, other

    var name: String {
        switch self {
        case .claude: "Claude Code"
        case .codex: "Codex"
        case .copilot: "Copilot CLI"
        case .opencode: "OpenCode"
        case .gemini: "Gemini CLI"
        case .other: "Agent"
        }
    }

    /// Each agent borrows one of the owl's colours.
    var palette: String {
        switch self {
        case .claude, .other: "golden"
        case .codex, .gemini: "ghost"
        case .copilot: "lilac"
        case .opencode: "ember"
        }
    }
}

/// What an owlet is doing, which picks its pose.
enum OwletState: String, Codable, CaseIterable, Sendable {
    case typing, searching, running, thinking, browsing, hatching, waitingOnHelpers, fixing
    case needsYou, asking
    case stuck, teaBreak, offline
    case done, shipped
    case resting, napping

    /// The sprite in OwletArt.states.
    var sprite: String {
        switch self {
        case .typing: "typing"
        case .searching: "search"
        case .running: "command"
        case .thinking: "think"
        case .browsing: "web"
        case .hatching: "hatch"
        case .waitingOnHelpers: "waiting"
        case .fixing: "retry"
        case .needsYou: "needs"
        case .asking: "ask"
        case .stuck: "error"
        case .teaBreak: "tea"
        case .offline: "offline"
        case .done: "done"
        case .shipped: "ship"
        case .resting: "idle"
        case .napping: "nap"
        }
    }

    /// The 16 x 16 owlet in OwletArt.icons.
    var icon: String {
        switch self {
        case .typing, .running, .thinking, .browsing, .hatching, .waitingOnHelpers, .fixing: "typing"
        case .searching: "search"
        case .needsYou: "needs"
        case .asking: "ask"
        case .stuck: "error"
        case .teaBreak: "tea"
        case .offline: "offline"
        case .done, .shipped: "done"
        case .resting, .napping: "nap"
        }
    }

    var label: String {
        switch self {
        case .typing: "Typing"
        case .searching: "Searching"
        case .running: "Running a command"
        case .thinking: "Thinking"
        case .browsing: "Browsing"
        case .hatching: "Starting a helper"
        case .waitingOnHelpers: "Waiting for its helpers"
        case .fixing: "Fixing"
        case .needsYou: "Needs you"
        case .asking: "Has a question"
        case .stuck: "Stuck"
        case .teaBreak: "Paused for the plan limit"
        case .offline: "Offline"
        case .done: "Your turn"
        case .shipped: "Shipped"
        case .resting: "Resting"
        case .napping: "Napping"
        }
    }

    /// Doing something, so worth keeping the Mac awake for.
    var isWorking: Bool {
        switch self {
        case .typing, .searching, .running, .thinking, .browsing, .hatching, .waitingOnHelpers, .fixing: true
        default: false
        }
    }

    /// Blocked until you answer.
    var needsYou: Bool { self == .needsYou || self == .asking }

    /// Worth a row of its own in the quick panel: it wants you, or it's your turn.
    var wantsAttention: Bool {
        switch self {
        case .needsYou, .asking, .stuck, .done, .shipped: true
        default: false
        }
    }

    /// Sort order: whatever needs you first, idle last.
    var rank: Int {
        switch self {
        case .needsYou, .asking: 0
        case .stuck: 1
        case .done, .shipped: 2
        case .teaBreak, .offline: 4
        case .resting, .napping: 5
        default: 3
        }
    }
}

/// What an agent is waiting on you for, read from its own log while it
/// waits. Kept only in memory, and in the widget's snapshot while it waits.
struct AgentRequest: Hashable, Sendable {
    enum Kind: Sendable { case command, question, edit, web, plan, other }
    var kind: Kind
    /// The command, the question, or the file: "git push origin main".
    var text: String
    /// A question's answers, in order.
    var options: [String] = []
    var since: Date
    /// Claude Code's questions carry on without you after a minute; one
    /// held for the island waits for you.
    var timesOut = true
    var deadline: Date? { kind == .question && timesOut ? since.addingTimeInterval(60) : nil }
}

/// What a finished turn did, from its log: counts only.
struct TurnEvidence: Hashable, Sendable {
    var filesChanged = 0
    var testsRun = 0
    var testsFailed = 0

    /// "6 files changed · tests pass".
    var summary: String? {
        var parts: [String] = []
        if filesChanged > 0 { parts.append(filesChanged == 1 ? "1 file changed" : "\(filesChanged) files changed") }
        if testsRun > 0 { parts.append(testsFailed == 0 ? "tests pass" : "\(testsFailed) test \(testsFailed == 1 ? "run" : "runs") failed") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// A subagent working for a session.
struct AgentHelper: Identifiable, Hashable, Sendable {
    let id: String
    /// "Explore", "Plan", "general-purpose" or a custom agent's name.
    var type: String
    /// The task it was given, such as "Survey prior art".
    var task: String
    var isWorking: Bool
    var started: Date

    var state: OwletState {
        guard isWorking else { return .done }
        switch type.lowercased() {
        case "explore": return .searching
        case "plan": return .thinking
        default: return .typing
        }
    }
}

/// One running agent session: an owlet.
struct AgentSession: Identifiable, Hashable, Sendable {
    /// "claude:<session id>", "codex:<pid>"…
    let id: String
    let agent: AgentKind
    var pid: Int32?
    /// The session's title, or its folder's name.
    var name: String
    var folder: URL
    var place: ProjectPlace
    /// The git branch it works on, where known.
    var branch: String?
    /// The app it runs in, such as Terminal or the Claude app.
    var host: String?
    var hostPID: Int32?
    /// The Claude app chat it runs in ("local_…"), to open that very chat.
    var appChat: String?
    /// A request held for the island to answer, when answering from it is on.
    var pendingAsk: IslandAnswers.Ask?
    var started: Date
    var state: OwletState
    var stateSince: Date
    /// One line under the name: "Wants to run a command", "3 failed commands".
    var detail: String?
    var helpers: [AgentHelper] = []
    /// Started by a script, CI or the Agent SDK rather than a person.
    var isScripted = false
    /// How long the last turn ran, for "finished after 47 min".
    var lastTurn: TimeInterval?
    /// What it's waiting on you for, while it waits.
    var request: AgentRequest?
    /// What the last (or current) turn changed.
    var evidence: TurnEvidence?

    /// Helpers in the order to show them: working ones first, newest first.
    var helpersByActivity: [AgentHelper] {
        helpers.sorted { ($0.isWorking ? 0 : 1, -$0.started.timeIntervalSince1970) < ($1.isWorking ? 0 : 1, -$1.started.timeIntervalSince1970) }
    }

    /// "barnowl" or "barnowl · tint-fix".
    var placeName: String {
        place.worktree.map { "\(place.repository) · \($0)" } ?? place.repository
    }
}

/// Where a session works: its repository, and the worktree if it's in one.
struct ProjectPlace: Hashable, Sendable {
    var repository: String
    var worktree: String?
    /// The repository's main folder, shared by its worktrees.
    var root: URL

    /// Works the place out from a folder, by its path and its `.git`:
    /// `…/barnowl/.claude/worktrees/tint-fix` is barnowl's worktree "tint-fix",
    /// and a `.git` file (not folder) points at the main repository.
    static func of(_ folder: URL, fileManager: FileManager = .default) -> ProjectPlace {
        let path = folder.standardizedFileURL.path
        for marker in ["/.claude/worktrees/", "/.worktrees/", "/.codex/worktrees/"] {
            if let range = path.range(of: marker) {
                let root = URL(fileURLWithPath: String(path[..<range.lowerBound]))
                let name = path[range.upperBound...].split(separator: "/").first.map(String.init)
                return ProjectPlace(repository: root.lastPathComponent, worktree: name, root: root)
            }
        }
        var current = folder.standardizedFileURL
        for _ in 0..<12 {
            let git = current.appending(path: ".git")
            var isFolder: ObjCBool = false
            if fileManager.fileExists(atPath: git.path, isDirectory: &isFolder) {
                if !isFolder.boolValue, let main = mainRepository(fromGitFile: git) {
                    return ProjectPlace(repository: main.lastPathComponent, worktree: current.lastPathComponent,
                                        root: main)
                }
                return ProjectPlace(repository: current.lastPathComponent, worktree: nil, root: current)
            }
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path { break }
            current = parent
        }
        return ProjectPlace(repository: folder.lastPathComponent, worktree: nil, root: folder)
    }

    /// A worktree's `.git` file says "gitdir: /path/main/.git/worktrees/name".
    static func mainRepository(fromGitFile url: URL) -> URL? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return mainRepository(fromGitFileText: text)
    }

    static func mainRepository(fromGitFileText text: String) -> URL? {
        guard let line = text.split(separator: "\n").first(where: { $0.hasPrefix("gitdir:") }) else { return nil }
        let gitdir = line.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespaces)
        guard let range = gitdir.range(of: "/.git/worktrees/") else { return nil }
        return URL(fileURLWithPath: String(gitdir[..<range.lowerBound]))
    }
}

/// Sorts command lines into a few kinds, in memory only, so failures can be
/// told apart without keeping what was run.
enum CommandKind: String, Sendable {
    case test, build, git, other

    static func of(_ command: String) -> CommandKind {
        let words = command.lowercased().split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).prefix(6)
        let line = words.joined(separator: " ")
        if words.first == "git" || words.first == "gh" { return .git }
        let tests = ["test", "pytest", "jest", "vitest", "rspec", "mocha", "phpunit", "ctest"]
        if words.contains(where: { word in tests.contains { word.hasPrefix($0) } }) { return .test }
        let builds = ["build", "xcodebuild", "make", "cargo", "tsc", "gradle", "mvn", "swiftc", "compile"]
        if builds.contains(where: { line.contains($0) }) { return .build }
        return .other
    }
}
