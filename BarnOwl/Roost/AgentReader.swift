import Foundation

/// Does the file work for AgentWatcher off the main thread: reads session
/// files, follows each live session's log from where it last stopped, and
/// scans for other agents' processes.
actor AgentReader {
    /// How much of a log to read when first seeing a session: enough for the
    /// current turn, without reading a log of hundreds of MB.
    static let firstRead = 256 * 1024
    /// Using this share of a CPU core between scans counts as working, for
    /// agents whose logs Barn Owl can't read.
    static let busyCPU = 0.02

    private struct Followed {
        var url: URL
        var offset: UInt64
        var claude = ClaudeSource.LogState()
        var codex = CodexSource.LogState()
        /// A line cut off at the end of the last read.
        var partial = Data()
    }

    private var logs: [String: Followed] = [:]
    /// The last session file that decoded, per path: Claude Code rewrites
    /// them in place, so a read can catch one half-written.
    private var lastGood: [URL: ClaudeSource.SessionFile] = [:]
    private var transcripts: [String: URL] = [:]
    /// Sessions with no log yet, and when that was last checked.
    private var missingLogs: [String: Date] = [:]
    private var places: [String: ProjectPlace] = [:]
    /// Codex log per process, so a session keeps its log while it runs.
    private var codexLogs: [Int32: URL] = [:]
    /// Vibe's journal per process, and its session's title and model.
    private var vibeFollowers: [Int32: VibeSource.Follower] = [:]
    private var vibeMeta: [String: (modified: Date, meta: VibeSource.Meta)] = [:]
    private var vibeLeasesModified: Date?
    /// Each agent process's parents, for which session started it.
    private var ancestry: [Int32: [Int32]] = [:]
    private var logFolders: [URL: String] = [:]
    private var agents: [ProcessScan.Found] = []
    private var cpuBefore: [Int32: (cpu: TimeInterval, at: Date)] = [:]
    private var busyByCPU: [Int32: Bool] = [:]
    private var lastScan = Date.distantPast
    private var emptyScans = 0
    /// The Claude app's usage history, read again only when it changes.
    private var history: (modified: Date, samples: [PlanLimits.Sample])?
    private var codexLimits: [PlanLimit] = []
    /// Claude app chats by Claude Code session ID, and when their records changed.
    private var chats: [String: (url: URL, modified: Date, chat: ClaudeAppChats.Chat)] = [:]
    private var lastChatScan = Date.distantPast

    struct ClaudeRead: Sendable {
        let file: ClaudeSource.SessionFile
        let log: ClaudeSource.LogState
        let helpers: [AgentHelper]
        let place: ProjectPlace
        /// The Claude app chat it runs in, for sessions started there.
        var chat: ClaudeAppChats.Chat?
    }

    struct AgentRead: Sendable {
        let found: ProcessScan.Found
        let place: ProjectPlace
        /// Codex's log, when one matched.
        let codex: CodexSource.LogState?
        /// Vibe's session, once it has one (after the first prompt).
        var vibe: VibeRead? = nil
        /// For agents without a log: whether it used the CPU since the last scan.
        let busy: Bool
        /// The session that started it, when another agent did: "claude:<id>", "codex:<pid>".
        var calledBy: String? = nil
    }

    struct VibeRead: Sendable {
        let log: VibeSource.LogState
        let meta: VibeSource.Meta?
    }

    struct Result: Sendable {
        var claude: [ClaudeRead] = []
        var agents: [AgentRead] = []
        var sessionsFolderExists = false
        var vibeLeasesExist = false
        var limits: [PlanLimit] = []
        /// Requests held for the island, when answering from it is on.
        var asks: [IslandAnswers.Ask] = []
    }

    /// Reads everything that changed. Processes are scanned every 15 seconds
    /// at most, and less often while none turn up.
    func read(now: Date, answers: Bool = false) -> Result {
        var result = Result()
        if answers { result.asks = IslandAnswers.pending(now: now) }
        var live = Set<String>()
        result.sessionsFolderExists = FileManager.default.fileExists(atPath: ClaudeSource.sessionsFolder.path)

        var files: [ClaudeSource.SessionFile] = []
        for url in ClaudeSource.sessionFiles() {
            let file = (try? Data(contentsOf: url)).flatMap(ClaudeSource.parse) ?? lastGood[url]
            guard let file, ClaudeSource.isLive(file) else {
                lastGood[url] = nil
                continue
            }
            lastGood[url] = file
            files.append(file)
        }
        lastGood = lastGood.filter { url, _ in FileManager.default.fileExists(atPath: url.path) }
        // A resumed session can run in two processes at once: show the latest.
        let newest = Dictionary(files.map { ($0.sessionId, $0) }) { a, b in
            (a.statusUpdatedAt ?? 0) >= (b.statusUpdatedAt ?? 0) ? a : b
        }
        for file in newest.values.sorted(by: { $0.started < $1.started }) {
            let key = "claude:\(file.sessionId)"
            live.insert(key)
            var helpers: [AgentHelper] = []
            if let transcript = transcript(for: file, now: now) {
                follow(key, url: transcript) { followed, line in followed.claude.consume(line) }
                helpers = ClaudeSource.helpers(transcript: transcript, now: now)
            }
            result.claude.append(ClaudeRead(file: file, log: logs[key]?.claude ?? .init(), helpers: helpers,
                                            place: place(of: file.cwd),
                                            chat: file.entrypoint == "claude-desktop" ? chat(for: file.sessionId, now: now) : nil))
        }

        let interval: TimeInterval = emptyScans >= 4 ? 60 : 15
        // A Vibe starting or ending changes its leases: look for processes now.
        let leasesChanged = FileTimes.modified(VibeSource.leasesFolder.path)
        result.vibeLeasesExist = leasesChanged != nil
        let vibeChanged = leasesChanged != vibeLeasesModified
        vibeLeasesModified = leasesChanged
        let scanned = now.timeIntervalSince(lastScan) >= interval || vibeChanged
        if scanned {
            scan(now: now)
        }
        let vibes = agents.filter { $0.agent == .vibe }
        let leases = vibes.isEmpty ? [:] : VibeSource.leases()
        vibeFollowers = vibeFollowers.filter { pid, _ in vibes.contains { $0.pid == pid } }
        for found in agents {
            let key = "\(found.agent.rawValue):\(found.pid)"
            live.insert(key)
            var codex: CodexSource.LogState?
            if found.agent == .codex, let url = codexLogs[found.pid] {
                follow(key, url: url) { followed, line in followed.codex.consume(line) }
                codex = logs[key]?.codex
            }
            var read = AgentRead(found: found, place: place(of: found.folder), codex: codex,
                                 busy: busyByCPU[found.pid] ?? false)
            if found.agent == .vibe {
                read.vibe = vibe(found.pid, leases: leases)
            }
            result.agents.append(read)
        }
        let callers = Dictionary(newest.values.map { ($0.pid, "claude:\($0.sessionId)") }, uniquingKeysWith: { a, _ in a })
            .merging(agents.map { ($0.pid, "\($0.agent.rawValue):\($0.pid)") }, uniquingKeysWith: { a, _ in a })
        for index in result.agents.indices {
            result.agents[index].calledBy = Self.caller(of: result.agents[index].found.pid, among: callers,
                                                        ancestors: ancestors(of: result.agents[index].found.pid))
        }
        ancestry = ancestry.filter { pid, _ in agents.contains { $0.pid == pid } }
        result.limits = limits(now: now, codex: result.agents.compactMap(\.codex))
        logs = logs.filter { live.contains($0.key) }
        transcripts = transcripts.filter { live.contains("claude:\($0.key)") }
        missingLogs = missingLogs.filter { live.contains("claude:\($0.key)") }
        if places.count > 200 { places.removeAll() }
        return result
    }

    /// The agent session an agent was started by, if any: the nearest of its
    /// ancestors that's a Claude Code session or another agent. An agent
    /// asked to help by another runs a few shells below it.
    static func caller(of pid: Int32, among callers: [Int32: String], ancestors: [Int32]) -> String? {
        ancestors.lazy.compactMap { callers[$0] }.first
    }

    /// A process's parents, nearest first, up to `launchd`. They don't change
    /// while it runs, so they're looked up once.
    private func ancestors(of pid: Int32) -> [Int32] {
        if let known = ancestry[pid] { return known }
        var chain: [Int32] = []
        var current = pid
        while chain.count < 16, let parent = ProcessScan.parent(of: current), parent > 1, parent != current {
            chain.append(parent)
            current = parent
        }
        ancestry[pid] = chain
        return chain
    }

    /// A Vibe process's session, followed from where it last stopped. `/clear`
    /// starts a new session in the same process, so its lease is read each time.
    private func vibe(_ pid: Int32, leases: [Int32: String]) -> VibeRead? {
        guard let session = VibeSource.session(of: pid, leases: leases, parentOf: { ProcessScan.parent(of: $0) })
        else { return nil }
        let folder = VibeSource.folder(of: session)
        var follower = vibeFollowers[pid]?.session == session ? vibeFollowers[pid]! : VibeSource.Follower(session: session)
        follower.read(folder: folder)
        vibeFollowers[pid] = follower
        var meta: VibeSource.Meta?
        if let modified = FileTimes.modified(folder.appending(path: "meta.json").path) {
            if let known = vibeMeta[session], known.modified == modified {
                meta = known.meta
            } else {
                meta = VibeSource.meta(of: folder)
                if let meta { vibeMeta[session] = (modified, meta) }
            }
        }
        if vibeMeta.count > 50 { vibeMeta = vibeMeta.filter { _, entry in Date().timeIntervalSince(entry.modified) < 86_400 } }
        return VibeRead(log: follower.log, meta: meta)
    }

    /// Plan limits: Claude's from its app's history and Barn Owl's status
    /// line relay, Codex's from its latest log (kept for six hours).
    /// The app's record for a session, looked for again at most every 30 s
    /// while it's missing, and reread when it changes (its title can).
    private func chat(for session: String, now: Date) -> ClaudeAppChats.Chat? {
        func modified(_ url: URL) -> Date? {
            FileTimes.modified(url.path)
        }
        if let known = chats[session] {
            guard let date = modified(known.url) else { chats[session] = nil; return nil }
            if date != known.modified, let head = ClaudeAppChats.head(of: known.url),
               let parsed = ClaudeAppChats.parse(head: head), parsed.cliSession == session {
                chats[session] = (known.url, date, parsed.chat)
            }
            return chats[session]?.chat
        }
        guard now.timeIntervalSince(lastChatScan) >= 30 else { return nil }
        lastChatScan = now
        let known = Set(chats.values.map(\.url))
        for url in ClaudeAppChats.records() where !known.contains(url) {
            guard let date = modified(url), let head = ClaudeAppChats.head(of: url),
                  let parsed = ClaudeAppChats.parse(head: head) else { continue }
            chats[parsed.cliSession] = (url, date, parsed.chat)
        }
        return chats[session]?.chat
    }

    private func limits(now: Date, codex: [CodexSource.LogState]) -> [PlanLimit] {
        guard Preferences.agentsShowLimits else { return [] }
        let url = PlanLimits.claudeHistory
        if let modified = FileTimes.modified(url.path) {
            if history?.modified != modified, let data = try? Data(contentsOf: url) {
                history = (modified, PlanLimits.claudeSamples(from: data))
            }
        } else {
            history = nil
        }
        let fromHistory = PlanLimits.claudeLimits(from: history?.samples ?? [], now: now)
        let fromRelay = (try? Data(contentsOf: PlanLimits.relayFile)).map { PlanLimits.relayLimits(from: $0, now: now) } ?? []
        let newest = codex.flatMap(\.limits).sorted { $0.updated > $1.updated }
        if !newest.isEmpty {
            codexLimits = Dictionary(newest.map { ($0.window, $0) }, uniquingKeysWith: { a, _ in a }).values
                .sorted { $0.window < $1.window }
        }
        codexLimits.removeAll { now.timeIntervalSince($0.updated) > 6 * 3600 || ($0.resetsAt.map { $0 < now } ?? false) }
        return PlanLimits.merge(history: fromHistory, relay: fromRelay) + codexLimits
    }

    private func scan(now: Date) {
        lastScan = now
        agents = ProcessScan.agents()
        emptyScans = agents.isEmpty ? emptyScans + 1 : 0
        var cpu: [Int32: (cpu: TimeInterval, at: Date)] = [:]
        var busy: [Int32: Bool] = [:]
        for found in agents {
            if let before = cpuBefore[found.pid], now > before.at {
                busy[found.pid] = (found.cpu - before.cpu) / now.timeIntervalSince(before.at) >= Self.busyCPU
            }
            cpu[found.pid] = (found.cpu, now)
        }
        cpuBefore = cpu
        busyByCPU = busy
        let codex = agents.filter { $0.agent == .codex }
        codexLogs = codexLogs.filter { pid, _ in codex.contains { $0.pid == pid } }
        assignCodexLogs(to: codex, now: now)
    }

    private func transcript(for file: ClaudeSource.SessionFile, now: Date) -> URL? {
        if let known = transcripts[file.sessionId] { return known }
        // A brand-new session has no log yet; look again in a little while.
        if let missed = missingLogs[file.sessionId], now.timeIntervalSince(missed) < 20 { return nil }
        guard let url = ClaudeSource.transcript(for: file) else {
            missingLogs[file.sessionId] = now
            return nil
        }
        transcripts[file.sessionId] = url
        return url
    }

    private func place(of folder: String) -> ProjectPlace {
        if let known = places[folder] { return known }
        let place = ProjectPlace.of(URL(fileURLWithPath: folder))
        places[folder] = place
        return place
    }

    /// Matches each running Codex to the newest log for its folder written
    /// since it started (not an earlier session's).
    private func assignCodexLogs(to processes: [ProcessScan.Found], now: Date) {
        let unassigned = processes.filter { codexLogs[$0.pid] == nil }
        guard !unassigned.isEmpty else { return }
        let taken = Set(codexLogs.values)
        let recent = CodexSource.recentLogs(now: now).filter { !taken.contains($0.url) }
        var claimed = Set<URL>()
        for process in unassigned {
            let match = recent.first { log in
                !claimed.contains(log.url) && log.modified >= process.started.addingTimeInterval(-5)
                    && folder(ofLog: log.url) == process.folder
            }
            if let match {
                codexLogs[process.pid] = match.url
                claimed.insert(match.url)
            }
        }
        if logFolders.count > 100 { logFolders.removeAll() }
    }

    private func folder(ofLog url: URL) -> String? {
        if let known = logFolders[url] { return known }
        let folder = CodexSource.folder(ofLog: url)
        if let folder { logFolders[url] = folder }
        return folder
    }

    /// Reads what was added to a log since last time, line by line.
    private func follow(_ key: String, url: URL, consume: (inout Followed, Substring) -> Void) {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return }
        let isNew = logs[key]?.url != url
        var followed = isNew
            ? Followed(url: url, offset: size > UInt64(Self.firstRead) ? size - UInt64(Self.firstRead) : 0)
            : logs[key]!
        if size < followed.offset { followed = Followed(url: url, offset: 0) } // replaced or truncated
        guard size > followed.offset else {
            logs[key] = followed
            return
        }
        // At most 8 MB at once; the rest comes on the next read.
        let start = followed.offset
        let length = min(size - start, 8 * 1024 * 1024)
        try? handle.seek(toOffset: start)
        guard let data = try? handle.read(upToCount: Int(length)), !data.isEmpty else { return }
        followed.offset += UInt64(data.count)
        var bytes = followed.partial + data
        followed.partial = Data()
        if bytes.last != UInt8(ascii: "\n") {
            if let cut = bytes.lastIndex(of: UInt8(ascii: "\n")) {
                followed.partial = Data(bytes[bytes.index(after: cut)...])
                bytes = Data(bytes[...cut])
            } else {
                followed.partial = bytes
                bytes = Data()
            }
        }
        var lines = bytes.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true)
        // Starting mid-file, the first line is probably cut off.
        if isNew, start > 0, !lines.isEmpty { lines.removeFirst() }
        for line in lines { consume(&followed, Substring(String(decoding: line, as: UTF8.self))) }
        // Don't let a runaway partial line grow without bound.
        if followed.partial.count > 4 * 1024 * 1024 { followed.partial = Data() }
        logs[key] = followed
    }
}
