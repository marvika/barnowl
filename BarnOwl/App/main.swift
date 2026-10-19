import AppKit

// Run by Claude Code as its status line (save the plan limits) or as a hook
// (pass an answer from the island); each exits without starting the app.
StatusLineRelay.runIfRequested()
IslandAnswers.runIfRequested()
IconRenderer.runIfRequested()

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
