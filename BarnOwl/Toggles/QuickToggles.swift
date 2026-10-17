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
    static func toggleDarkMode() {
        let source = "tell application \"System Events\" to tell appearance preferences to set dark mode to not dark mode"
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {
            Log.app.error("Dark mode toggle failed: \(error)")
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

    static var desktopIconsHidden: Bool {
        !finderBool("CreateDesktop", default: true)
    }

    static func toggleDesktopIcons() {
        setFinderBool("CreateDesktop", desktopIconsHidden)
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
        run("/usr/bin/killall", ["Finder"])
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
