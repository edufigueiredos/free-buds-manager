import Foundation
import AppKit
import CoreAudio
import ApplicationServices

/// Pausing and resuming the Mac's music when an earbud comes out.
///
/// The earbuds never tell the Mac to pause (no AVRCP command arrives), so the app does it: it checks which
/// processes are playing to the earbuds and pauses them.
///
/// * Music and Spotify are asked to pause by name (AppleScript, the Automation permission). That targets the
///   app that is really making the sound.
/// * Anything else (a browser tab, a video player) gets the Play/Pause media key (the Accessibility
///   permission). The key goes to whichever app owns "Now Playing", which may not be the one making the sound,
///   so the effect is checked afterwards and undone if it started another app.
/// * Call apps are ignored: taking an earbud out during a call must not press Play/Pause.
public enum MacPlayback {
    /// Players that can be paused and resumed by name, with no media key.
    static let scriptablePlayers: Set<String> = ["com.apple.Music", "com.spotify.client"]

    /// Apps whose sound is a call, not music.
    static let callAppPrefixes = ["com.microsoft.teams", "us.zoom", "com.apple.avconferenced",
                                  "com.apple.FaceTime", "com.cisco.webex"]

    static func countsAsMusic(_ bundle: String) -> Bool {
        !callAppPrefixes.contains { bundle.hasPrefix($0) }
    }

    /// What `pause` stopped, so `resume` starts only that.
    public struct PausedMedia: Equatable {
        public var players: [String] = []
        public var byKey = false
        public var isEmpty: Bool { players.isEmpty && !byKey }
        public init() {}
    }

    /// Sending a media key needs the Accessibility permission.
    public static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt for the Accessibility permission (once per launch is plenty).
    public static func requestTrust() {
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    /// Clears this app's old Accessibility entry, then asks again.
    ///
    /// macOS binds the permission to the exact build that received it, so after an update the switch in System
    /// Settings still looks on while it no longer applies. Resetting the entry (only this app's) and asking
    /// again makes the new build the one that is allowed.
    public static func repairAndRequestAccess() {
        let reset = Process()
        reset.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        reset.arguments = ["reset", "Accessibility", Bundle.main.bundleIdentifier ?? "io.github.edufigueiredos.FreeBudsManager"]
        try? reset.run()
        reset.waitUntilExit()
        requestTrust()
    }

    public static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// True when the earbuds are the Mac's output and some app is playing sound through them.
    public static func isPlaying(to deviceName: String) -> Bool {
        !playingBundles(to: deviceName).isEmpty
    }

    /// Bundle ids of the apps playing sound while the earbuds are the Mac's output (call apps left out).
    /// An app whose id is unknown shows up as "unknown".
    public static func playingBundles(to deviceName: String) -> [String] {
        guard let output = defaultOutputDevice(), name(of: output).lowercased().contains(deviceName.lowercased()) ||
                deviceName.lowercased().contains(name(of: output).lowercased()) else { return [] }

        if #available(macOS 14.2, *) {
            let bundles = processIDs()
                .filter { property($0, kAudioProcessPropertyIsRunningOutput) == 1 }
                .map { bundleID(of: $0) ?? "unknown" }
            return Array(Set(bundles)).filter(countsAsMusic).sorted()
        }
        return property(output, kAudioDevicePropertyDeviceIsRunningSomewhere) == 1 ? ["unknown"] : []
    }

    /// Pauses what is playing. `playing` is `playingBundles(to:)` taken a moment ago.
    @MainActor
    public static func pause(_ playing: [String], deviceName: String,
                             verifyAfter: Duration = .milliseconds(700)) async -> PausedMedia {
        var paused = PausedMedia()
        var needsKey = false
        for bundle in playing {
            if scriptablePlayers.contains(bundle), tell(bundle, "pause") {
                paused.players.append(bundle)
            } else {
                needsKey = true
            }
        }
        guard needsKey, isTrusted else { return paused }

        sendPlayPause()
        try? await Task.sleep(for: verifyAfter)

        let after = Set(playingBundles(to: deviceName))
        let before = Set(playing)
        paused.byKey = playing.contains { !paused.players.contains($0) && !after.contains($0) }
        for bundle in after {
            if scriptablePlayers.contains(bundle) {
                // The key missed the player that is making the sound: pause it by name.
                if tell(bundle, "pause"), !paused.players.contains(bundle) { paused.players.append(bundle) }
            } else if !before.contains(bundle) {
                sendPlayPause() // the key started another app: undo it
            }
        }
        return paused
    }

    /// Starts again only what `pause` stopped.
    @MainActor
    public static func resume(_ paused: PausedMedia) {
        for bundle in paused.players { _ = tell(bundle, "play") }
        if paused.byKey, isTrusted { sendPlayPause() }
    }

    /// Tells a player to pause or play. Never launches it: an app that has quit is left alone.
    @MainActor
    private static func tell(_ bundle: String, _ verb: String) -> Bool {
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: bundle).isEmpty else { return false }
        var error: NSDictionary?
        _ = NSAppleScript(source: "tell application id \"\(bundle)\" to \(verb)")?.executeAndReturnError(&error)
        return error == nil
    }

    /// Sends one press of the Play/Pause media key.
    public static func sendPlayPause() {
        let key = 16 // NX_KEYTYPE_PLAY
        for down in [true, false] {
            let state = down ? 0xA : 0xB
            let event = NSEvent.otherEvent(with: .systemDefined, location: .zero,
                                           modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(state << 8)),
                                           timestamp: 0, windowNumber: 0, context: nil, subtype: 8,
                                           data1: (key << 16) | (state << 8), data2: -1)
            event?.cgEvent?.post(tap: .cghidEventTap)
        }
    }

    // MARK: - CoreAudio

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    private static func defaultOutputDevice() -> AudioObjectID? {
        var addr = address(kAudioHardwarePropertyDefaultOutputDevice)
        var device = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &device) == noErr,
              device != 0 else { return nil }
        return device
    }

    private static func name(of device: AudioObjectID) -> String {
        var addr = address(kAudioObjectPropertyName)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &value) == noErr, let value else { return "" }
        return value.takeRetainedValue() as String
    }

    private static func property(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> UInt32? {
        var addr = address(selector)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(object, &addr, 0, nil, &size, &value) == noErr ? value : nil
    }

    @available(macOS 14.2, *)
    private static func bundleID(of process: AudioObjectID) -> String? {
        var addr = address(kAudioProcessPropertyBundleID)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(process, &addr, 0, nil, &size, &value) == noErr, let value else { return nil }
        let id = value.takeRetainedValue() as String
        return id.isEmpty ? nil : id
    }

    @available(macOS 14.2, *)
    private static func processIDs() -> [AudioObjectID] {
        var addr = address(kAudioHardwarePropertyProcessObjectList)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }
}
