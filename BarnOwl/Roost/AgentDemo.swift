import Foundation

/// Made-up owlets for demo mode, for screenshots and trying the design
/// without real agents.
enum AgentDemo {
    static func limits(now: Date) -> [PlanLimit] {
        [PlanLimit(agent: .claude, window: .session, used: 38, resetsAt: now.addingTimeInterval(2.5 * 3600), updated: now),
         PlanLimit(agent: .claude, window: .week, used: 71, resetsAt: now.addingTimeInterval(3 * 24 * 3600), updated: now,
                   fullAt: now.addingTimeInterval(2 * 24 * 3600))]
    }

    static func sessions(now: Date) -> [AgentSession] {
        func session(_ id: String, _ agent: AgentKind, _ name: String, _ path: String, _ state: OwletState,
                     minutes: Double, detail: String? = nil, helpers: [AgentHelper] = [], host: String = "Terminal") -> AgentSession {
            let folder = URL(fileURLWithPath: path)
            return AgentSession(id: id, agent: agent, pid: nil, name: name, folder: folder, place: ProjectPlace.of(folder),
                                host: host, started: now.addingTimeInterval(-minutes * 60), state: state,
                                stateSince: now.addingTimeInterval(-60), detail: detail, helpers: helpers,
                                lastTurn: state == .done ? 47 * 60 : nil)
        }
        let started = now.addingTimeInterval(-90)
        return [
            session("demo:1", .claude, "Agents feature research", "/Users/demo/code/barnowl", .typing, minutes: 31,
                    helpers: [AgentHelper(id: "h1", type: "Explore", task: "Survey prior art", isWorking: true, started: started),
                              AgentHelper(id: "h2", type: "Plan", task: "Plan the owlet card", isWorking: true, started: started),
                              AgentHelper(id: "h3", type: "general-purpose", task: "Check the logs", isWorking: false,
                                          started: started)],
                    host: "the Claude app"),
            {
                var asking = session("demo:2", .claude, "Fix Perch tint on Space switch",
                                     "/Users/demo/code/barnowl/.claude/worktrees/tint-fix", .asking, minutes: 43,
                                     detail: "Has a question for you")
                asking.request = AgentRequest(kind: .question,
                                              text: "Which colour should the Perch follow when you switch Spaces?",
                                              options: ["Desktop picture", "Accent colour", "Ask each time"],
                                              since: now.addingTimeInterval(-18))
                return asking
            }(),
            {
                var pushing = session("demo:6", .claude, "Release notes", "/Users/demo/code/tk-app-2026", .needsYou,
                                      minutes: 12, detail: "Wants to run a command")
                pushing.request = AgentRequest(kind: .command, text: "git push origin main", since: now.addingTimeInterval(-250))
                return pushing
            }(),
            session("demo:3", .codex, "tk-app-2026", "/Users/demo/code/tk-app-2026", .running, minutes: 23, host: "iTerm2"),
            {
                var done = session("demo:4", .copilot, "dotfiles", "/Users/demo/code/dotfiles", .done, minutes: 50,
                                   detail: "Your turn · finished after 47 min · 4 files changed · tests pass")
                done.evidence = TurnEvidence(filesChanged: 4, testsRun: 2, testsFailed: 0)
                return done
            }(),
            // A brood: a session fanned out across many helpers.
            session("demo:7", .claude, "Sync engine rewrite", "/Users/demo/code/site", .waitingOnHelpers, minutes: 64,
                    detail: "Waiting for its helpers",
                    helpers: (0..<18).map { index in
                        AgentHelper(id: "b\(index)", type: "Explore", task: "Map module \(index + 1)", isWorking: index < 12,
                                    started: now.addingTimeInterval(-Double(index) * 40))
                    }),
            session("demo:8", .claude, "Flaky login test", "/Users/demo/code/site", .stuck, minutes: 9,
                    detail: "Stopped after 3 failed test runs"),
            {
                var shipped = session("demo:9", .claude, "Docs pass", "/Users/demo/code/docs", .shipped, minutes: 38,
                                      detail: "Opened a pull request")
                shipped.evidence = TurnEvidence(filesChanged: 7, testsRun: 0, testsFailed: 0)
                return shipped
            }(),
            {
                var napping = session("demo:10", .opencode, "Theme tokens", "/Users/demo/code/design-system", .napping,
                                      minutes: 95)
                napping.stateSince = now.addingTimeInterval(-25 * 60)
                return napping
            }(),
        ]
    }
}
