import AppKit
import Darwin

/// Finds agent processes and what they run in, with the same calls Activity
/// Monitor uses. Only your own processes, and no permission is needed.
enum ProcessScan {
    struct Found: Equatable, Sendable {
        let pid: Int32
        let agent: AgentKind
        let folder: String
        let started: Date
        /// CPU time used so far, in seconds, to tell working from idle.
        let cpu: TimeInterval
        /// Run for one prompt by a script or another agent (`vibe -p …`,
        /// `codex exec …`) rather than opened by a person.
        var scripted = false
    }

    /// Native agent binaries by process name. Node-hosted ones are matched
    /// on the script they run instead.
    static let binaries: [String: AgentKind] = [
        "codex": .codex, "opencode": .opencode, "copilot": .copilot, "gemini": .gemini, "vibe-rs": .vibe,
        "cursor-agent": .other,
        "droid": .other, "goose": .other, "crush": .other, "aider": .other, "amp": .other,
    ]

    /// Editors' background servers (`codex app-server`, `mcp-server`) aren't sessions.
    static let serverWords: Set<String> = ["app-server", "mcp-server", "mcp", "serve", "proto"]

    /// Agents other than Claude Code (which lists its own sessions).
    static func agents() -> [Found] {
        let me = getuid()
        var matches: [(found: Found, parent: Int32)] = []
        for pid in allPIDs() where pid > 1 {
            guard let info = bsdInfo(of: pid), info.pbi_uid == me else { continue }
            let name = processName(info)
            var agent = binaries[name]
            var arguments: [String]?
            if agent == nil, name == "node" || name == "bun" || name.hasPrefix("python") {
                arguments = self.arguments(of: pid)
                agent = scriptAgent(arguments: arguments ?? [])
            }
            guard let agent else { continue }
            let words = arguments ?? self.arguments(of: pid)
            if words.dropFirst().contains(where: { serverWords.contains($0) }) { continue }
            guard let folder = workingFolder(of: pid) else { continue }
            matches.append((Found(pid: pid, agent: agent, folder: folder, started: startTime(info),
                                  cpu: cpuTime(of: pid) ?? 0, scripted: isScripted(agent, arguments: words)),
                            Int32(info.pbi_ppid)))
        }
        return outermost(matches)
    }

    /// A node agent often relaunches itself, or wraps a native binary: keep
    /// only the outermost process of each agent.
    static func outermost(_ matches: [(found: Found, parent: Int32)],
                          parentOf: (Int32) -> Int32? = { parent(of: $0) }) -> [Found] {
        let byPID = Dictionary(matches.map { ($0.found.pid, $0.found) }, uniquingKeysWith: { first, _ in first })
        return matches.filter { match in
            var ancestor = match.parent
            for _ in 0..<4 {
                if let outer = byPID[ancestor], outer.agent == match.found.agent { return false }
                guard ancestor > 1, let next = parentOf(ancestor) else { break }
                ancestor = next
            }
            return true
        }.map(\.found)
    }

    static func isScripted(_ agent: AgentKind, arguments: [String]) -> Bool {
        let words = arguments.dropFirst()
        switch agent {
        case .vibe: return words.contains { $0 == "-p" || $0 == "--prompt" || $0 == "--prompt-file" || $0.hasPrefix("--prompt=") }
        // Global flags can come first: `codex --search exec …`, `codex -c key=value exec …`.
        case .codex: return ["exec", "e"].contains(subcommand(words, valueFlags: codexValueFlags))
        default: return false
        }
    }

    /// Codex's global options that take a value, so their values aren't taken for a subcommand.
    static let codexValueFlags: Set<String> = ["-c", "--config", "-m", "--model", "-p", "--profile", "-s", "--sandbox",
                                                "-a", "--ask-for-approval", "-C", "--cd", "-i", "--image", "--add-dir",
                                                "--enable", "--disable", "--local-provider"]

    /// The first word that isn't an option or an option's value.
    static func subcommand<Words: Collection<String>>(_ words: Words, valueFlags: Set<String>) -> String? {
        var skip = false
        for word in words {
            if skip { skip = false; continue }
            if word == "--" { return nil }
            if word.hasPrefix("-") {
                skip = valueFlags.contains(word)
                continue
            }
            return word
        }
        return nil
    }

    /// A process's children, for agents that run as a small wrapper around the real program.
    static func children(of pid: Int32) -> [Int32] {
        let count = proc_listchildpids(pid, nil, 0)
        guard count > 0 else { return [] }
        var pids = [Int32](repeating: 0, count: Int(count) + 8)
        let filled = pids.withUnsafeMutableBytes { raw in proc_listchildpids(pid, raw.baseAddress, Int32(raw.count)) }
        return Array(pids.prefix(Int(max(0, filled))))
    }

    static func scriptAgent(arguments: [String]) -> AgentKind? {
        for argument in arguments.dropFirst().prefix(3) {
            let lower = argument.lowercased()
            if lower.contains("@github/copilot") || lower.hasSuffix("/copilot") { return .copilot }
            if lower.contains("gemini-cli") || lower.hasSuffix("/gemini") { return .gemini }
            if lower.contains("@openai/codex") || lower.hasSuffix("/codex") { return .codex }
            // Editors host Vibe through its ACP server, a Python script.
            if lower.hasSuffix("/vibe-acp") { return .vibe }
            if lower.hasSuffix("/aider") { return .other }
        }
        return nil
    }

    // MARK: libproc

    static func allPIDs() -> [Int32] {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        var pids = [Int32](repeating: 0, count: Int(count) + 64)
        let filled = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<Int32>.size))
        return Array(pids.prefix(Int(max(0, filled))))
    }

    static func workingFolder(of pid: Int32) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
        let path = withUnsafeBytes(of: info.pvi_cdir.vip_path) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
        return path.isEmpty ? nil : path
    }

    /// A process's parent. A terminal's `login` belongs to root, which
    /// libproc won't describe to us, so fall back on what `ps` reads.
    static func parent(of pid: Int32) -> Int32? {
        if let info = bsdInfo(of: pid) { return Int32(info.pbi_ppid) }
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
        return info.kp_eproc.e_ppid
    }

    /// The terminal a process runs in, such as "/dev/ttys003", to find its tab.
    static func terminalDevice(of pid: Int32) -> String? {
        guard let info = bsdInfo(of: pid), info.e_tdev != UInt32.max, info.e_tdev != 0,
              let name = devname(dev_t(bitPattern: info.e_tdev), S_IFCHR) else { return nil }
        return "/dev/" + String(cString: name)
    }

    /// When a process started, to tell a live session from a reused PID.
    static func startTime(of pid: Int32) -> Date? {
        bsdInfo(of: pid).map(startTime)
    }

    private static func startTime(_ info: proc_bsdinfo) -> Date {
        Date(timeIntervalSince1970: TimeInterval(info.pbi_start_tvsec) + TimeInterval(info.pbi_start_tvusec) / 1_000_000)
    }

    /// The files a process has open whose paths pass `matching`, through
    /// libproc's file descriptors (what `lsof` lists). Only your own processes.
    static func openFiles(of pid: Int32, matching: (String) -> Bool) -> [String] {
        let size = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard size > 0 else { return [] }
        let count = Int(size) / MemoryLayout<proc_fdinfo>.stride
        var fds = [proc_fdinfo](repeating: proc_fdinfo(), count: count + 16)
        let filled = fds.withUnsafeMutableBytes { raw in
            proc_pidinfo(pid, PROC_PIDLISTFDS, 0, raw.baseAddress, Int32(raw.count))
        }
        guard filled > 0 else { return [] }
        var paths: [String] = []
        for fd in fds.prefix(Int(filled) / MemoryLayout<proc_fdinfo>.stride)
        where fd.proc_fdtype == UInt32(PROX_FDTYPE_VNODE) {
            var info = vnode_fdinfowithpath()
            let wanted = Int32(MemoryLayout<vnode_fdinfowithpath>.size)
            guard proc_pidfdinfo(pid, fd.proc_fd, PROC_PIDFDVNODEPATHINFO, &info, wanted) == wanted else { continue }
            let path = withUnsafeBytes(of: info.pvip.vip_path) { raw in
                String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
            }
            if matching(path) { paths.append(path) }
        }
        return paths
    }

    static func cpuTime(of pid: Int32) -> TimeInterval? {
        var info = proc_taskinfo()
        let size = Int32(MemoryLayout<proc_taskinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, size) == size else { return nil }
        return TimeInterval(info.pti_total_user + info.pti_total_system) * timebase / 1_000_000_000
    }

    /// Task times are in Mach time units: nanoseconds on Intel, not on Apple silicon.
    private static let timebase: Double = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info.denom == 0 ? 1 : Double(info.numer) / Double(info.denom)
    }()

    private static func bsdInfo(of pid: Int32) -> proc_bsdinfo? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return info
    }

    private static func processName(_ info: proc_bsdinfo) -> String {
        withUnsafeBytes(of: info.pbi_comm) { raw in String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self) }
    }

    /// A process's arguments, from KERN_PROCARGS2. Its environment, which
    /// follows them, is never read.
    static func arguments(of pid: Int32) -> [String] {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 0 else { return [] }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return [] }
        let argc = buffer.withUnsafeBytes { $0.load(as: Int32.self) }
        var index = MemoryLayout<Int32>.size
        // Skip the executable path and its padding.
        while index < size, buffer[index] != 0 { index += 1 }
        while index < size, buffer[index] == 0 { index += 1 }
        var arguments: [String] = []
        while arguments.count < Int(argc), index < size {
            let start = index
            while index < size, buffer[index] != 0 { index += 1 }
            arguments.append(String(decoding: buffer[start..<index], as: UTF8.self))
            index += 1
        }
        return arguments
    }

    /// The app a process runs in (Terminal, iTerm, VS Code, the Claude app…),
    /// found by walking up its parents.
    @MainActor
    static func hostApp(of pid: Int32) -> NSRunningApplication? {
        var current: Int32? = pid
        for _ in 0..<16 {
            guard let this = current, this > 1 else { return nil }
            if let app = NSRunningApplication(processIdentifier: this), app.activationPolicy == .regular {
                return app
            }
            current = parent(of: this)
        }
        return nil
    }
}
