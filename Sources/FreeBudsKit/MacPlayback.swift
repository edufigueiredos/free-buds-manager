import Foundation
import AppKit
import CoreAudio
import ApplicationServices

/// Pausing and resuming the Mac's music when an earbud comes out.
///
/// The earbuds never tell the Mac to pause (no AVRCP command arrives), so the app does it: it checks whether
/// any process is playing to the earbuds and, if so, sends the Play/Pause media key.
public enum MacPlayback {
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
        guard let output = defaultOutputDevice(), name(of: output).lowercased().contains(deviceName.lowercased()) ||
                deviceName.lowercased().contains(name(of: output).lowercased()) else { return false }

        if #available(macOS 14.2, *) {
            return processIDs().contains { property($0, kAudioProcessPropertyIsRunningOutput) == 1 }
        }
        return property(output, kAudioDevicePropertyDeviceIsRunningSomewhere) == 1
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
