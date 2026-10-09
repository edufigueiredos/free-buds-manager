import Foundation

/// Command ids of the Huawei control protocol (see docs/PROTOCOL.md).
enum Command {
    static let deviceInfo: UInt16 = 0x0107
    static let batteryRead: UInt16 = 0x0108
    static let batteryNotify: UInt16 = 0x0127

    static let doubleTapWrite: UInt16 = 0x011F
    static let doubleTapRead: UInt16 = 0x0120
    static let tripleTapWrite: UInt16 = 0x0125
    static let tripleTapRead: UInt16 = 0x0126

    static let ancRead: UInt16 = 0x2B2A
    static let ancWrite: UInt16 = 0x2B04
    static let stateNotify: UInt16 = 0x2B03
    /// Which earbuds are in the ears and in the case: p1/p2 in ear (left, right), p3/p4 in case. Pushed on every change.
    static let wearState: UInt16 = 0x2B25

    static let autoPauseWrite: UInt16 = 0x2B10
    static let autoPauseRead: UInt16 = 0x2B11

    static let longTapWrite: UInt16 = 0x2B16
    static let longTapRead: UInt16 = 0x2B17
    static let longTapANCWrite: UInt16 = 0x2B18
    static let longTapANCRead: UInt16 = 0x2B19

    static let swipeWrite: UInt16 = 0x2B1E
    static let swipeRead: UInt16 = 0x2B1F

    static let lowLatency: UInt16 = 0x2B6C

    static let soundQualityWrite: UInt16 = 0x2BA2
    static let soundQualityRead: UInt16 = 0x2BA3

    /// Pinch gestures (squeezing the stem).
    static let pinchWrite: UInt16 = 0x2B92
    static let pinchRead: UInt16 = 0x2B93

    /// Equalizer: write selects a preset, `eqState` reports it (and is what you read).
    static let eqWrite: UInt16 = 0x2B49
    static let eqState: UInt16 = 0x2B4A

    /// Multi-connection (several devices at once), the device list and the actions on its entries.
    static let multiConnectWrite: UInt16 = 0x2B2E
    static let multiConnectRead: UInt16 = 0x2B2F
    static let deviceList: UInt16 = 0x2B31
    static let devicePriority: UInt16 = 0x2B32
    static let deviceAction: UInt16 = 0x2B33
    static let deviceEvent: UInt16 = 0x2B36

    /// Charging-case tone: write p1 `0/1`; the answer carries p2 (on) and p3 (can be changed: both earbuds in an open case).
    static let caseTone: UInt16 = 0x2BB1

    /// Generic on/off and mode settings, addressed by a feature id in parameter 1.
    static let feature: UInt16 = 0x2BB4
}

/// Feature ids used with `Command.feature`.
enum FeatureID {
    static let adaptiveVolume: UInt8 = 0x02
    static let singleEarbudANC: UInt8 = 0x05
    static let headControl: UInt8 = 0x0B
    static let spatialAudio: UInt8 = 0x18
    static let conversationAwareness: UInt8 = 0x1B
    /// Case options: a 12-byte block whose second byte is the "case opening tone" flag.
    static let caseOptions: UInt8 = 0x10
}

/// Parameter ids of a device action (`Command.deviceAction`), each carrying the device's 6-byte address.
enum DeviceAction {
    /// Connecting takes the three steps below, in this order; disconnecting uses `disconnectSteps`.
    static let connectSteps: [UInt8] = [4, 6, 1]
    static let disconnectSteps: [UInt8] = [5, 7, 2]
    static let audioPriorityOn: UInt8 = 8
    static let audioPriorityOff: UInt8 = 9
}
