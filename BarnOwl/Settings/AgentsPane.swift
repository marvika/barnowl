import SwiftUI

/// Settings → Agents: which agents Barn Owl sees, what it tells you, and
/// what's hidden or muted.
struct AgentsPane: View {
    let model: AppModel
    @AppStorage(PrefKey.agentsEnabled) private var enabled = true
    @AppStorage(PrefKey.agentsMenuBar) private var menuBar = true
    @AppStorage(PrefKey.agentsNotifyNeedsYou) private var notifyNeedsYou = true
    @AppStorage(PrefKey.agentsNotifyDone) private var notifyDone = true
    @AppStorage(PrefKey.agentsNotifyAfterMinutes) private var notifyAfter = 3
    @AppStorage(PrefKey.agentsEditor) private var editor = ""
    @AppStorage(PrefKey.agentsHideScripted) private var hideScripted = true
    @AppStorage(PrefKey.agentsHideScratch) private var hideScratch = true
    @AppStorage(PrefKey.agentsShowLimits) private var showLimits = true
    @AppStorage(PrefKey.agentsLimitAlerts) private var limitAlerts = true
    @AppStorage(PrefKey.agentsIsland) private var island = IslandMode.attention
    @State private var relayOn = false
    @State private var detected: [Detected] = []
    @State private var relayPreview: (before: String, after: String)?
    @State private var relayError: String?
    @State private var answersOn = false
    @AppStorage(PrefKey.roostSky) private var sky = RoostSky.follow
    @State private var answersPreview: (before: String, after: String)?

    private var agents: AgentWatcher { model.agents }

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $enabled) {
                    BadgeLabel(title: "Show coding agents as owlets",
                               subtitle: "Claude Code, Codex, Mistral Vibe, Copilot CLI, OpenCode and other agents, in the quick panel.",
                               symbol: "bird.fill", color: .orange)
                }
                Toggle(isOn: $menuBar) {
                    BadgeLabel(title: "Show an owlet beside the owl in the menu bar",
                               subtitle: "While agents work, and when one needs you.",
                               symbol: "menubar.rectangle", color: .blue)
                }
                .disabled(!enabled)
                Picker(selection: $island) {
                    ForEach(IslandMode.allCases) { Text($0.title).tag($0) }
                } label: {
                    BadgeLabel(title: "Show at the notch",
                               subtitle: "A small island that grows out of the notch, or hangs from the top of the screen.",
                               symbol: "capsule.fill", color: .indigo)
                }
                .disabled(!enabled)
                LabeledContent {
                    if answersOn {
                        Button("Turn Off") { setAnswers(false) }
                    } else {
                        Button("Turn On…") {
                            do { answersPreview = try IslandAnswers.preview() } catch { relayError = Self.relayMessage(error) }
                        }
                        .disabled(!enabled || island == .off)
                    }
                } label: {
                    BadgeLabel(title: "Answer from the island",
                               subtitle: answersOn
                                   ? "On: allow or deny Claude Code's requests, and pick an answer to its questions, in the island."
                                   : "Allow or deny Claude Code's requests and answer its questions without switching apps.",
                               symbol: "hand.tap.fill", color: .green)
                }
            } footer: {
                Text("Barn Owl reads the agents' own session files on this Mac, in ~/.claude, ~/.codex and the Claude app's folder. It shows each session's title, state, folder and branch and, while one waits on you, the command, file or question it's asking. It never keeps your prompts or replies, never reads your login, and nothing leaves your Mac.")
            }

            if !enabled && (relayOn || answersOn) {
                Section {
                    LabeledContent {
                        Button("Remove") {
                            if relayOn { setRelay(false) }
                            if answersOn { setAnswers(false) }
                        }
                    } label: {
                        BadgeLabel(title: "Barn Owl is still in Claude Code's settings",
                                   subtitle: relayOn && answersOn ? "The status line relay and the island's hooks. Harmless, but you may want them gone."
                                       : relayOn ? "The status line relay. Harmless, but you may want it gone."
                                       : "The island's hooks. Harmless, but you may want them gone.",
                                   symbol: "gearshape.2", color: .gray)
                    }
                }
            }

            Section("On this Mac") {
                ForEach(detected, id: \.kind) { agent in
                    LabeledContent {
                        Text(agent.status).foregroundStyle(.secondary)
                    } label: {
                        HStack(spacing: 10) {
                            OwletIcon(icon: "typing", palette: agent.kind.palette, scale: 2)
                                .padding(2)
                                .background(Brand.indigoDeep, in: .rect(cornerRadius: 7))
                            Text(agent.kind.name)
                        }
                    }
                }
            }
            .disabled(!enabled)

            Section {
                Toggle(isOn: $notifyNeedsYou) {
                    BadgeLabel(title: "When an agent needs you",
                               subtitle: "A permission prompt, a question, or stuck after failures.",
                               symbol: "hand.raised.fill", color: .orange)
                }
                Toggle(isOn: $notifyDone) {
                    BadgeLabel(title: "When a long task finishes",
                               symbol: "checkmark.circle.fill", color: .green)
                }
                Picker(selection: $notifyAfter) {
                    ForEach([2, 3, 5, 10, 30], id: \.self) { Text("\($0) min").tag($0) }
                } label: {
                    BadgeLabel(title: "Long means at least", symbol: "timer", color: .gray)
                }
                .disabled(!notifyDone)
            } header: {
                Text("Notifications")
            } footer: {
                Text("Notifications come only when the island can't show it (you're presenting, in full screen, or the island is off) or you've been away, and never for a session whose window is in front of you.")
            }
            .disabled(!enabled)

            Section {
                Picker(selection: $editor) {
                    let installed = AgentActions.installedEditors
                    if installed.isEmpty { Text("Finder").tag("") }
                    ForEach(installed) { Text($0.name).tag($0.bundleIdentifier) }
                    if !editor.isEmpty, !installed.contains(where: { $0.bundleIdentifier == editor }) {
                        Text("Not installed").tag(editor)
                    }
                } label: {
                    BadgeLabel(title: "Open projects in", subtitle: "A worktree session opens its own folder.",
                               symbol: "chevron.left.forwardslash.chevron.right", color: .blue)
                }
                Picker(selection: $sky) {
                    ForEach(RoostSky.allCases) { Text($0.title).tag($0) }
                } label: {
                    BadgeLabel(title: "The Roost's sky", subtitle: "Behind the tree: the time of day, or always the same.",
                               symbol: "moon.stars.fill", color: .indigo)
                }
                LabeledContent {
                    Button("Open Roost") { model.showRoost(nil) }
                } label: {
                    BadgeLabel(title: "The Roost", subtitle: "Every agent on this Mac, what needs you, and how today went.",
                               symbol: "bird", color: .orange)
                }
                LabeledContent {
                    Button("Open Rules") { model.showSettings(.keepAwake) }
                } label: {
                    BadgeLabel(title: "Keep awake while an agent is working",
                               subtitle: "A rule in Keep Awake. Sleeps 5 minutes after the last one stops.",
                               symbol: "eyes", color: .orange)
                }
            }
            .disabled(!enabled)

            Section {
                Toggle(isOn: $showLimits) {
                    BadgeLabel(title: "Show plan limits",
                               subtitle: "Claude's and Codex's 5-hour and weekly windows, under the owlets.",
                               symbol: "gauge.with.dots.needle.67percent", color: .purple)
                }
                .disabled(!enabled)
                Toggle(isOn: $limitAlerts) {
                    BadgeLabel(title: "Tell me at 80%, and when a limit resets",
                               symbol: "bell.badge.fill", color: .red)
                }
                .disabled(!showLimits || !enabled)
                LabeledContent {
                    if relayOn {
                        Button("Turn Off") { setRelay(false) }
                    } else {
                        Button("Turn On…") {
                            do { relayPreview = try StatusLineRelay.preview() } catch { relayError = Self.relayMessage(error) }
                        }
                        .disabled(!showLimits || !enabled)
                    }
                } label: {
                    BadgeLabel(title: "Reset times for Claude",
                               subtitle: relayOn ? "On: Claude Code in a terminal passes them to Barn Owl as it works. The Claude app's Code tab has no status line, so it doesn't."
                                   : "Claude Code in a terminal can pass them on through its status line. Your status line stays as it is.",
                               symbol: "clock.arrow.circlepath", color: .orange)
                }
            } header: {
                Text("Plan limits")
            } footer: {
                Text("Claude's limits come from the Claude app's own usage history, which it saves now and then, and from the status line when that's on. Codex's come from its session logs. An old reading shows as \"as of\" with its time. Barn Owl never asks a server and never reads your login.")
            }
            .sheet(isPresented: Binding(get: { relayPreview != nil }, set: { if !$0 { relayPreview = nil } })) {
                if let relayPreview {
                    SettingsChangeSheet(
                        title: "Get reset times from Claude Code",
                        message: "Barn Owl will change the status line setting in ~/.claude/settings.json, after saving a backup beside it. Your own status line still shows as before. Turn it off any time to put it back.",
                        before: relayPreview.before, after: relayPreview.after) {
                        self.relayPreview = nil
                        setRelay(true)
                    } cancel: {
                        self.relayPreview = nil
                    }
                }
            }
            .sheet(isPresented: Binding(get: { answersPreview != nil }, set: { if !$0 { answersPreview = nil } })) {
                if let answersPreview {
                    SettingsChangeSheet(
                        title: "Answer Claude Code from the island",
                        message: "Barn Owl will add two hooks to ~/.claude/settings.json, after saving a backup beside it. When Claude Code asks for permission or asks you a question, the island offers Allow Once, Deny and Always Allow, or the question's options. Nothing is allowed without your click; Always Allow adds only the rule Claude Code itself suggests, as its \"don't ask again\" would. Barn Owl steps aside for the usual prompt whenever you're in that session's app, choose Answer in Terminal, or Barn Owl isn't running. Turn it off any time to remove the hooks.",
                        before: answersPreview.before, after: answersPreview.after) {
                        self.answersPreview = nil
                        setAnswers(true)
                    } cancel: {
                        self.answersPreview = nil
                    }
                }
            }
            .alert("Couldn't change Claude Code's settings", isPresented: Binding(get: { relayError != nil },
                                                                                  set: { if !$0 { relayError = nil } })) {
                Button("OK") { relayError = nil }
            } message: {
                Text(relayError ?? "")
            }

            Section {
                Toggle(isOn: $hideScripted) {
                    BadgeLabel(title: "Hide scripted sessions",
                               subtitle: "Runs from scripts, CI and the Agent SDK, such as claude -p.",
                               symbol: "terminal.fill", color: .gray)
                }
                Toggle(isOn: $hideScratch) {
                    BadgeLabel(title: "Hide scratch folders",
                               subtitle: "Temporary folders and the Claude app's scratch workspaces.",
                               symbol: "folder.badge.minus", color: .gray)
                }
                ForEach(Array(agents.choices.hiddenFolders).sorted(), id: \.self) { path in
                    LabeledContent {
                        Button("Show Again") { agents.choices.showFolder(path) }
                    } label: {
                        Text((path as NSString).abbreviatingWithTildeInPath)
                        Text("Always hidden")
                    }
                }
                ForEach(Array(agents.choices.mutedFolders).sorted(), id: \.self) { path in
                    LabeledContent {
                        Button("Unmute") { agents.choices.setMuted(false, folder: path) }
                    } label: {
                        Text((path as NSString).abbreviatingWithTildeInPath)
                        Text("Muted: shown, but never notifies")
                    }
                }
            } header: {
                Text("Hidden and muted")
            } footer: {
                Text("Right-click an owlet in the quick panel to hide, mute or open it.")
            }
            .disabled(!enabled)
        }
        .task { await lookAround() }
        .onChange(of: agents.all.map(\.agent)) { refreshDetected() }
    }

    private func setRelay(_ on: Bool) {
        do {
            try on ? StatusLineRelay.turnOn() : StatusLineRelay.turnOff()
        } catch {
            relayError = Self.relayMessage(error)
        }
        relayOn = StatusLineRelay.isOn()
    }

    private func setAnswers(_ on: Bool) {
        do {
            try on ? IslandAnswers.turnOn() : IslandAnswers.turnOff()
        } catch {
            relayError = Self.relayMessage(error)
        }
        answersOn = IslandAnswers.isOn()
        agents.setAnswering(answersOn)
    }

    static func relayMessage(_ error: Error) -> String {
        switch error as? StatusLineRelay.Failure {
        case .unreadableSettings:
            "~/.claude/settings.json isn't valid JSON, so Barn Owl left it alone. Fix it and try again."
        case .notInstalled:
            "Move Barn Owl to your Applications folder first, so Claude Code can always find it."
        default:
            "Barn Owl couldn't write ~/.claude/settings.json. Nothing was changed."
        }
    }

    private struct Detected {
        let kind: AgentKind
        let status: String
    }

    /// Which agents are installed, looked up once when the pane appears.
    @State private var installed: [AgentKind: Bool] = [:]

    private func lookAround() async {
        let found = await Task.detached { () -> ([AgentKind: Bool], Bool, Bool) in
            let home = FileManager.default.homeDirectoryForCurrentUser
            func exists(_ path: String) -> Bool { FileManager.default.fileExists(atPath: home.appending(path: path).path) }
            let installed: [AgentKind: Bool] = [
                .claude: FileManager.default.fileExists(atPath: ClaudeSource.home.path),
                .codex: FileManager.default.fileExists(atPath: CodexSource.home.path),
                .copilot: exists(".copilot"),
                .opencode: exists(".local/share/opencode") || exists(".config/opencode"),
                .gemini: exists(".gemini"),
                .vibe: FileManager.default.fileExists(atPath: VibeSource.home.path),
            ]
            return (installed, StatusLineRelay.isOn(), IslandAnswers.isOn())
        }.value
        installed = found.0
        relayOn = found.1
        answersOn = found.2
        refreshDetected()
    }

    private func refreshDetected() {
        detected = [AgentKind.claude, .codex, .vibe, .copilot, .opencode, .gemini].map { kind in
            let running = agents.all.filter { $0.agent == kind }.count
            let status = running > 0 ? "\(running) running" : (installed[kind] == true ? "Found" : "Not found")
            return Detected(kind: kind, status: status)
        }
    }
}

/// Shows exactly what a change to Claude Code's settings does, before it's made.
private struct SettingsChangeSheet: View {
    let title: String
    let message: String
    let before: String
    let after: String
    let confirm: () -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.headline)
            Text(message).fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .top, spacing: 12) {
                snippet("Now", before)
                snippet("After", after)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: cancel).keyboardShortcut(.cancelAction)
                Button("Turn On", action: confirm).keyboardShortcut(.defaultAction).buttonStyle(.glassProminent)
            }
        }
        .padding(20)
        .frame(width: 560)
    }

    private func snippet(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ScrollView {
                Text(text).font(.caption.monospaced()).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 110)
            .padding(8)
            .background(Color.primary.opacity(0.05), in: .rect(cornerRadius: 8))
        }
    }
}
