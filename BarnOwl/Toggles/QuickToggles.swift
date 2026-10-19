import AppKit
import CoreAudio

/// One-click system switches shown in Barn Owl's menu.
@MainActor
enum QuickToggles {
    // MARK: Dark mode

    static var isDarkMode: Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    /// System Events is the only public way to switch appearance. The first
    /// use asks for Automation permission.
    /// Runs in osascript, off the main thread: the first time, macOS asks for
    /// permission, and Barn Owl stays responsive while it does.
    static func toggleDarkMode() {
        let source = "tell application \"System Events\" to tell appearance preferences to set dark mode to not dark mode"
        Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", source]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
                process.waitUntilExit()
                if process.terminationStatus != 0 { Log.app.error("Dark mode toggle failed (\(process.terminationStatus))") }
            } catch {
                Log.app.error("Dark mode toggle failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: Microphone

    /// Whether the default microphone is muted (or turned all the way down,
    /// for devices without a mute control).
    static var isMicrophoneMuted: Bool {
        guard let device = defaultInputDevice else { return false }
        if let muted: UInt32 = inputProperty(device, kAudioDevicePropertyMute) { return muted != 0 }
        if let volume: Float32 = inputProperty(device, kAudioDevicePropertyVolumeScalar) { return volume == 0 }
        return false
    }

    private static var volumeBeforeMute: Float32 = 0.75

    static func toggleMicrophone() {
        guard let device = defaultInputDevice else { return }
        let mute = !isMicrophoneMuted
        if setInputProperty(device, kAudioDevicePropertyMute, UInt32(mute ? 1 : 0)) { return }
        // No mute control: use the input volume instead, and restore it after.
        if mute, let volume: Float32 = inputProperty(device, kAudioDevicePropertyVolumeScalar), volume > 0 {
            volumeBeforeMute = volume
        }
        _ = setInputProperty(device, kAudioDevicePropertyVolumeScalar, mute ? Float32(0) : volumeBeforeMute)
    }

    private static var defaultInputDevice: AudioDeviceID? {
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size,
                                         &device) == noErr, device != 0 else { return nil }
        return device
    }

    private static func inputProperty<T: BitwiseCopyable>(_ device: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> T? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioDevicePropertyScopeInput,
                                                 mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectHasProperty(device, &address) else { return nil }
        var size = UInt32(MemoryLayout<T>.size)
        let pointer = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { pointer.deallocate() }
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, pointer) == noErr else { return nil }
        return pointer.pointee
    }

    private static func setInputProperty<T: BitwiseCopyable>(_ device: AudioDeviceID, _ selector: AudioObjectPropertySelector,
                                            _ value: T) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioDevicePropertyScopeInput,
                                                 mElement: kAudioObjectPropertyElementMain)
        var settable: DarwinBoolean = false
        guard AudioObjectHasProperty(device, &address),
              AudioObjectIsPropertySettable(device, &address, &settable) == noErr, settable.boolValue else {
            return false
        }
        var value = value
        return AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<T>.size), &value) == noErr
    }

    // MARK: Display

    static func sleepDisplay() {
        run("/usr/bin/pmset", ["displaysleepnow"])
    }

    // MARK: Finder settings

    /// Hidden by Barn Owl's cover, or by Finder's own setting (how earlier
    /// versions hid them).
    static var desktopIconsHidden: Bool {
        DesktopCover.shared.isShown || !finderBool("CreateDesktop", default: true)
    }

    static func toggleDesktopIcons() {
        if !finderBool("CreateDesktop", default: true) {
            // Hidden the old way: give Finder its desktop back.
            setFinderBool("CreateDesktop", true)
        } else if DesktopCover.shared.isShown {
            DesktopCover.shared.hide()
        } else {
            DesktopCover.shared.show()
        }
    }

    static var hiddenFilesShown: Bool {
        finderBool("AppleShowAllFiles", default: false)
    }

    static func toggleHiddenFiles() {
        setFinderBool("AppleShowAllFiles", !hiddenFilesShown)
    }

    private static func finderBool(_ key: String, default defaultValue: Bool) -> Bool {
        CFPreferencesAppSynchronize("com.apple.finder" as CFString)
        let value = CFPreferencesCopyAppValue(key as CFString, "com.apple.finder" as CFString)
        if let number = value as? NSNumber { return number.boolValue }
        if let string = value as? String { return ["1", "true", "yes"].contains(string.lowercased()) }
        return defaultValue
    }

    /// Writes through `defaults` so cfprefsd sees the change, then restarts
    /// Finder, which only reads these settings at launch.
    private static func setFinderBool(_ key: String, _ value: Bool) {
        run("/usr/bin/defaults", ["write", "com.apple.finder", key, "-bool", value ? "true" : "false"])
        restartFinder()
    }

    /// Asks Finder to quit, so it saves its windows and where the desktop
    /// icons are, and only forces it after a few seconds. Then opens it again.
    private static func restartFinder() {
        guard let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first
        else { return openFinder() }
        finder.terminate()
        Task {
            for _ in 0..<30 where !finder.isTerminated {
                try? await Task.sleep(for: .milliseconds(100))
            }
            if !finder.isTerminated { finder.forceTerminate() }
            try? await Task.sleep(for: .milliseconds(300))
            openFinder()
        }
    }

    private static func openFinder() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.finder") else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }

    private static func run(_ path: String, _ arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            Log.app.error("\(path) failed: \(error.localizedDescription)")
        }
    }
}
