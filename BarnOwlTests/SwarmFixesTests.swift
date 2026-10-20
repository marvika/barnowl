import Foundation
import Testing
@testable import BarnOwl

/// Fixes for what the review swarm found.
struct SwarmFixesTests {
    private func folder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "swarm-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    @Test func aSettingsWriteNoticesAChangeMadeMeanwhile() throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let files = StatusLineRelay.Files(settings: folder.appending(path: "settings.json"), support: folder.appending(path: "s"))
        try Data(#"{"model":"opus"}"#.utf8).write(to: files.settings)
        let (settings, bytes) = try StatusLineRelay.snapshot(files)
        // Claude Code writes the file between our read and our write.
        try Data(#"{"model":"opus","permissions":{"allow":["Bash(ls)"]}}"#.utf8).write(to: files.settings)
        #expect(throws: StatusLineRelay.Failure.changedMeanwhile) { try StatusLineRelay.write(settings, files, over: bytes) }
        // Turning on, from a fresh read, keeps what Claude Code wrote.
        try StatusLineRelay.turnOn(files: files, binary: "/Applications/Barn Owl.app/Contents/MacOS/Barn Owl")
        let after = try StatusLineRelay.readSettings(files)
        #expect((after["permissions"] as? [String: Any]) != nil)
        #expect(after["statusLine"] != nil)
    }

    @Test func settingsAreNeverWrittenReadableByOthers() throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let files = StatusLineRelay.Files(settings: folder.appending(path: "settings.json"), support: folder.appending(path: "s"))
        try StatusLineRelay.write(["model": "opus"], files)
        let mode = try FileManager.default.attributesOfItem(atPath: files.settings.path)[.posixPermissions] as? NSNumber
        #expect(mode?.intValue == 0o600)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.contains("barnowl-") }
        #expect(leftovers.isEmpty)
    }

    @Test func onlyOurOwnHookCommandIsOurs() {
        let ours = IslandAnswers.command(binary: "/Applications/Barn Owl.app/Contents/MacOS/Barn Owl")
        #expect(IslandAnswers.isOurs(["command": ours]))
        #expect(!IslandAnswers.isOurs(["command": "~/bin/notify 'Barn Owl' --answer done"]))
    }

    @Test func turningAnswersOffLeavesOtherHooksUntouched() throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let files = StatusLineRelay.Files(settings: folder.appending(path: "settings.json"), support: folder.appending(path: "s"))
        let original = #"{ "hooks" : { "Stop" : [ { "hooks" : [ { "command" : "say done", "type" : "command" } ] } ] } }"#
        try Data(original.utf8).write(to: files.settings)
        try IslandAnswers.turnOff(files: files)
        #expect(try String(contentsOf: files.settings, encoding: .utf8) == original)
    }

    @Test func backCountsOnlyTheCurrentBatch() {
        let now = Date()
        func helper(_ id: String, started: TimeInterval, back: TimeInterval? = nil) -> AgentSession {
            var session = AgentSession(id: id, agent: .vibe, pid: nil, name: "GLM 5.3", folder: URL(fileURLWithPath: "/x"),
                                       place: ProjectPlace(repository: "x", root: URL(fileURLWithPath: "/x")),
                                       started: now.addingTimeInterval(started), state: .napping,
                                       stateSince: now.addingTimeInterval(back ?? 0))
            session.calledBy = "claude:c"
            return session
        }
        let earlier = (0..<6).map { helper("old\($0)", started: -3600, back: -3000) }
        let thisBatch = (0..<3).map { helper("new\($0)", started: -300, back: -60) }
        let out = [helper("out", started: -300)]
        #expect(HelperBatch.back(of: "claude:c", live: out, returned: earlier + thisBatch, now: now).count == 3)
        // All back: those of the last half hour.
        #expect(HelperBatch.back(of: "claude:c", live: [], returned: earlier + thisBatch, now: now).count == 3)
    }

    @Test func aSaveOvertakenByALaterOneIsDropped() throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "history.json")
        let writer = HistoryWriter()
        let stale = writer.ticket()
        let clear = writer.ticket()
        writer.write(["entries": ["secret"]], to: url, ticket: clear - 0, wait: true)
        writer.write(["entries": ["secret", "older"]], to: url, ticket: stale, wait: true)
        #expect(try String(contentsOf: url, encoding: .utf8).contains("older") == false)
        let mode = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
        #expect(mode?.intValue == 0o600)
    }

    @Test func outlandishPlanNumbersAreIgnored() {
        #expect(CodexSource.limit(["used_percent": 1e300, "window_minutes": 300], at: Date()) == nil)
        #expect(CodexSource.limit(["used_percent": 38, "window_minutes": 300], at: Date()) != nil)
    }
}
