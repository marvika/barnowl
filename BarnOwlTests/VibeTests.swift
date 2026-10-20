import Foundation
import Testing
@testable import BarnOwl

/// Mistral Vibe's session store, with records shaped like Vibe 3.0's own.
struct VibeTests {
    private let t0: Double = 1_792_519_003_343 // ms

    private func line(_ type: String, _ payload: String, sequence: Int = 1) -> Substring {
        Substring(#"{"payload":\#(payload),"previous_record_sha256":"aa","record_sha256":"bb","recovery_journal_record_version":1,"sequence":\#(sequence),"type":"\#(type)"}"#)
    }

    private func envelope(_ status: String, turn: String, started: Double, ended: Double? = nil) -> Substring {
        let completed = ended.map { #","completedAt":\#(Int($0))"# } ?? ""
        let active = status == "running" ? #","activeTurnId":"turn-1""# : ""
        return line("projection_delta", """
        {"delta":[{"op":"set_envelope","state":{"activeCallbacks":[],"format":"harness.public-session-state/v1",
        "latestTurn":{"id":"turn-1","startedAt":\(Int(started))\(completed),"status":"\(turn)"},
        "session":{"id":"s","status":{"type":"\(status)"\(active)}},"turnQueue":{"items":[]}}}],"watermark":3}
        """.replacingOccurrences(of: "\n", with: ""))
    }

    private func effect(_ tool: String, _ status: String) -> Substring {
        line("projection_delta", """
        {"delta":[{"entry":{"type":"effect","id":"effect-1","title":"\(tool)","detail":{"kind":"tool","toolName":"\(tool)","input":{}},
        "state":{"status":"\(status)"}},"op":"append_entry"}],"watermark":4}
        """.replacingOccurrences(of: "\n", with: ""))
    }

    private var approval: Substring {
        line("callback_registered", """
        {"callback_id":"approval-1","kind":"approval","routing":{"type":"callback","id":"approval-1","createdAt":\(Int(t0 + 5000)),
        "title":"Approve file_system.bash","detail":{"kind":"approval","effect":{"kind":"tool","toolName":"file_system.bash",
        "input":{"command":"git push origin main\\ngit status"}},"choices":["approve","approve_for_session","approve_permanently","deny","cancel_turn"]},
        "state":{"status":"open"}}}
        """.replacingOccurrences(of: "\n", with: ""))
    }

    @Test func aTurnRunsThenRests() {
        var log = VibeSource.LogState()
        log.consume(envelope("running", turn: "in_progress", started: t0))
        let now = Date(timeIntervalSince1970: (t0 + 2000) / 1000)
        #expect(log.state(now: now).state == .thinking)
        log.consume(envelope("idle", turn: "completed", started: t0, ended: t0 + 1102))
        #expect(log.state(now: now).state == .resting)
        #expect(abs((log.lastTurn ?? 0) - 1.102) < 0.001)
        let later = now.addingTimeInterval(11 * 60)
        #expect(log.state(now: later).state == .napping)
    }

    @Test func theRunningToolPicksThePose() {
        var log = VibeSource.LogState()
        log.consume(envelope("running", turn: "in_progress", started: t0))
        let now = Date(timeIntervalSince1970: t0 / 1000 + 5)
        log.consume(effect("file_system.bash", "running"))
        #expect(log.state(now: now).state == .running)
        log.consume(effect("file_system.bash", "completed"))
        log.consume(effect("file_system.search_replace", "running"))
        #expect(log.state(now: now).state == .typing)
        log.consume(effect("file_system.search_replace", "completed"))
        log.consume(effect("connector_web_search.web_search", "running"))
        #expect(log.state(now: now).state == .browsing)
        log.consume(effect("connector_web_search.web_search", "completed"))
        log.consume(effect("agents.spawn", "running"))
        #expect(log.state(now: now).state == .waitingOnHelpers)
        log.consume(effect("agents.spawn", "completed"))
        #expect(log.state(now: now).state == .thinking)
    }

    @Test func threeFailedCommandsIsFixingThenStuck() {
        var log = VibeSource.LogState()
        log.consume(envelope("running", turn: "in_progress", started: t0))
        let now = Date(timeIntervalSince1970: t0 / 1000 + 5)
        for _ in 0..<2 { log.consume(effect("file_system.bash", "failed")) }
        #expect(log.state(now: now).state == .thinking)
        log.consume(effect("file_system.bash", "failed"))
        #expect(log.state(now: now).state == .fixing)
        log.consume(envelope("idle", turn: "completed", started: t0, ended: t0 + 3000))
        #expect(log.state(now: now).state == .stuck)
        // A new turn starts counting again.
        log.consume(envelope("running", turn: "in_progress", started: t0 + 60_000))
        #expect(log.failures == 0)
    }

    @Test func anApprovalNeedsYouWithItsCommand() throws {
        var log = VibeSource.LogState()
        log.consume(envelope("running", turn: "in_progress", started: t0))
        log.consume(approval)
        let now = Date(timeIntervalSince1970: t0 / 1000 + 10)
        #expect(log.state(now: now).state == .needsYou)
        let request = try #require(log.request)
        #expect(request.kind == .command)
        #expect(request.text == "git push origin main")
        #expect(request.deadline == nil)
        log.consume(line("callback_resolved", #"{"callback_id":"approval-1","result":{"choice":"approve"},"state":"resolved"}"#))
        #expect(log.request == nil)
        #expect(log.state(now: now).state == .thinking)
    }

    @Test func aQuestionIsAskingWithItsOptions() throws {
        var log = VibeSource.LogState()
        log.consume(envelope("running", turn: "in_progress", started: t0))
        log.consume(line("callback_registered", """
        {"callback_id":"user-input-1","kind":"user_input","routing":{"type":"callback","createdAt":\(Int(t0)),
        "detail":{"kind":"user_input","request":{"questions":[{"question":"Which colour should the Perch follow?",
        "options":[{"label":"Desktop picture"},{"label":"Accent colour"}]}]}}}}
        """.replacingOccurrences(of: "\n", with: "")))
        #expect(log.state(now: Date()).state == .asking)
        let request = try #require(log.request)
        #expect(request.text == "Which colour should the Perch follow?")
        #expect(request.options == ["Desktop picture", "Accent colour"])
    }

    @Test func anEndedTurnLetsGoOfWhatItWaitedFor() {
        var log = VibeSource.LogState()
        log.consume(envelope("running", turn: "in_progress", started: t0))
        log.consume(approval)
        log.consume(effect("file_system.bash", "running"))
        log.consume(envelope("idle", turn: "interrupted", started: t0, ended: t0 + 9000))
        #expect(log.request == nil)
        #expect(log.runningTool == nil)
        #expect(log.state(now: Date(timeIntervalSince1970: t0 / 1000 + 20)).state == .resting)
    }

    @Test func aLongTurnEndsAsYourTurn() {
        var log = VibeSource.LogState()
        log.consume(envelope("running", turn: "in_progress", started: t0))
        log.consume(envelope("idle", turn: "completed", started: t0, ended: t0 + 47 * 60_000))
        let now = Date(timeIntervalSince1970: (t0 + 48 * 60_000) / 1000)
        let (state, detail) = log.state(now: now)
        #expect(state == .done)
        #expect(detail == "Your turn · finished after 47 min")
    }

    @Test func aFailedTurnIsStuck() {
        var log = VibeSource.LogState()
        log.consume(envelope("idle", turn: "failed", started: t0, ended: t0 + 2000))
        #expect(log.state(now: Date(timeIntervalSince1970: t0 / 1000 + 60)).state == .stuck)
    }

    @Test func aRateLimitedRetryIsATeaBreak() {
        var log = VibeSource.LogState()
        log.consume(line("projection_delta", """
        {"delta":[{"op":"set_envelope","state":{"latestTurn":{"startedAt":\(Int(t0)),"status":"in_progress"},
        "retrying":{"category":"rate_limited","attempt":2},"session":{"status":{"type":"running"}}}}]}
        """.replacingOccurrences(of: "\n", with: "")))
        #expect(log.state(now: Date()).state == .teaBreak)
    }

    @Test func otherRecordsAreIgnored() {
        var log = VibeSource.LogState()
        log.consume(line("command_reserved", #"{"method":"turn/start","params":{"entries":[{"content":[{"text":"Hey!"}]}]}}"#))
        log.consume(line("action_intent", #"{"action_id":"a","kind":"tool"}"#))
        log.consume("not json")
        #expect(log == VibeSource.LogState())
    }

    // MARK: Files

    private func temporaryFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "vibe-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    @Test func leasesNameTheAppServerUnderTheProcess() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let active = folder.appending(path: "active")
        try FileManager.default.createDirectory(at: active, withIntermediateDirectories: true)
        try Data(#"{"acquired_at":"2026-10-20T17:56:06.162Z","lease_version":1,"process_id":38711,"session_id":"a8700966-c331-b92a-b8c1-53682d7177f6"}"#.utf8)
            .write(to: active.appending(path: "a8700966-c331-b92a-b8c1-53682d7177f6.lock.json"))
        try Data(#"{"process_id":1,"session_id":"../../etc"}"#.utf8).write(to: active.appending(path: "bad.lock.json"))
        let leases = VibeSource.leases(in: folder)
        #expect(leases == [38711: "a8700966-c331-b92a-b8c1-53682d7177f6"])
        // vibe-rs (38699) starts the app server (38711), which holds the lease.
        let parents: [Int32: Int32] = [38711: 38699]
        #expect(VibeSource.session(of: 38699, leases: leases, parentOf: { parents[$0] }) == "a8700966-c331-b92a-b8c1-53682d7177f6")
        #expect(VibeSource.session(of: 38711, leases: leases, parentOf: { parents[$0] }) == "a8700966-c331-b92a-b8c1-53682d7177f6")
        #expect(VibeSource.session(of: 4242, leases: leases, parentOf: { parents[$0] }) == nil)
    }

    @Test func metaGivesTheTitleAndModel() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data(#"{"session_id":"s","title":"Fix the Perch tint","environment":{"working_directory":"/Users/me/code"},"config":{"active_model":"glm-5.3","model_name":"glm-5-3-fp8"}}"#.utf8)
            .write(to: folder.appending(path: "meta.json"))
        #expect(VibeSource.meta(of: folder) == VibeSource.Meta(title: "Fix the Perch tint", model: "glm-5.3"))
    }

    @Test func theFollowerCarriesOnIntoTheNextSegment() throws {
        let session = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: session) }
        let journal = session.appending(path: "journal")
        try FileManager.default.createDirectory(at: journal, withIntermediateDirectories: true)
        let first = journal.appending(path: "0000000000000035.jsonl")
        try Data((envelope("running", turn: "in_progress", started: t0) + "\n").utf8).write(to: first)
        var follower = VibeSource.Follower(session: "s")
        follower.read(folder: session)
        #expect(follower.log.status == "running")

        // A tool starts, cut off mid-line, then finishes the line.
        let handle = try FileHandle(forWritingTo: first)
        let tool = String(effect("file_system.bash", "running"))
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(tool.prefix(40).utf8))
        follower.read(folder: session)
        #expect(follower.log.runningTool == nil)
        try handle.write(contentsOf: Data((tool.dropFirst(40) + "\n").utf8))
        try handle.close()
        follower.read(folder: session)
        #expect(follower.log.runningTool == "file_system.bash")

        // The turn ends; Vibe snapshots and starts a new, empty segment.
        let end = String(envelope("idle", turn: "completed", started: t0, ended: t0 + 4000)) + "\n"
        let more = try FileHandle(forWritingTo: first)
        try more.seekToEnd()
        try more.write(contentsOf: Data(end.utf8))
        try more.close()
        try Data().write(to: journal.appending(path: "0000000000000043.jsonl"))
        follower.read(folder: session)
        #expect(follower.log.status == "idle")
        #expect(follower.segment?.lastPathComponent == "0000000000000043.jsonl")

        // The next turn goes into the new segment, read from its start.
        try Data((envelope("running", turn: "in_progress", started: t0 + 60_000) + "\n").utf8)
            .write(to: journal.appending(path: "0000000000000043.jsonl"))
        follower.read(folder: session)
        #expect(follower.log.status == "running")
    }

    @Test func aFreshFollowerReadsTheLastTwoSegments() throws {
        let session = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: session) }
        let journal = session.appending(path: "journal")
        try FileManager.default.createDirectory(at: journal, withIntermediateDirectories: true)
        try Data((envelope("idle", turn: "completed", started: t0, ended: t0 + 1000) + "\n").utf8)
            .write(to: journal.appending(path: "0000000000000035.jsonl"))
        try Data().write(to: journal.appending(path: "0000000000000043.jsonl"))
        try Data("ignored".utf8).write(to: journal.appending(path: "notes.txt"))
        var follower = VibeSource.Follower(session: "s")
        follower.read(folder: session)
        #expect(follower.log.status == "idle")
        #expect(follower.log.turnStatus == "completed")
    }

    // MARK: Processes

    @Test func vibeProcessesAreFoundAndOnePromptRunsAreScripted() {
        #expect(ProcessScan.binaries["vibe-rs"] == .vibe)
        #expect(ProcessScan.scriptAgent(arguments: ["python3", "/Users/me/.local/bin/vibe-acp"]) == .vibe)
        // The app server Vibe starts renames itself, and isn't a second session.
        #expect(ProcessScan.scriptAgent(arguments: ["vibe-app-server"]) == nil)
        #expect(ProcessScan.isScripted(.vibe, arguments: ["vibe-rs", "-p", "Reply with: ok"]))
        #expect(!ProcessScan.isScripted(.vibe, arguments: ["vibe-rs"]))
        #expect(ProcessScan.isScripted(.codex, arguments: ["codex", "exec", "fix the tests"]))
        #expect(!ProcessScan.isScripted(.codex, arguments: ["codex"]))
    }

    @Test func onlyPlainSessionIDsAreUsed() {
        #expect(VibeSource.isSessionID("a8700966-c331-b92a-b8c1-53682d7177f6"))
        #expect(!VibeSource.isSessionID("../a8700966"))
        #expect(!VibeSource.isSessionID(""))
    }

    // MARK: One agent calling another

    @Test func theNearestAgentAboveIsTheCaller() {
        let callers: [Int32: String] = [30911: "claude:abc", 500: "codex:500"]
        // vibe-rs ← zsh ← Claude Code's shell ← claude (30911)
        #expect(AgentReader.caller(of: 42100, among: callers, ancestors: [42043, 42040, 30911, 28489]) == "claude:abc")
        #expect(AgentReader.caller(of: 42100, among: callers, ancestors: [600, 500, 30911]) == "codex:500")
        #expect(AgentReader.caller(of: 42100, among: callers, ancestors: [36386, 1]) == nil)
    }

    @MainActor @Test func anAgentsScriptedHelperIsShown() throws {
        let defaults = try #require(UserDefaults(suiteName: "vibe-called-\(UUID().uuidString)"))
        let choices = AgentChoices(defaults: defaults)
        var session = AgentSession(id: "vibe:42100", agent: .vibe, pid: 42100, name: "owl-playground",
                                   folder: URL(fileURLWithPath: "/Users/me/code/owl-playground"),
                                   place: ProjectPlace(repository: "owl-playground", root: URL(fileURLWithPath: "/Users/me/code/owl-playground")),
                                   started: Date(), state: .running, stateSince: Date())
        session.isScripted = true
        #expect(choices.isHidden(session) == Preferences.agentsHideScripted)
        session.calledBy = "claude:abc"
        #expect(!choices.isHidden(session))
    }


    @Test func aLongModelCallSaysHowLong() {
        var log = VibeSource.LogState()
        log.consume(envelope("running", turn: "in_progress", started: t0))
        log.consume(line("action_intent", #"{"action_id":"call-1","kind":"completion"}"#))
        let now = Date()
        #expect(log.state(now: now, thinkingSince: now.addingTimeInterval(-30)).detail == nil)
        #expect(log.state(now: now, thinkingSince: now.addingTimeInterval(-150)).detail == "Thinking · 3 min")
        log.consume(line("action_result", #"{"action_id":"call-1","result":{}}"#))
        #expect(log.pendingCompletion == nil)
        #expect(log.state(now: now, thinkingSince: now.addingTimeInterval(-150)).detail == nil)
    }
}

