import Foundation
import Testing
@testable import BarnOwl

struct ClaudeSessionFileTests {
    @Test func parsesASessionFile() throws {
        let json = """
        {"pid":68803,"sessionId":"abc","cwd":"/Users/me/code/barnowl","startedAt":1792421305489,"kind":"interactive",
         "entrypoint":"claude-desktop","name":"Agents research","status":"busy","statusUpdatedAt":1792421700010,
         "peerFeatures":["notify_idle"],"messagingSocketPath":"/tmp/x.sock"}
        """
        let file = try #require(ClaudeSource.parse(Data(json.utf8)))
        #expect(file.pid == 68803)
        #expect(file.status == "busy")
        #expect(file.name == "Agents research")
        #expect(!file.isScripted)
        #expect(file.started.timeIntervalSince1970 > 1_792_000_000)
    }

    @Test func scriptedSessionsAreMarked() throws {
        let json = #"{"pid":1,"sessionId":"a","cwd":"/x","kind":"print","entrypoint":"sdk-cli"}"#
        #expect(try #require(ClaudeSource.parse(Data(json.utf8))).isScripted)
    }

    @Test func projectFolderNameReplacesEverythingButLettersAndDigits() {
        #expect(ClaudeSource.projectFolderName(for: "/Users/me/code/priv/macos-menubar")
                == "-Users-me-code-priv-macos-menubar")
        #expect(ClaudeSource.projectFolderName(for: "/a/b.c d_e") == "-a-b-c-d-e")
    }

    @Test func keyFilesAreNeverListed() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data("{}".utf8).write(to: folder.appending(path: "12.json"))
        try Data("secret".utf8).write(to: folder.appending(path: "12.abcdef.key"))
        #expect(ClaudeSource.sessionFiles(in: folder).map(\.lastPathComponent) == ["12.json"])
    }
}

struct ClaudeLogTests {
    /// Shortly after the times in these logs.
    private let soon = ClaudeSource.LogState.date(from: "2026-10-19T10:05:00.000Z")!

    private func line(_ object: [String: Any]) -> Substring {
        let data = try! JSONSerialization.data(withJSONObject: object)
        return Substring(String(decoding: data, as: UTF8.self))
    }

    private func toolUse(_ id: String, _ name: String, command: String? = nil, at time: String = "2026-10-19T10:00:00.000Z")
        -> Substring {
        var part: [String: Any] = ["type": "tool_use", "id": id, "name": name]
        if let command { part["input"] = ["command": command] }
        return line(["type": "assistant", "timestamp": time, "gitBranch": "main",
                     "message": ["content": [part], "stop_reason": "tool_use"]])
    }

    private func result(_ id: String, failed: Bool) -> Substring {
        line(["type": "user", "message": ["role": "user",
              "content": [["type": "tool_result", "tool_use_id": id, "is_error": failed, "content": "…"]]]])
    }

    private func prompt(at time: String) -> Substring {
        line(["type": "user", "timestamp": time, "message": ["role": "user", "content": "do the thing"]])
    }

    private func endTurn(at time: String) -> Substring {
        line(["type": "assistant", "timestamp": time,
              "message": ["content": [["type": "text", "text": "done"]], "stop_reason": "end_turn"]])
    }

    private func file(status: String, waitingFor: String? = nil) -> ClaudeSource.SessionFile {
        ClaudeSource.SessionFile(pid: 1, sessionId: "s", cwd: "/x", startedAt: nil, kind: "interactive",
                                 entrypoint: "cli", name: nil, status: status, waitingFor: waitingFor,
                                 statusUpdatedAt: nil, procStart: nil)
    }

    @Test func pendingToolPicksThePose() {
        var log = ClaudeSource.LogState()
        log.consume(toolUse("1", "Edit"))
        #expect(ClaudeSource.state(file: file(status: "busy"), log: log, helpers: [], now: soon).state == .typing)
        log.consume(result("1", failed: false))
        log.consume(toolUse("2", "Grep"))
        #expect(ClaudeSource.state(file: file(status: "busy"), log: log, helpers: [], now: soon).state == .searching)
        #expect(log.branch == "main")
    }

    @Test func waitingIsNeedsYouAndQuestionsAreAsking() {
        var log = ClaudeSource.LogState()
        log.consume(toolUse("1", "Bash", command: "rm -rf build"))
        let waiting = ClaudeSource.state(file: file(status: "waiting", waitingFor: "permission prompt"), log: log,
                                         helpers: [], now: soon)
        #expect(waiting.state == .needsYou)
        #expect(waiting.detail == "Wants to run a command")
        var asking = ClaudeSource.LogState()
        asking.consume(toolUse("2", "AskUserQuestion"))
        #expect(ClaudeSource.state(file: file(status: "waiting", waitingFor: "input needed"), log: asking, helpers: [],
                                   now: soon).state == .asking)
    }

    @Test func oneOrTwoFailuresAreNormalThreeIsStuck() {
        var log = ClaudeSource.LogState()
        for id in ["1", "2"] {
            log.consume(toolUse(id, "Bash", command: "swift test"))
            log.consume(result(id, failed: true))
        }
        #expect(ClaudeSource.state(file: file(status: "idle"), log: log, helpers: [], now: soon).state != .stuck)
        log.consume(toolUse("3", "Bash", command: "swift test"))
        log.consume(result("3", failed: true))
        let stuck = ClaudeSource.state(file: file(status: "idle"), log: log, helpers: [], now: soon)
        #expect(stuck.state == .stuck)
        #expect(stuck.detail == "Stopped after 3 failed test runs")
        #expect(ClaudeSource.state(file: file(status: "busy"), log: log, helpers: [], now: soon).state == .fixing)
        // A success clears it.
        log.consume(toolUse("4", "Bash", command: "swift test"))
        log.consume(result("4", failed: false))
        #expect(log.failures == 0)
    }

    @Test func failuresOfOtherToolsDontCount() {
        var log = ClaudeSource.LogState()
        for id in ["1", "2", "3"] {
            log.consume(toolUse(id, "Read"))
            log.consume(result(id, failed: true))
        }
        #expect(log.failures == 0)
    }

    @Test func aLongTurnEndsAsYourTurn() {
        var log = ClaudeSource.LogState()
        log.consume(prompt(at: "2026-10-19T10:00:00.000Z"))
        log.consume(endTurn(at: "2026-10-19T10:47:00.000Z"))
        let now = ClaudeSource.LogState.date(from: "2026-10-19T10:48:00.000Z")!
        let done = ClaudeSource.state(file: file(status: "idle"), log: log, helpers: [], now: now)
        #expect(done.state == .done)
        #expect(done.detail == "Your turn · finished after 47 min")
        // A short turn just rests.
        var short = ClaudeSource.LogState()
        short.consume(prompt(at: "2026-10-19T10:00:00.000Z"))
        short.consume(endTurn(at: "2026-10-19T10:00:30.000Z"))
        let shortly = ClaudeSource.LogState.date(from: "2026-10-19T10:01:00.000Z")!
        #expect(ClaudeSource.state(file: file(status: "idle"), log: short, helpers: [], now: shortly).state == .resting)
        // Idle for over ten minutes, it naps.
        #expect(ClaudeSource.state(file: file(status: "idle"), log: short, helpers: [], now: now).state == .napping)
    }

    @Test func rateLimitIsATeaBreak() {
        var log = ClaudeSource.LogState()
        log.consume(line(["type": "assistant", "timestamp": "2026-10-19T10:00:00.000Z", "isApiErrorMessage": true,
                          "error": "rate_limit", "message": ["content": [], "stop_reason": "stop_sequence"]]))
        let now = ClaudeSource.LogState.date(from: "2026-10-19T10:01:00.000Z")!
        #expect(ClaudeSource.state(file: file(status: "busy"), log: log, helpers: [], now: now).state == .teaBreak)
    }

    @Test func hugeLinesAreScannedNotDecoded() {
        var log = ClaudeSource.LogState()
        log.consume(toolUse("big", "Bash", command: "make"))
        let padding = String(repeating: "x", count: 300_000)
        let huge = #"{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"big","is_error":true,"content":""#
            + padding + #""}]}}"#
        log.consume(Substring(huge))
        #expect(log.failures == 1)
        #expect(log.pending.isEmpty)
    }

    @Test func hugeLinesFindTheErrorFlagAtEitherEnd() {
        var log = ClaudeSource.LogState()
        log.consume(toolUse("big", "Bash", command: "make"))
        let padding = String(repeating: "x", count: 300_000)
        let huge = #"{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"big","content":""#
            + padding + #"","is_error":true}]}}"#
        log.consume(Substring(huge))
        #expect(log.failures == 1)
    }

    @Test func aBusySessionSilentForHoursIsNotWorking() {
        var log = ClaudeSource.LogState()
        log.consume(toolUse("1", "Bash", command: "sleep 9999", at: "2026-10-19T08:00:00.000Z"))
        let later = ClaudeSource.LogState.date(from: "2026-10-19T11:00:00.000Z")!
        // A command still running (a long build) is work, however quiet.
        #expect(ClaudeSource.state(file: file(status: "busy"), log: log, helpers: [], now: later).state == .running)
        let halfHour = ClaudeSource.LogState.date(from: "2026-10-19T08:30:00.000Z")!
        #expect(ClaudeSource.state(file: file(status: "busy"), log: log, helpers: [], now: halfHour).state == .running)
        // Nothing running and nothing logged for hours: left behind.
        var quiet = ClaudeSource.LogState()
        quiet.consume(["type": "user", "message": ["role": "user", "content": "Go"], "timestamp": "2026-10-19T08:00:00.000Z"])
        #expect(ClaudeSource.state(file: file(status: "busy"), log: quiet, helpers: [], now: later).state == .napping)
    }

    @Test func aNewTurnForgetsTheLastTool() {
        var log = ClaudeSource.LogState()
        log.consume(toolUse("1", "Edit"))
        log.consume(result("1", failed: false))
        log.consume(endTurn(at: "2026-10-19T10:01:00.000Z"))
        log.consume(prompt(at: "2026-10-19T10:02:00.000Z"))
        #expect(ClaudeSource.state(file: file(status: "busy"), log: log, helpers: [], now: soon).state == .thinking)
    }

    @Test func compactSummariesDontStartATurn() {
        var log = ClaudeSource.LogState()
        log.consume(prompt(at: "2026-10-19T10:00:00.000Z"))
        log.consume(line(["type": "user", "isCompactSummary": true, "timestamp": "2026-10-19T10:30:00.000Z",
                          "message": ["role": "user", "content": "summary"]]))
        #expect(log.turnStarted == ClaudeSource.LogState.date(from: "2026-10-19T10:00:00.000Z"))
    }

    @Test func procStartIsReadAsUTC() {
        let date = ClaudeSource.procStartDate("Mon Oct  9 14:48:25 2026")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        #expect(date.map { calendar.component(.hour, from: $0) } == 14)
        #expect(date.map { calendar.component(.day, from: $0) } == 9)
    }

    @Test func aSessionWhoseProcessIsGoneIsNotLive() {
        var dead = file(status: "busy")
        dead.pid = 99_999_999
        #expect(!ClaudeSource.isLive(dead))
        // Our own process is live, but a recorded start that doesn't match it means a reused PID.
        var reused = file(status: "busy")
        reused.pid = getpid()
        reused.procStart = "Thu Jan  1 00:00:00 2015"
        #expect(!ClaudeSource.isLive(reused))
    }

    @Test func subagentRecordsAreIgnoredInTheMainLog() {
        var log = ClaudeSource.LogState()
        log.consume(line(["type": "assistant", "isSidechain": true,
                          "message": ["content": [["type": "tool_use", "id": "x", "name": "Edit"]]]]))
        #expect(log.lastTool == nil)
    }
}

struct CodexLogTests {
    private func event(_ type: String, _ payload: [String: Any] = [:]) -> [String: Any] {
        ["type": "event_msg", "timestamp": "2026-10-19T10:00:00.000Z", "payload": payload.merging(["type": type]) { a, _ in a }]
    }

    @Test func turnsAndTools() {
        var log = CodexSource.LogState()
        log.consume(event("task_started"))
        log.consume(["type": "response_item", "payload": ["type": "custom_tool_call", "name": "exec"]])
        #expect(log.state(now: Date()).state == .running)
        log.consume(event("task_complete", ["duration_ms": 600_000.0]))
        let now = ClaudeSource.LogState.date(from: "2026-10-19T10:05:00.000Z")!
        let done = log.state(now: now)
        #expect(done.state == .done)
        #expect(done.detail == "Your turn · finished after 10 min")
    }

    @Test func failedCommandsAndRateLimits() {
        var log = CodexSource.LogState()
        log.consume(event("task_started"))
        for _ in 0..<3 {
            log.consume(event("item_completed", ["item": ["type": "CommandExecution", "exit_code": 1]]))
        }
        #expect(log.state(now: Date()).state == .fixing)
        log.consume(event("token_count", ["rate_limits": ["rate_limit_reached_type": "primary"]]))
        let hit = log.rateLimitedAt ?? Date()
        #expect(log.state(now: hit).state == .teaBreak)
        // With no reset time given, the pause is let go after a quarter of an hour.
        #expect(log.state(now: hit.addingTimeInterval(16 * 60)).state != .teaBreak)
        log.consume(event("token_count", ["rate_limits": ["rate_limit_reached_type": NSNull()]]))
        #expect(log.state(now: Date()).state != .teaBreak)
    }
}

struct ProcessScanTests {
    private func found(_ pid: Int32, _ agent: AgentKind) -> ProcessScan.Found {
        ProcessScan.Found(pid: pid, agent: agent, folder: "/x", started: Date(), cpu: 0)
    }

    @Test func onlyTheOutermostProcessOfAnAgentCounts() {
        // A node wrapper (10) runs the native codex (11), which runs a helper (12).
        let parents: [Int32: Int32] = [10: 1, 11: 10, 12: 11, 20: 1]
        let matches = [(found: found(12, .codex), parent: Int32(11)), (found: found(11, .codex), parent: Int32(10)),
                       (found: found(10, .codex), parent: Int32(1)), (found: found(20, .codex), parent: Int32(1))]
        let kept = ProcessScan.outermost(matches) { parents[$0] }
        #expect(Set(kept.map(\.pid)) == [10, 20])
    }

    @Test func scriptAgentsByWhatTheyRun() {
        #expect(ProcessScan.scriptAgent(arguments: ["node", "/opt/homebrew/lib/node_modules/@github/copilot/index.js"]) == .copilot)
        #expect(ProcessScan.scriptAgent(arguments: ["node", "/usr/local/bin/gemini"]) == .gemini)
        #expect(ProcessScan.scriptAgent(arguments: ["node", "server.js"]) == nil)
    }
}

struct ProjectPlaceTests {
    @Test func claudeWorktreesBelongToTheirRepository() {
        let place = ProjectPlace.of(URL(fileURLWithPath: "/Users/me/code/barnowl/.claude/worktrees/tint-fix"))
        #expect(place.repository == "barnowl")
        #expect(place.worktree == "tint-fix")
        #expect(place.root.path == "/Users/me/code/barnowl")
    }

    @Test func gitWorktreeFilesPointAtTheMainRepository() {
        let main = ProjectPlace.mainRepository(fromGitFileText: "gitdir: /Users/me/code/barnowl/.git/worktrees/docs\n")
        #expect(main?.path == "/Users/me/code/barnowl")
        #expect(ProjectPlace.mainRepository(fromGitFileText: "gitdir: /elsewhere") == nil)
    }

    @Test func aRepositoryIsFoundFromASubfolder() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "roost-\(UUID().uuidString)")
        let sub = root.appending(path: "Sources/App")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appending(path: ".git"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let place = ProjectPlace.of(sub)
        #expect(place.repository == root.lastPathComponent)
        #expect(place.worktree == nil)
    }
}

struct OwletStateTests {
    @Test func commandsAreSortedWithoutKeepingThem() {
        #expect(CommandKind.of("xcodebuild test -scheme BarnOwl") == .test)
        #expect(CommandKind.of("npm test") == .test)
        #expect(CommandKind.of("pytest -q") == .test)
        #expect(CommandKind.of("xcodebuild -scheme BarnOwl build") == .build)
        #expect(CommandKind.of("git push") == .git)
        #expect(CommandKind.of("ls -la") == .other)
    }

    @Test func everyStateHasArt() {
        for state in OwletState.allCases {
            #expect(OwletArt.states[state.sprite] != nil, "no sprite for \(state)")
            #expect(OwletArt.icons[state.icon] != nil, "no icon for \(state)")
        }
        for name in ["typing", "needs", "error", "done", "nap"] {
            #expect(OwletArt.templates[name] != nil)
        }
    }

    @Test func artFramesAreWholeAndUseKnownColours() {
        let keys = Set(OwletArt.palettes["golden"]?.keys.map { $0 } ?? []).union(["."])
        for (name, art) in OwletArt.states {
            #expect(!art.frames.isEmpty, "\(name) has no frames")
            for frame in art.frames {
                #expect(frame.count == OwletArt.width * OwletArt.height, "\(name) frame size")
                #expect(Set(frame).isSubset(of: keys), "\(name) uses an unknown colour")
            }
        }
        for palette in OwletArt.palettes.values {
            #expect(Set(palette.keys) == Set(OwletArt.palettes["golden"]?.keys.map { $0 } ?? []))
        }
    }

    @Test func needsYouSortsFirst() {
        #expect(OwletState.needsYou.rank < OwletState.typing.rank)
        #expect(OwletState.typing.rank < OwletState.resting.rank)
    }

    @Test func agentWorkingRule() {
        var snapshot = ConditionSnapshot()
        #expect(!RuleCondition.agentWorking.holds(in: snapshot))
        snapshot.agentWorking = true
        #expect(RuleCondition.agentWorking.holds(in: snapshot))
        #expect(KeepAwakeRule.presets.contains { $0.conditions == [.agentWorking] })
    }
}

@MainActor
struct AgentChoicesTests {
    private func session(state: OwletState, scripted: Bool = false, path: String = "/Users/me/code/barnowl")
        -> AgentSession {
        let folder = URL(fileURLWithPath: path)
        return AgentSession(id: "claude:1", agent: .claude, pid: 1, name: "x", folder: folder,
                            place: ProjectPlace(repository: "barnowl", worktree: nil, root: folder), started: Date(),
                            state: state, stateSince: Date(), isScripted: scripted)
    }

    private func choices() -> AgentChoices {
        Preferences.registerDefaults()
        return AgentChoices(defaults: UserDefaults(suiteName: "roost-tests-\(UUID().uuidString)")!)
    }

    @Test func hiddenUntilNeededComesBackWhenItNeedsYou() {
        let choices = choices()
        choices.hide(session(state: .typing), for: .untilNeeded)
        #expect(choices.isHidden(session(state: .typing)))
        #expect(!choices.isHidden(session(state: .needsYou)))
    }

    @Test func hiddenFolderStillShowsWhenItNeedsYou() {
        let choices = choices()
        choices.hideFolder(of: session(state: .typing))
        #expect(choices.isHidden(session(state: .typing)))
        #expect(!choices.isHidden(session(state: .asking)))
    }

    @Test func scratchFolders() {
        #expect(AgentChoices.isScratch(URL(fileURLWithPath: "/private/tmp/x")))
        #expect(AgentChoices.isScratch(URL(fileURLWithPath: "/private/tmp")))
        #expect(AgentChoices.isScratch(URL(fileURLWithPath: "/var/folders/ab/T/x")))
        #expect(!AgentChoices.isScratch(URL(fileURLWithPath: "/private/tmpfiles")))
        #expect(AgentChoices.isScratch(URL(fileURLWithPath:
            "/Users/me/Library/Application Support/Claude/scratch-workspaces/abc")))
        #expect(!AgentChoices.isScratch(URL(fileURLWithPath: "/Users/me/code/barnowl")))
    }

    @Test func onceItNeededYouItStaysInView() {
        let choices = choices()
        choices.hide(session(state: .typing), for: .untilNeeded)
        choices.cameBack(session(state: .needsYou))
        #expect(!choices.isHidden(session(state: .typing)))
    }

    @Test func mutedAndHiddenForTodayDontNotify() {
        let today = choices()
        #expect(today.mayNotify(session(state: .needsYou)))
        today.hide(session(state: .typing), for: .today)
        #expect(!today.mayNotify(session(state: .needsYou)))
        let muted = choices()
        muted.setMuted(true, folder: "/Users/me/code/barnowl")
        #expect(!muted.mayNotify(session(state: .needsYou)))
        #expect(!choices().mayNotify(session(state: .needsYou, scripted: true)))
    }

    @Test func revealShowsEverything() {
        let choices = choices()
        choices.hide(session(state: .typing), for: .today)
        choices.revealHidden = true
        #expect(!choices.isHidden(session(state: .typing)))
    }
}

struct ScanSettlingTests {
    @Test func burstsWaitForQuietButNotForever() {
        #expect(ItemScanner.settleDelay(sinceFirstChange: 0) == 1.5)
        #expect(ItemScanner.settleDelay(sinceFirstChange: 9) == 1)
        #expect(ItemScanner.settleDelay(sinceFirstChange: 30) == 0)
    }
}

struct PlanLimitTests {
    private func history(_ samples: [(Double, String, [String: Double])]) -> Data {
        let list = samples.map { ["t": $0.0 * 1000, "org": $0.1, "u": $0.2] as [String: Any] }
        return try! JSONSerialization.data(withJSONObject: ["version": 2, "samples": list])
    }

    @Test func readsTheLatestOrganisationsWindows() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let data = history([(990_000, "a", ["fh": 10, "sd": 20]), (995_000, "b", ["fh": 0, "sd": 40]),
                            (999_000, "a", ["xu": 0.1]), (999_500, "b", ["fh": 30, "sd": 45])])
        let samples = PlanLimits.claudeSamples(from: data)
        #expect(samples.count == 2) // org b only, extra-usage samples skipped
        let limits = PlanLimits.claudeLimits(from: samples, now: now)
        #expect(limits.first { $0.window == .week }?.used == 45)
        #expect(limits.first { $0.window == .session }?.used == 30)
    }

    @Test func anAfternoonsWeekReadingStillShowsAtNightMarkedOld() throws {
        let now = Date()
        let samples = [PlanLimits.Sample(time: now.addingTimeInterval(-6.5 * 3600), session: 20, week: 43)]
        let limits = PlanLimits.claudeLimits(from: samples, now: now)
        let week = try #require(limits.first)
        #expect(limits.count == 1 && week.window == .week && week.used == 43)
        #expect(week.isStale(now: now))
    }

    @Test func staleHistoryShowsNothing() {
        let samples = [PlanLimits.Sample(time: Date(timeIntervalSince1970: 0), session: 10, week: 10)]
        #expect(PlanLimits.claudeLimits(from: samples, now: Date()).isEmpty)
    }

    @Test func forecastFollowsTheRecentPace() {
        let now = Date(timeIntervalSince1970: 100_000)
        // 10 points an hour, at 60% now: full in four hours.
        let points = [(now.addingTimeInterval(-7200), 40.0), (now.addingTimeInterval(-3600), 50.0), (now, 60.0)]
        let eta = PlanLimits.forecast(points, now: now)
        #expect(eta.map { abs($0.timeIntervalSince(now) - 4 * 3600) < 60 } == true)
        // Falling or flat: no forecast.
        #expect(PlanLimits.forecast([(now.addingTimeInterval(-7200), 60.0), (now.addingTimeInterval(-3600), 60.0), (now, 60.0)], now: now) == nil)
    }

    @Test func codexWindows() {
        let time = Date(timeIntervalSince1970: 1000)
        let session = CodexSource.limit(["used_percent": 38, "window_minutes": 300, "resets_at": 5000], at: time)
        #expect(session?.window == .session)
        #expect(session?.resetsAt == Date(timeIntervalSince1970: 5000))
        let week = CodexSource.limit(["used_percent": 71, "window_minutes": 10080, "resets_in_seconds": 600], at: time)
        #expect(week?.window == .week)
        #expect(week?.resetsAt == time.addingTimeInterval(600))
        #expect(CodexSource.limit(NSNull(), at: time) == nil)
    }

    @Test func limitsNameTheirOwnerAndPlan() {
        var log = CodexSource.LogState()
        log.consume(["timestamp": "2026-10-20T10:00:00.000Z", "type": "event_msg",
                     "payload": ["type": "token_count", "rate_limits": [
                        "plan_type": "plus", "rate_limit_reached_type": NSNull(),
                        "primary": ["used_percent": 38, "window_minutes": 300, "resets_at": 1_792_500_000]]]])
        #expect(log.limits.first?.owner == "Codex Plus")
        #expect(CodexSource.plan(NSNull()) == nil)
        #expect(CodexSource.plan("../x") == nil)
        let claude = PlanLimit(agent: .claude, window: .week, used: 71, updated: Date())
        #expect(claude.owner == "Claude")
    }

    @Test func relayKeepsOnlyTheLimits() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "relay-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let status: [String: Any] = ["session_id": "s", "cwd": "/secret/project", "model": ["id": "x"],
                                     "rate_limits": ["five_hour": ["used_percentage": 23.5, "resets_at": 2_000_000_000],
                                                     "seven_day": ["used_percentage": 41.2, "resets_at": 2_000_100_000]]]
        StatusLineRelay.saveLimits(from: try JSONSerialization.data(withJSONObject: status), now: Date(), to: file)
        let saved = try String(contentsOf: file, encoding: .utf8)
        #expect(!saved.contains("secret") && !saved.contains("session_id"))
        let limits = PlanLimits.relayLimits(from: try Data(contentsOf: file), now: Date())
        #expect(limits.first { $0.window == .session }?.used == 23.5)
        #expect(limits.first { $0.window == .week }?.resetsAt == Date(timeIntervalSince1970: 2_000_100_000))
    }

    @Test func theRelayKeepsYourStatusLineSettings() {
        let line = StatusLineRelay.relayLine(replacing: ["type": "command", "command": "~/bin/line", "padding": 2],
                                             binary: "/Applications/Barn Owl.app/Contents/MacOS/Barn Owl")
        #expect(line["padding"] as? Int == 2)
        let command = line["command"] as? String ?? ""
        #expect(StatusLineRelay.isRelay(command))
        #expect(!StatusLineRelay.isRelay("~/bin/line"))
        // If Barn Owl is gone, the command still runs your own status line.
        #expect(command.hasSuffix("; ~/bin/line"))
        #expect(command.contains("-- '~/bin/line'"))
    }

    @Test func quotingSurvivesQuotes() {
        #expect(StatusLineRelay.shellQuoted("it's") == "'it'\\''s'")
    }

    @Test func turningTheRelayOnAndOffPutsEverythingBack() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "relay-\(UUID().uuidString)")
        let real = folder.appending(path: "dotfiles/settings.json")
        let link = folder.appending(path: "claude/settings.json")
        try FileManager.default.createDirectory(at: real.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let original = #"{"model":"opus","statusLine":{"type":"command","command":"~/bin/line","padding":1},"zzz":[1,2]}"#
        try Data(original.utf8).write(to: real)
        try FileManager.default.setAttributes([.posixPermissions: 0o640], ofItemAtPath: real.path)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        let files = StatusLineRelay.Files(settings: link, support: folder.appending(path: "support"))
        let binary = "/Applications/Barn Owl.app/Contents/MacOS/Barn Owl"

        try StatusLineRelay.turnOn(files: files, binary: binary)
        #expect(StatusLineRelay.isOn(files: files))
        try StatusLineRelay.turnOn(files: files, binary: binary) // twice changes nothing
        // The link is still a link, and the real file kept its permissions and other settings.
        #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: link.path)) != nil)
        #expect(((try FileManager.default.attributesOfItem(atPath: real.path))[.posixPermissions] as? NSNumber)?.intValue == 0o640)
        let on = try JSONSerialization.jsonObject(with: Data(contentsOf: real)) as? [String: Any]
        #expect(on?["model"] as? String == "opus")
        #expect(on?["zzz"] != nil)

        try StatusLineRelay.turnOff(files: files)
        #expect(!StatusLineRelay.isOn(files: files))
        let off = try JSONSerialization.jsonObject(with: Data(contentsOf: real)) as? [String: Any]
        let line = off?["statusLine"] as? [String: Any]
        #expect(line?["command"] as? String == "~/bin/line")
        #expect(line?["padding"] as? Int == 1)
    }

    @Test func turningOffWithoutTheSavedCopyUsesTheBackup() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "relay-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let settings = folder.appending(path: "settings.json")
        try Data(#"{"statusLine":{"type":"command","command":"mine"}}"#.utf8).write(to: settings)
        let files = StatusLineRelay.Files(settings: settings, support: folder.appending(path: "support"))
        try StatusLineRelay.turnOn(files: files, binary: "/Applications/Barn Owl.app/Contents/MacOS/Barn Owl")
        try FileManager.default.removeItem(at: files.original) // an app cleaner took it
        try StatusLineRelay.turnOff(files: files)
        let off = try JSONSerialization.jsonObject(with: Data(contentsOf: settings)) as? [String: Any]
        #expect((off?["statusLine"] as? [String: Any])?["command"] as? String == "mine")
    }
}

struct FlightLogTests {
    private func session(_ id: String, _ state: OwletState) -> AgentSession {
        let folder = URL(fileURLWithPath: "/x/\(id)")
        return AgentSession(id: id, agent: .claude, pid: nil, name: id, folder: folder,
                            place: ProjectPlace(repository: id, worktree: nil, root: folder), started: Date(),
                            state: state, stateSince: Date())
    }

    @Test func segmentsCarryOnAndAddUp() {
        var log = FlightLog()
        // Midday, so the ten minutes below never cross into a new day.
        let start = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: Date()) ?? Date()
        log.record([session("a", .typing), session("b", .needsYou)], now: start)
        log.record([session("a", .running), session("b", .needsYou)], now: start.addingTimeInterval(30))
        log.record([session("a", .typing)], now: start.addingTimeInterval(60))
        #expect(log.total(.working) == 60)
        #expect(log.total(.waiting) == 30)
        #expect(log.peak == 1)
        #expect(log.repositories == ["a", "b"])
        // A long gap starts a new segment.
        log.record([session("a", .typing)], now: start.addingTimeInterval(600))
        #expect(log.segments.filter { $0.session == "a" }.count == 2)
    }
}

@MainActor
struct IslandTests {
    private func session(_ id: String, _ state: OwletState, since: TimeInterval = 0) -> AgentSession {
        let folder = URL(fileURLWithPath: "/x/\(id)")
        return AgentSession(id: id, agent: .claude, pid: nil, name: id, folder: folder,
                            place: ProjectPlace(repository: id, worktree: nil, root: folder), started: Date(),
                            state: state, stateSince: Date().addingTimeInterval(-since))
    }

    @Test func showsWhatNeedsYouAndBrieflyWhatsDone() {
        let sessions = [session("a", .typing), session("b", .needsYou), session("c", .done, since: 2),
                        session("d", .done, since: 30)]
        let attention = IslandController.items(from: sessions, mode: .attention, now: Date())
        #expect(attention.map(\.id) == ["b", "c"])
        #expect(IslandController.items(from: sessions, mode: .always, now: Date()).map(\.id) == ["a", "b", "c"])
        #expect(IslandController.items(from: sessions, mode: .off, now: Date()).isEmpty)
    }
}

struct MoonTests {
    @Test func knownPhases() {
        // Full moon on 3 January 2026 at 10:03 UTC; new moon on 18 January 2026 at 19:52 UTC.
        let full = MoonPhase.fraction(at: Date(timeIntervalSince1970: 1767434580))
        #expect(abs(full - 0.5) < 0.08)
        let new = MoonPhase.fraction(at: Date(timeIntervalSince1970: 1_768_765_920))
        #expect(new < 0.05 || new > 0.95)
    }
}

struct ClaudeAppChatTests {
    @Test func readsTheIDsAndTitleFromARecordsStart() throws {
        let head = Data(#"{"sessionId":"local_69772db8-a0c1","cliSessionId":"577d92eb-04bb","cwd":"/x","title":"Fix the \"Perch\"","model":"#.utf8)
        let parsed = try #require(ClaudeAppChats.parse(head: head))
        #expect(parsed.cliSession == "577d92eb-04bb")
        #expect(parsed.chat == .init(id: "local_69772db8-a0c1", title: #"Fix the "Perch""#))
    }

    @Test func ignoresRecordsThatAreNotTheAppsOwn() {
        #expect(ClaudeAppChats.parse(head: Data(#"{"sessionId":"cse_1","cliSessionId":"a"}"#.utf8)) == nil)
        #expect(ClaudeAppChats.parse(head: Data(#"{"sessionId":"local_1"}"#.utf8)) == nil)
    }

    @Test func linksOnlyToWellFormedChatIDs() {
        #expect(ClaudeAppChats.link(to: "local_69772db8-a0c1")?.absoluteString == "claude://code/continue?session=local_69772db8-a0c1")
        #expect(ClaudeAppChats.link(to: "local_x&source=evil") == nil)
        #expect(ClaudeAppChats.link(to: "577d92eb") == nil)
    }

    @Test func findsRecordsTwoFoldersDown() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let folder = root.appendingPathComponent("account/org")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("{}".utf8).write(to: folder.appendingPathComponent("local_a.json"))
        try Data("{}".utf8).write(to: folder.appendingPathComponent("other.json"))
        #expect(ClaudeAppChats.records(in: root).map(\.lastPathComponent) == ["local_a.json"])
    }
}

struct RoostSnapshotTests {
    @Test func savesAndLoadsThroughAFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "/roost.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let now = Date(timeIntervalSince1970: 1_792_000_000)
        let snapshot = RoostSnapshot(updated: now, owlets: [.init(
            id: "claude:1", name: "Fix", place: "barnowl", palette: "golden", sprite: "ask", icon: "ask", label: "Asking you",
            needsYou: true, working: false, request: "Ship it?", since: now)], workedToday: 3600)
        snapshot.save(to: url)
        #expect(RoostSnapshot.load(from: url) == snapshot)
    }

    @Test func aChangingClockAloneDoesNotCountAsAChange() {
        let now = Date()
        var later = RoostSnapshot(updated: now, workedToday: 3600)
        later.updated = now.addingTimeInterval(300)
        later.workedToday = 3700
        #expect(later.looksLike(RoostSnapshot(updated: now, workedToday: 3600)))
        later.owlets = [.init(id: "a", name: "A", place: "a", palette: "golden", sprite: "nap", icon: "nap", label: "",
                              needsYou: false, working: false, since: now)]
        #expect(!later.looksLike(RoostSnapshot(updated: now, workedToday: 3600)))
    }

    @Test func goesStaleWhenOldOrStopped() {
        let now = Date()
        #expect(!RoostSnapshot(updated: now).isStale(at: now.addingTimeInterval(60)))
        #expect(RoostSnapshot(updated: now).isStale(at: now.addingTimeInterval(RoostSnapshot.freshFor + 1)))
        #expect(RoostSnapshot(updated: now, running: false).isStale(at: now))
    }

    @MainActor @Test func carriesTheRequestOnlyWhileItWaits() {
        let now = Date()
        let sessions = AgentDemo.sessions(now: now)
        let snapshot = WidgetFeed.snapshot(sessions: sessions, limits: AgentDemo.limits(now: now), worked: 0, now: now)
        #expect(snapshot.owlets.first?.needsYou == true)
        #expect(snapshot.owlets.filter { $0.request != nil }.allSatisfy { $0.needsYou })
        // Each limit says whose it is: Claude's plan isn't Vibe's or Codex's.
        #expect(snapshot.limits.map(\.title).contains("Claude week"))
    }
}

struct IslandAnswerTests {
    nonisolated(unsafe) static let permission: [String: Any] = [
        "session_id": "s1", "hook_event_name": "PermissionRequest", "tool_name": "Bash",
        "tool_input": ["command": "git push origin main", "description": "Push"],
    ]
    nonisolated(unsafe) static let question: [String: Any] = [
        "session_id": "s1", "hook_event_name": "PreToolUse", "tool_name": "AskUserQuestion",
        "tool_input": ["questions": [["question": "Which colour?", "header": "Colour", "multiSelect": false,
                                      "options": [["label": "Desktop", "description": ""], ["label": "Accent", "description": ""]]]]],
    ]

    @Test func readsAPermissionRequestAndAQuestion() throws {
        let ask = try #require(IslandAnswers.ask(from: Self.permission))
        #expect(ask.kind == .permission && ask.text == "git push origin main" && ask.session == "s1")
        let question = try #require(IslandAnswers.ask(from: Self.question))
        #expect(question.kind == .question && question.text == "Which colour?" && question.options == ["Desktop", "Accent"])
    }

    @Test func leavesMultiSelectAndSeveralQuestionsToThePrompt() {
        var multi = Self.question
        multi["tool_input"] = ["questions": [["question": "Q", "multiSelect": true, "options": [["label": "A"]]]]]
        #expect(IslandAnswers.ask(from: multi) == nil)
        var two = Self.question
        two["tool_input"] = ["questions": [["question": "A", "options": [["label": "x"]]], ["question": "B", "options": [["label": "y"]]]]]
        #expect(IslandAnswers.ask(from: two) == nil)
    }

    @Test func writesTheHookOutputClaudeCodeExpects() throws {
        let ask = try #require(IslandAnswers.ask(from: Self.permission))
        let allow = try #require(IslandAnswers.output(for: .allow, ask: ask, hook: Self.permission))
        let allowed = try #require(try JSONSerialization.jsonObject(with: allow) as? [String: Any])
        let decision = (allowed["hookSpecificOutput"] as? [String: Any])?["decision"] as? [String: Any]
        #expect(decision?["behavior"] as? String == "allow")
        #expect(IslandAnswers.output(for: .pass, ask: ask, hook: Self.permission) == nil)
        #expect(IslandAnswers.output(for: .answer("x"), ask: ask, hook: Self.permission) == nil)

        let question = try #require(IslandAnswers.ask(from: Self.question))
        let data = try #require(IslandAnswers.output(for: .answer("Accent"), ask: question, hook: Self.question))
        let output = try #require((try JSONSerialization.jsonObject(with: data) as? [String: Any])?["hookSpecificOutput"] as? [String: Any])
        #expect(output["permissionDecision"] as? String == "allow")
        let input = try #require(output["updatedInput"] as? [String: Any])
        #expect((input["answers"] as? [String: String]) == ["Which colour?": "Accent"])
        #expect((input["questions"] as? [[String: Any]])?.count == 1)
        // Only one of the question's own options.
        #expect(IslandAnswers.output(for: .answer("Something else"), ask: question, hook: Self.question) == nil)
    }

    @Test func passesStraightAwayWhenNobodyListens() throws {
        let input = try JSONSerialization.data(withJSONObject: Self.permission)
        #expect(IslandAnswers.answer(input, folder: FileManager.default.temporaryDirectory, wait: 5, listener: { false }) == nil)
    }

    @Test func waitsForTheIslandsAnswer() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        // The island answers once the request shows up.
        let answering = Task.detached {
            for _ in 0..<50 {
                if let file = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
                    .first(where: { $0.pathExtension == "ask" }) {
                    let reply = file.deletingPathExtension().appendingPathExtension("reply")
                    try? JSONEncoder().encode(IslandAnswers.Reply.deny).write(to: reply)
                    return
                }
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
        let input = try JSONSerialization.data(withJSONObject: Self.permission)
        let output = try #require(IslandAnswers.answer(input, folder: folder, wait: 5, listener: { true }))
        await answering.value
        let decision = ((try JSONSerialization.jsonObject(with: output) as? [String: Any])?["hookSpecificOutput"]
            as? [String: Any])?["decision"] as? [String: Any]
        #expect(decision?["behavior"] as? String == "deny")
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty)
    }

    @Test func addsAndRemovesOnlyItsOwnHooks() throws {
        let theirs: [String: Any] = ["PreToolUse": [["matcher": "Bash", "hooks": [["type": "command", "command": "lint.sh"]]]]]
        let added = IslandAnswers.adding(binary: "/Applications/Barn Owl.app/Contents/MacOS/Barn Owl", to: theirs)
        #expect((added["PreToolUse"] as? [[String: Any]])?.count == 2)
        #expect((added["PermissionRequest"] as? [[String: Any]])?.count == 1)
        let removed = IslandAnswers.removing(from: added)
        #expect(removed.keys.sorted() == ["PreToolUse"])
        #expect(((removed["PreToolUse"] as? [[String: Any]])?.first?["matcher"] as? String) == "Bash")
    }

    @Test func turnsOnAndOffThroughTheSettingsFile() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let files = StatusLineRelay.Files(settings: folder.appending(path: "settings.json"), support: folder)
        try Data(#"{"model":"opus"}"#.utf8).write(to: files.settings)
        try IslandAnswers.turnOn(files: files, binary: "/Applications/Barn Owl.app/Contents/MacOS/Barn Owl")
        #expect(IslandAnswers.isOn(files: files))
        try IslandAnswers.turnOff(files: files)
        #expect(!IslandAnswers.isOn(files: files))
        let settings = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: files.settings)) as? [String: Any])
        #expect(settings["hooks"] == nil && settings["model"] as? String == "opus")
    }

    @Test func aHeldQuestionDoesNotTimeOut() {
        let ask = IslandAnswers.Ask(id: "a", kind: .question, session: "s", pid: 1, tool: "AskUserQuestion", asked: Date(),
                                    text: "Q", options: ["A"])
        let request = AgentWatcher.request(for: ask)
        #expect(request.kind == .question && request.deadline == nil)
    }
}

struct HostLookupTests {
    /// launchd belongs to root, as a terminal's `login` does: its parent must still be readable.
    @Test func readsTheParentOfARootProcess() {
        #expect(ProcessScan.parent(of: 1) == 0)
        #expect(ProcessScan.parent(of: getpid()) == getppid())
    }
}

struct ClaudeSettingsTogetherTests {
    /// The status line relay and the island's hooks touch different keys: either can go on or off first.
    @Test(arguments: [true, false]) func bothOnThenOffInEitherOrder(relayFirst: Bool) throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let files = StatusLineRelay.Files(settings: folder.appending(path: "settings.json"), support: folder)
        let original = #"{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"lint.sh"}]}]},"#
            + #""statusLine":{"type":"command","command":"my-status.sh"},"model":"opus"}"#
        try Data(original.utf8).write(to: files.settings)
        let binary = "/Applications/Barn Owl.app/Contents/MacOS/Barn Owl"
        let steps: [() throws -> Void] = [{ try StatusLineRelay.turnOn(files: files, binary: binary) },
                                          { try IslandAnswers.turnOn(files: files, binary: binary) }]
        for step in relayFirst ? steps : steps.reversed() { try step() }
        #expect(StatusLineRelay.isOn(files: files) && IslandAnswers.isOn(files: files))
        let offs: [() throws -> Void] = [{ try StatusLineRelay.turnOff(files: files) }, { try IslandAnswers.turnOff(files: files) }]
        for step in relayFirst ? offs.reversed() : offs { try step() }
        let back = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: files.settings)) as? [String: Any])
        let before = try #require(try JSONSerialization.jsonObject(with: Data(original.utf8)) as? [String: Any])
        #expect(NSDictionary(dictionary: back).isEqual(to: before))
    }
}

struct IslandAlwaysAllowTests {
    nonisolated(unsafe) static let fetch: [String: Any] = [
        "session_id": "s1", "hook_event_name": "PermissionRequest", "tool_name": "WebFetch",
        "tool_input": ["url": "https://www.vg.no/", "prompt": "Headlines"],
        "permission_suggestions": [["type": "addRules", "behavior": "allow", "destination": "localSettings",
                                    "rules": [["toolName": "WebFetch", "ruleContent": "domain:www.vg.no"]]]],
    ]

    @Test func saysWhatClaudesOwnRuleCovers() throws {
        let ask = try #require(IslandAnswers.ask(from: Self.fetch))
        #expect(ask.text == "https://www.vg.no/" && ask.always == "www.vg.no")
        let bash = IslandAnswers.alwaysScope([["type": "addRules", "behavior": "allow", "destination": "session",
                                               "rules": [["toolName": "Bash", "ruleContent": "npm test:*"]]]])
        #expect(bash == "npm test commands, this session")
        #expect(IslandAnswers.alwaysScope([["type": "addRules", "behavior": "deny", "rules": []]]) == nil)
    }

    @Test func alwaysAllowHandsBackExactlyThatRule() throws {
        let ask = try #require(IslandAnswers.ask(from: Self.fetch))
        let data = try #require(IslandAnswers.output(for: .always, ask: ask, hook: Self.fetch))
        let decision = try #require(((try JSONSerialization.jsonObject(with: data) as? [String: Any])?["hookSpecificOutput"]
            as? [String: Any])?["decision"] as? [String: Any])
        #expect(decision["behavior"] as? String == "allow")
        let rules = try #require(decision["updatedPermissions"] as? [[String: Any]])
        #expect(rules.count == 1 && rules[0]["destination"] as? String == "localSettings")
        #expect(((rules[0]["rules"] as? [[String: Any]])?.first?["ruleContent"] as? String) == "domain:www.vg.no")
    }

    @Test func noSuggestionMeansNoAlwaysAllow() throws {
        let ask = try #require(IslandAnswers.ask(from: IslandAnswerTests.permission))
        #expect(ask.always == nil)
        #expect(IslandAnswers.output(for: .always, ask: ask, hook: IslandAnswerTests.permission) == nil)
    }
}

struct ReviewFixTests {
    @Test func aPullRequestCountsOnceThoughClaudeCodeRepeatsIt() {
        var log = ClaudeSource.LogState()
        let pr: [String: Any] = ["type": "pr-link", "prNumber": 2, "prUrl": "https://github.com/o/r/pull/2",
                                 "timestamp": "2026-10-19T10:00:00.000Z"]
        log.consume(pr)
        #expect(log.shippedAt != nil)
        log.consume(["type": "user", "message": ["role": "user", "content": "Next, please"],
                     "timestamp": "2026-10-19T10:05:00.000Z"])
        #expect(log.shippedAt == nil)
        var again = pr
        again["timestamp"] = "2026-10-19T10:06:00.000Z"
        log.consume(again)
        #expect(log.shippedAt == nil)
    }

    @Test func aNewPromptForgetsTheLastTurnsFailures() {
        var log = ClaudeSource.LogState()
        log.failures = 3
        log.consume(["type": "user", "message": ["role": "user", "content": "Try something else"],
                     "timestamp": "2026-10-19T10:05:00.000Z"])
        #expect(log.failures == 0 && log.pending.isEmpty)
    }

    @Test func theUsersOwnStatusLineComesBackOutOfTheRelay() {
        let original = "printf '%s' \"$(git branch --show-current)\" it's"
        let command = StatusLineRelay.command(binary: "/Applications/Barn Owl.app/Contents/MacOS/Barn Owl", original: original)
        #expect(StatusLineRelay.original(inRelay: command) == original)
        #expect(StatusLineRelay.original(inRelay: "my-status.sh") == nil)
    }

    @Test func listeningMeansHoldingTheLock() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(!IslandAnswers.isListening(at: url))
        let descriptor = open(url.path, O_RDWR | O_CREAT, 0o600)
        #expect(!IslandAnswers.isListening(at: url))
        #expect(flock(descriptor, LOCK_EX | LOCK_NB) == 0)
        #expect(IslandAnswers.isListening(at: url))
        close(descriptor)
        #expect(!IslandAnswers.isListening(at: url))
    }

    @Test func otherToolsShowEveryArgument() throws {
        let hook: [String: Any] = ["session_id": "s", "hook_event_name": "PermissionRequest", "tool_name": "mcp__mail__send_email",
                                   "tool_input": ["to": "ana@example.com", "subject": "Hi"]]
        let ask = try #require(IslandAnswers.ask(from: hook))
        #expect(ask.text == "send_email\nsubject: Hi\nto: ana@example.com")
    }

    @Test func alwaysAllowIsOfferedOnlyWhenItsWholeScopeFits() {
        let three: [[String: Any]] = [["type": "addRules", "behavior": "allow", "destination": "localSettings",
                                        "rules": [["toolName": "Bash", "ruleContent": "a:*"], ["toolName": "Bash", "ruleContent": "b:*"],
                                                  ["toolName": "Bash", "ruleContent": "c:*"]]]]
        #expect(IslandAnswers.alwaysScope(three) == nil)
    }

    @Test func urgentQuestionsComeFirst() {
        let now = Date()
        func asking(_ id: String, since: TimeInterval, question: Bool) -> AgentSession {
            var session = AgentSession(id: id, agent: .claude, pid: nil, name: id, folder: URL(fileURLWithPath: "/x"),
                                       place: ProjectPlace(repository: "r", worktree: nil, root: URL(fileURLWithPath: "/x")),
                                       started: now.addingTimeInterval(-3600), state: question ? .asking : .needsYou, stateSince: now)
            session.request = AgentRequest(kind: question ? .question : .command, text: "?", since: now.addingTimeInterval(since))
            return session
        }
        let order = [asking("command", since: -300, question: false), asking("question", since: -50, question: true)]
            .sorted(by: AgentWatcher.order).map(\.id)
        #expect(order.first == "question")
    }
}

@MainActor
struct LenientRulesTests {
    @Test func aRuleFromANewerVersionDoesNotWipeTheRest() throws {
        let defaults = try #require(UserDefaults(suiteName: "barnowl.test.rules.\(UUID().uuidString)"))
        let json = #"[{"id":"0D3E0000-0000-4000-8000-0000000001A1","conditions":[{"onPower":{}}],"isEnabled":true,"allowDisplaySleep":false},"#
            + #"{"id":"0D3E0000-0000-4000-8000-0000000001A2","conditions":[{"somethingNew":{}}],"isEnabled":true,"allowDisplaySleep":true}]"#
        defaults.set(Data(json.utf8), forKey: "keepAwakeRules")
        let store = RuleStore(defaults: defaults)
        #expect(store.rules.count == 1)
        #expect(store.rules.first?.conditions == [.onPower])
    }
}
