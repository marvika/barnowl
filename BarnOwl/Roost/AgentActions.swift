import AppKit

/// Taking you to a session: its window, its folder in your editor, Terminal or Finder.
@MainActor
enum AgentActions {
    static let claudeApp = "com.anthropic.claudefordesktop"

    /// Brings the app the session runs in to the front: in Terminal and
    /// iTerm, the very tab it runs in (macOS asks once for permission).
    static func show(_ session: AgentSession) {
        // Going there to answer: a request held for the island goes back to the usual prompt.
        if let ask = session.pendingAsk { IslandAnswers.reply(.pass, to: ask) }
        // A chat in the Claude app opens itself, in whichever window holds it.
        if let chat = session.appChat, let link = ClaudeAppChats.link(to: chat),
           NSWorkspace.shared.urlForApplication(toOpen: link) != nil {
            NSWorkspace.shared.open(link)
            return
        }
        if let pid = session.hostPID, let app = NSRunningApplication(processIdentifier: pid) {
            if let agent = session.pid, let tty = ProcessScan.terminalDevice(of: agent),
               let script = tabScript(bundle: app.bundleIdentifier, tty: tty) {
                run(script)
            }
            app.activate()
            return
        }
        // Only a session started in the Claude app lives there.
        if session.appChat != nil || session.host == "Claude",
           let app = NSRunningApplication.runningApplications(withBundleIdentifier: claudeApp).first {
            app.activate()
            return
        }
        openInEditor(session)
    }

    /// AppleScript that selects the tab running on `tty`, for the terminals that can.
    static func tabScript(bundle: String?, tty: String) -> String? {
        let device = tty.replacingOccurrences(of: "\"", with: "")
        switch bundle {
        case "com.apple.Terminal":
            return """
            tell application "Terminal"
                repeat with w in windows
                    repeat with t in tabs of w
                        if tty of t is "\(device)" then
                            set selected of t to true
                            set index of w to 1
                        end if
                    end repeat
                end repeat
            end tell
            """
        case "com.googlecode.iterm2":
            return """
            tell application "iTerm2"
                repeat with w in windows
                    repeat with t in tabs of w
                        repeat with s in sessions of t
                            if tty of s is "\(device)" then
                                select w
                                tell t to select
                                tell s to select
                            end if
                        end repeat
                    end repeat
                end repeat
            end tell
            """
        default:
            return nil
        }
    }

    /// In osascript, off the main thread: the first time, macOS asks whether
    /// Barn Owl may control that terminal.
    private static func run(_ script: String) {
        Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try? process.run()
            process.waitUntilExit()
        }
    }

    // MARK: Editors

    struct Editor: Identifiable, Hashable, Sendable {
        let bundleIdentifier: String
        let name: String
        var id: String { bundleIdentifier }
    }

    /// Editors that open a folder as a project, most popular first.
    static let knownEditors: [Editor] = [
        Editor(bundleIdentifier: "com.microsoft.VSCode", name: "VS Code"),
        Editor(bundleIdentifier: "com.todesktop.230313mzl4w4u92", name: "Cursor"),
        Editor(bundleIdentifier: "dev.zed.Zed", name: "Zed"),
        Editor(bundleIdentifier: "com.apple.dt.Xcode", name: "Xcode"),
        Editor(bundleIdentifier: "com.exafunction.windsurf", name: "Windsurf"),
        Editor(bundleIdentifier: "com.microsoft.VSCodeInsiders", name: "VS Code Insiders"),
        Editor(bundleIdentifier: "com.jetbrains.intellij", name: "IntelliJ IDEA"),
        Editor(bundleIdentifier: "com.jetbrains.intellij.ce", name: "IntelliJ IDEA CE"),
        Editor(bundleIdentifier: "com.jetbrains.pycharm", name: "PyCharm"),
        Editor(bundleIdentifier: "com.jetbrains.WebStorm", name: "WebStorm"),
        Editor(bundleIdentifier: "com.jetbrains.goland", name: "GoLand"),
        Editor(bundleIdentifier: "com.sublimetext.4", name: "Sublime Text"),
        Editor(bundleIdentifier: "com.panic.Nova", name: "Nova"),
        Editor(bundleIdentifier: "com.barebones.bbedit", name: "BBEdit"),
    ]

    /// The known editors installed on this Mac, looked up at most once a minute.
    static var installedEditors: [Editor] {
        if let cached = editorCache, Date().timeIntervalSince(cached.at) < 60 { return cached.editors }
        let editors = knownEditors.filter {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.bundleIdentifier) != nil
        }
        editorCache = (editors, Date())
        return editors
    }

    private static var editorCache: (editors: [Editor], at: Date)?

    /// The one picked in Settings, or the first installed.
    static var editor: Editor? {
        let installed = installedEditors
        return installed.first { $0.bundleIdentifier == Preferences.agentsEditor } ?? installed.first
    }

    /// Opens the session's folder (its own worktree, if it's in one).
    static func openInEditor(_ session: AgentSession) {
        guard let editor, let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: editor.bundleIdentifier) else {
            return revealInFinder(session)
        }
        NSWorkspace.shared.open([session.folder], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    }

    static func openInTerminal(_ session: AgentSession) {
        guard let terminal = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") else { return }
        NSWorkspace.shared.open([session.folder], withApplicationAt: terminal, configuration: NSWorkspace.OpenConfiguration())
    }

    static func revealInFinder(_ session: AgentSession) {
        NSWorkspace.shared.activateFileViewerSelecting([session.folder])
    }
}
