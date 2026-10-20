import Foundation
import Testing
@testable import BarnOwl

/// Agents started by other agents: their names, their caller's twig, and Codex's logs.
struct HelpersTests {
    private func session(_ id: String, _ agent: AgentKind, _ repository: String, _ state: OwletState,
                         calledBy: String? = nil, model: String? = nil) -> AgentSession {
        let folder = URL(fileURLWithPath: "/Users/me/code/\(repository)")
        var session = AgentSession(id: id, agent: agent, pid: nil, name: model ?? repository, folder: folder,
                                   place: ProjectPlace(repository: repository, root: folder),
                                   started: Date().addingTimeInterval(-120), state: state, stateSince: Date())
        session.calledBy = calledBy
        session.model = model
        return session
    }

    @Test func modelNamesReadLikePeopleSayThem() {
        #expect(ModelName.display("glm-5.3") == "GLM 5.3")
        #expect(ModelName.display("gpt-6-astra") == "GPT-6 Astra")
        #expect(ModelName.display("Mistral Medium 3.5") == "Mistral Medium 3.5")
        // Without Vibe's display names, its aliases read the same way.
        #expect(ModelName.display("mistral-medium-3.5") == "Mistral Medium 3.5")
        #expect(ModelName.display("devstral-medium") == "Devstral Medium")
        #expect(ModelName.display("Devstral Medium (25.12)") == "Devstral Medium")
        #expect(ModelName.display("GLM 5.3 · 1M context") == "GLM 5.3 · 1M context")
        #expect(ModelName.display("codestral") == "Codestral")
    }

    @Test func vibeModelNamesComeFromItsConfig() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "vibe-config-\(UUID().uuidString).toml")
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("""
        active_model = "glm-5.3"
        models = [
            { alias = "glm-5.3", name = "glm-5-3-fp8", provider = "mistral", display_name = "GLM 5.3", thinking = "high" },
            { alias = "devstral-medium", name = "devstral-medium-2512", display_name = "Devstral Medium (25.12)" },
            { alias = "plain", name = "plain-1" },
        ]
        """.utf8).write(to: file)
        #expect(VibeSource.modelNames(config: file) == ["glm-5.3": "GLM 5.3", "devstral-medium": "Devstral Medium (25.12)"])
        // As Vibe writes it after saving the config itself.
        try Data("""
        active_model = "glm-5.3"

        [[models]]
        alias = "mistral-medium-3.5"
        name = "mistral-medium-3-5"
        display_name = "Mistral Medium 3.5"
        thinking_levels = ["off", "high"]

        [[models]]
        alias = "codestral"
        name = "codestral-2508"

        [[providers]]
        name = "mistral"
        """.utf8).write(to: file)
        #expect(VibeSource.modelNames(config: file) == ["mistral-medium-3.5": "Mistral Medium 3.5"])
    }

    @Test func codexSaysWhichModelItRuns() {
        var log = CodexSource.LogState()
        log.consume(["timestamp": "2026-10-20T10:00:00.000Z", "type": "turn_context",
                     "payload": ["cwd": "/Users/me/code/x", "model": "gpt-6-astra", "effort": "high"]])
        #expect(log.model == "gpt-6-astra")
    }

    @Test func codexLogsAreRecognisedByPath() {
        let folder = CodexSource.sessionsFolder.path
        #expect(CodexSource.isLog("\(folder)/2026/10/20/rollout-2026-10-20T20-41-04-01a15a9d.jsonl"))
        #expect(!CodexSource.isLog("\(folder)/2026/10/20/history.jsonl"))
        #expect(!CodexSource.isLog("/tmp/rollout-x.jsonl"))
        #expect(ProcessScan.isScripted(.codex, arguments: ["codex", "--search", "exec", "-C", "/x", "-"]))
    }

    @Test func aProcessCanListItsOwnOpenFiles() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "open-\(UUID().uuidString).txt")
        try Data("x".utf8).write(to: file)
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close(); try? FileManager.default.removeItem(at: file) }
        let open = ProcessScan.openFiles(of: getpid()) { $0.hasSuffix(file.lastPathComponent) }
        #expect(open.count == 1)
    }

    @Test func helpersPerchOnTheirCallersTwig() {
        let caller = session("claude:c", .claude, "macos-menubar", .waitingOnHelpers)
        let helpers = (0..<3).map { session("vibe:\($0)", .vibe, "owl-playground", .running, calledBy: caller.id, model: "GLM 5.3") }
        let back = [session("codex:9", .codex, "owl-playground", .napping, calledBy: caller.id, model: "GPT-6 Astra")]
        let plan = TreePlan(sessions: [caller] + helpers, cameHome: back, size: CGSize(width: 1240, height: 700),
                            now: Date(), unit: 3, trim: false)
        // No branch of their own: they sit on a twig under the caller.
        #expect(plan.branches.map(\.repository).filter { !$0.isEmpty } == ["macos-menubar"])
        #expect(plan.twigs.count == 1)
        let group = plan.helpers.first
        #expect(group?.caller == caller.id)
        #expect(group?.working == 3)
        #expect(group?.back == 1)
        #expect(group?.place == "owl-playground")
        #expect(group?.flock.isEmpty == true)
        let callerPerch = plan.perches.first { $0.id == caller.id }
        let helperTops = plan.perches.filter { $0.session.isHelper }.map(\.top)
        #expect(helperTops.count == 3)
        #expect(helperTops.allSatisfy { $0 > (callerPerch?.top ?? 0) + plan.labelBottom })
        // The ones that came back went to their caller, not the nest.
        #expect(plan.nest.count == 0)
    }

    @Test func pastFiveTheRestHuddleAsAFlock() {
        let caller = session("claude:c", .claude, "barnowl", .waitingOnHelpers)
        let helpers = (0..<9).map { session("codex:\($0)", .codex, "barnowl", .thinking, calledBy: caller.id) }
        let plan = TreePlan(sessions: [caller] + helpers, cameHome: [], size: CGSize(width: 1240, height: 700),
                            now: Date(), unit: 3, trim: false)
        #expect(plan.perches.filter { $0.session.isHelper }.count == 4)
        #expect(plan.helpers.first?.flock.count == 5)
        #expect(plan.helpers.first?.place == nil)
    }

    @Test func helpersOfANappingCallerKeepTheirOwnBranch() {
        let caller = session("claude:c", .claude, "barnowl", .napping)
        let helper = session("vibe:1", .vibe, "owl-playground", .running, calledBy: caller.id, model: "GLM 5.3")
        let plan = TreePlan(sessions: [caller, helper], cameHome: [], size: CGSize(width: 1240, height: 700),
                            now: Date(), unit: 3, trim: false)
        #expect(plan.twigs.isEmpty)
        #expect(plan.branches.contains { $0.repository == "owl-playground" && !$0.bare })
    }

    @Test func theFlockSaysWhoItIs() {
        let helpers = [session("a", .codex, "x", .running), session("b", .codex, "x", .thinking),
                       session("c", .vibe, "x", .typing)]
        #expect(TreePlan.makeUp(helpers) == "2 Codex · 1 Vibe, working")
    }

    @Test func withNoRoomForATwigHelpersKeepTheirOwnBranch() {
        let caller = session("claude:c", .claude, "barnowl", .thinking)
        let helpers = (0..<3).map { session("vibe:\($0)", .vibe, "owl-playground", .running, calledBy: caller.id) }
        let plan = TreePlan(sessions: [caller] + helpers, cameHome: [], size: CGSize(width: 420, height: 700),
                            now: Date(), unit: 3, trim: false)
        #expect(plan.twigs.isEmpty)
        #expect(plan.perches.filter { $0.session.isHelper }.count + (plan.overflows.first?.sessions.count ?? 0) == 3)
        #expect(plan.branches.contains { $0.repository == "owl-playground" && !$0.bare })
    }

    @Test func twoCallersOnOneBranchStackTheirTwigs() {
        let left = session("claude:a", .claude, "barnowl", .thinking)
        let right = session("claude:b", .claude, "barnowl", .typing)
        let helpers = [session("vibe:1", .vibe, "barnowl", .running, calledBy: left.id),
                       session("vibe:2", .vibe, "barnowl", .running, calledBy: left.id),
                       session("codex:3", .codex, "barnowl", .running, calledBy: right.id)]
        let plan = TreePlan(sessions: [left, right] + helpers, cameHome: [], size: CGSize(width: 1600, height: 900),
                            now: Date(), unit: 3, trim: false)
        #expect(plan.twigs.count == 2)
        let x = Dictionary(uniqueKeysWithValues: plan.perches.map { ($0.id, $0.x) })
        let byCaller = Dictionary(uniqueKeysWithValues: plan.twigs.map { twig in
            ([left.id, right.id].min { abs((x[$0] ?? 0) - twig.x) < abs((x[$1] ?? 0) - twig.x) } ?? "", twig.y)
        })
        // The rightmost caller's twig is highest; the other's runs below it.
        let leftIsLeft = (x[left.id] ?? 0) < (x[right.id] ?? 0)
        let (outer, inner) = leftIsLeft ? (left.id, right.id) : (right.id, left.id)
        #expect((byCaller[outer] ?? 0) > (byCaller[inner] ?? 0))
    }

    @Test func whenAllAreBackTheTwigSaysSoForAWhile() {
        let caller = session("claude:c", .claude, "barnowl", .thinking)
        var back = [session("vibe:1", .vibe, "barnowl", .napping, calledBy: caller.id),
                    session("codex:2", .codex, "barnowl", .napping, calledBy: caller.id)]
        let plan = TreePlan(sessions: [caller], cameHome: back, size: CGSize(width: 1240, height: 700),
                            now: Date(), unit: 3, trim: false)
        #expect(plan.twigs.count == 1)
        #expect(plan.helpers.first?.back == 2)
        #expect(plan.helpers.first?.working == 0)
        for index in back.indices { back[index].stateSince = Date().addingTimeInterval(-3600) }
        let later = TreePlan(sessions: [caller], cameHome: back, size: CGSize(width: 1240, height: 700),
                             now: Date(), unit: 3, trim: false)
        #expect(later.twigs.isEmpty)
    }

    @Test func codexSubcommandSkipsOptionValues() {
        #expect(!ProcessScan.isScripted(.codex, arguments: ["codex", "-C", "exec"]))
        #expect(ProcessScan.isScripted(.codex, arguments: ["codex", "-c", "a=b", "-c", "c=d", "-c", "e=f", "exec", "-"]))
        #expect(!ProcessScan.isScripted(.codex, arguments: ["codex", "resume", "--last"]))
    }

    @Test func aProcessListsItsChildren() throws {
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/bin/sleep")
        child.arguments = ["5"]
        try child.run()
        defer { child.terminate() }
        #expect(ProcessScan.children(of: getpid()).contains(child.processIdentifier))
    }
}

