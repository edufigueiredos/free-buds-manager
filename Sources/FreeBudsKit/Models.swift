import Foundation

public enum ANCMode: Int, CaseIterable, Identifiable, Sendable {
    case off = 0
    case cancellation = 1
    case awareness = 2

    public var id: Int { rawValue }
}

/// Noise-cancelling strength. Declaration order is the order shown in the UI.
public enum CancellationLevel: Int, CaseIterable, Identifiable, Sendable {
    case comfort = 1
    case normal = 0
    case ultra = 2
    case dynamic = 3

    public var id: Int { rawValue }
}

public enum AwarenessLevel: Int, CaseIterable, Identifiable, Sendable {
    case normal = 2
    case voiceBoost = 1
    case adaptive = 4

    public var id: Int { rawValue }
}

public struct ANCState: Equatable, Sendable {
    public var mode: ANCMode?
    public var cancellationLevel: CancellationLevel?
    public var awarenessLevel: AwarenessLevel?
    /// How much outside noise adaptive awareness lets in: `0` more noise … `10` less noise (default `5`).
    public var adaptiveIntensity: Int?

    public init() {}
}

public struct BatteryState: Equatable, Sendable {
    public var global: Int?
    public var left: Int?
    public var right: Int?
    public var caseLevel: Int?
    public var chargingLeft = false
    public var chargingRight = false
    public var chargingCase = false

    public init() {}

    /// What to show in the menu bar: the weakest earbud, or the overall level.
    public var summary: Int? {
        if let left, let right { return min(left, right) }
        return global ?? left ?? right
    }
}

public struct DeviceInfo: Equatable, Sendable {
    public var model: String?
    public var submodel: String?
    public var firmware: String?
    public var hardware: String?
    public var serial: String?

    public init() {}
}

/// Everything the earbuds report about gestures, as raw codes. `nil` means "not read (yet)".
///
/// The Pro 5 has five kinds of gesture, each with its own command:
/// pinch (squeeze), tap (touch), press and hold, pinch and hold, and swipe.
public struct GestureSettings: Equatable, Sendable {
    public struct PinchSlot: Hashable, Sendable {
        public var kind: PinchKind
        public var inCall: Bool
        public init(_ kind: PinchKind, inCall: Bool = false) {
            self.kind = kind
            self.inCall = inCall
        }
    }

    /// Value of the left earbud; the phone app always sets both sides alike.
    public var pinch: [PinchSlot: Int8] = [:]
    public var pinchHoldLeft: Int8?
    public var pinchHoldRight: Int8?

    public var doubleTap: Int8?
    public var doubleTapInCall: Int8?
    public var tripleTapLeft: Int8?
    public var tripleTapRight: Int8?

    public var holdLeft: Int8?
    public var holdRight: Int8?

    /// Which modes a long press cycles through. The earbuds keep one value for both sides.
    public var ancCycle: Int8?
    public var swipe: Int8?

    public init() {}
}

public enum PinchKind: UInt8, CaseIterable, Sendable {
    case once = 0
    case twice = 1
    case thrice = 2
    case hold = 3
}

public enum GestureCode {
    public static let none: Int8 = -1

    /// Pinch actions.
    public static let answerCall: Int8 = 0
    public static let rejectCall: Int8 = 1
    public static let playPause: Int8 = 2
    public static let previousTrack: Int8 = 3
    public static let nextTrack: Int8 = 4
    /// Pinch-and-hold actions.
    public static let holdAssistant: Int8 = 5
    public static let holdNoiseControl: Int8 = 6

    /// Tap actions (touch panel).
    public static let tapPlayPause: Int8 = 1
    public static let tapNext: Int8 = 2
    public static let tapPrevious: Int8 = 7
    public static let tapAnswerCall: Int8 = 0

    /// Press-and-hold actions.
    public static let pressAssistant: Int8 = 0
    public static let pressNoiseControl: Int8 = 10

    public static let swipeVolume: Int8 = 0

    /// What a noise-control gesture cycles through: 1 off/on, 2 off/on/awareness, 3 on/awareness, 4 off/awareness.
    public static let ancCycles: [Int8] = [2, 4, 3, 1]
}

public enum SpatialAudio: Int, CaseIterable, Identifiable, Sendable {
    case off = 0
    case fixed = 2
    case headTracking = 1

    public var id: Int { rawValue }
}

/// Equalizer presets by the id the earbuds use.
public enum EqualizerPreset: Int, CaseIterable, Identifiable, Sendable {
    case adaptive = 17
    case balanced = 5
    case voice = 9
    case bass = 2
    case classic = 201
    case movie = 13
    case podcast = 15
    case games = 14
    case impact = 16

    public var id: Int { rawValue }

    /// "Classic" is not a built-in id: the phone app sends it as a ten-band curve.
    static let classicBands: [UInt8] = [0xFB, 0x14, 0x1E, 0x0A, 0x00, 0x00, 0xE7, 0xF6, 0x0A, 0x00]
}

public struct ToggleState: Equatable, Sendable {
    public var adaptiveVolume: Bool?
    public var conversationAwareness: Bool?
    public var singleEarbudANC: Bool?
    public var headControl: Bool?

    public init() {}
}

public enum Side: Sendable {
    case left, right
}

public enum SoundPreference: Int, CaseIterable, Identifiable, Sendable {
    case connectivity = 0
    case quality = 1

    public var id: Int { rawValue }
}

// MARK: - Multi-connection

public enum DeviceKind: Sendable {
    case computer, phone, other
}

/// A device the earbuds know about (they can stay connected to several at once).
public struct ConnectedDevice: Identifiable, Equatable, Sendable {
    /// The Bluetooth address as the earbuds write it: six bytes, least significant first, as 12 hex digits.
    public var id: String
    public var name: String
    public var kind: DeviceKind
    public var isConnected: Bool
    /// The earbuds play audio only from this device, calls and assistant included.
    public var audioPriority: Bool
    /// The earbuds work with this device's assistant only.
    public var voicePriority: Bool
    public var isThisMac: Bool

    public var address: [UInt8] {
        stride(from: 0, to: id.count - 1, by: 2).compactMap {
            UInt8(id[id.index(id.startIndex, offsetBy: $0)..<id.index(id.startIndex, offsetBy: $0 + 2)], radix: 16)
        }
    }
}

// MARK: - Custom equalizer

/// A user-made equalizer curve stored in the earbuds.
public struct CustomEqualizer: Identifiable, Equatable, Sendable {
    public var id: Int
    public var name: String
    /// Gain per band in tenths of a dB.
    public var gains: [Int]

    public static let bandLabels = ["60", "125", "250", "500", "1k", "2k", "4k", "8k", "12k", "16k"]
    public static let gainRange = -60...60
    public static let flat = [Int](repeating: 0, count: 10)
    /// Ids start here and count up.
    public static let firstID = 100
    public static let maxNameBytes = 24
    public static let maxProfiles = 5

    public init(id: Int, name: String, gains: [Int] = CustomEqualizer.flat) {
        self.id = id
        self.name = name
        self.gains = gains
    }
}

enum CustomEqualizerAction: UInt8 {
    /// Plays the curve without storing it (used while dragging a slider).
    case preview = 0
    case save = 1
    case delete = 2
}

/// Which earbuds are in the ears and in the case right now.
public struct WearState: Equatable, Sendable {
    public var leftInEar = false
    public var rightInEar = false
    public var leftInCase = false
    public var rightInCase = false

    public init() {}

    /// Reads the earbuds' `2b25` report: p1/p2 in ear (left, right), p3/p4 in the case.
    public mutating func update(from packet: HuaweiPacket) {
        if let value = packet.byte(1) { leftInEar = value == 1 }
        if let value = packet.byte(2) { rightInEar = value == 1 }
        if let value = packet.byte(3) { leftInCase = value == 1 }
        if let value = packet.byte(4) { rightInCase = value == 1 }
    }

    public var anyInEar: Bool { leftInEar || rightInEar }
    public var bothInEar: Bool { leftInEar && rightInEar }
}
