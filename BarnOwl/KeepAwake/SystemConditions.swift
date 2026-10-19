import AppKit
import CoreAudio
import IOKit.ps

/// Reads the things keep-awake rules depend on. Each read is cheap enough to
/// run every few seconds.
enum SystemConditions {
    // MARK: Power

    struct PowerState: Equatable, Sendable {
        var onAC: Bool
        /// 0–100, or nil on a Mac without a battery.
        var batteryPercent: Int?
    }

    static func power() -> PowerState {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else {
            return PowerState(onAC: true, batteryPercent: nil)
        }
        let providing = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String?
        var percent: Int?
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue()
                    as? [String: Any],
                  (description[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType,
                  let current = description[kIOPSCurrentCapacityKey] as? Int,
                  let max = description[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }
            percent = current * 100 / max
        }
        return PowerState(onAC: providing == kIOPSACPowerValue, batteryPercent: percent)
    }

    // MARK: Displays

    @MainActor
    static var hasExternalDisplay: Bool {
        NSScreen.screens.contains { screen in
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
            else { return false }
            return CGDisplayIsBuiltin(id) == 0
        }
    }

    // MARK: Microphone

    /// Whether any app is using the default microphone: a call, a recording,
    /// dictation. Doesn't say which app, and needs no permission.
    static var isMicrophoneInUse: Bool {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size,
                                         &deviceID) == noErr, deviceID != 0 else { return false }
        var running: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        address.mSelector = kAudioDevicePropertyDeviceIsRunningSomewhere
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &running) == noErr else { return false }
        return running != 0
    }

    // MARK: Downloads

    /// File extensions browsers and download tools use for unfinished files.
    static let partialExtensions: Set<String> = ["download", "crdownload", "part", "partial", "opdownload", "tmp"]

    /// Whether the Downloads folder has an unfinished download in it.
    static var isDownloading: Bool {
        guard let folder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first,
              let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return false }
        return names.contains { partialExtensions.contains(($0 as NSString).pathExtension.lowercased()) }
    }

    // MARK: Apps

    @MainActor
    static func isRunning(_ bundleIdentifier: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
    }

    // MARK: Idle time

    /// Seconds since the last keyboard or mouse input.
    static var secondsSinceInput: TimeInterval {
        [CGEventType.mouseMoved, .keyDown, .leftMouseDown, .rightMouseDown, .leftMouseDragged, .scrollWheel]
            .map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }
            .min() ?? 0
    }
}

/// Whether the user is in the middle of using the mouse or keyboard, so
/// Barn Owl can keep its hands off the pointer until they pause.
enum UserActivity {
    /// How long without input counts as a pause.
    static let pause: TimeInterval = 2.5

    @MainActor static var isIdle: Bool {
        SystemConditions.secondsSinceInput >= pause && !ItemMover.isAnyMouseButtonHeld
    }

    /// Waits for a pause in the user's input; false if none came in time.
    @MainActor static func waitUntilIdle(timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !isIdle {
            guard Date() < deadline, !Task.isCancelled else { return false }
            try? await Task.sleep(for: .milliseconds(250))
        }
        return true
    }
}
