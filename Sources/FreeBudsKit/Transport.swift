import Foundation
#if canImport(IOBluetooth)
import IOBluetooth

public struct PairedDevice: Identifiable, Hashable, Sendable {
    public var address: String
    public var name: String
    public var isConnected: Bool
    public var id: String { address }
}

/// Thin wrapper over the paired-device list of macOS.
public enum BluetoothDirectory {
    private static let nameHints = ["freebuds", "freeclip", "freelace", "honor earbuds"]

    public static func looksLikeHuaweiBuds(_ name: String) -> Bool {
        let lower = name.lowercased()
        return nameHints.contains { lower.contains($0) }
    }

    public static func pairedDevices() -> [PairedDevice] {
        let devices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []
        return devices.compactMap { device in
            guard let address = device.addressString else { return nil }
            return PairedDevice(
                address: address.replacingOccurrences(of: "-", with: ":").uppercased(),
                name: device.name ?? device.nameOrAddress ?? address,
                isConnected: device.isConnected()
            )
        }
    }

    public static func device(address: String) -> IOBluetoothDevice? {
        IOBluetoothDevice(addressString: address.replacingOccurrences(of: ":", with: "-").lowercased())
    }
}

public enum TransportError: Error, LocalizedError {
    case noChannel
    case openFailed(IOReturn)
    case writeFailed(IOReturn)
    case notOpen

    public var errorDescription: String? {
        switch self {
        case .noChannel: return "No control channel found on the device."
        case .openFailed(let code): return "Could not open the control channel (0x\(String(UInt32(bitPattern: code), radix: 16)))."
        case .writeFailed(let code): return "Could not send data (0x\(String(UInt32(bitPattern: code), radix: 16)))."
        case .notOpen: return "Control channel is not open."
        }
    }
}

/// RFCOMM serial channel to the earbuds. All callbacks arrive on the main thread.
public final class RFCOMMTransport: NSObject, IOBluetoothRFCOMMChannelDelegate {
    /// The channel Huawei uses for its control protocol on the models seen so far.
    private static let defaultChannel: BluetoothRFCOMMChannelID = 1

    private let device: IOBluetoothDevice
    private var channel: IOBluetoothRFCOMMChannel?
    private var candidates: [BluetoothRFCOMMChannelID] = []
    private var openCompletion: ((Result<Void, Error>) -> Void)?
    private var lastError: IOReturn = kIOReturnSuccess
    private var isClosing = false

    public var onData: (([UInt8]) -> Void)?
    public var onClose: (() -> Void)?

    public init(device: IOBluetoothDevice) {
        self.device = device
    }

    /// `skip` rotates the order in which channels are tried: after the earbuds stayed silent on one channel,
    /// the next attempt starts with another.
    public func open(skip: Int = 0, completion: @escaping (Result<Void, Error>) -> Void) {
        openCompletion = completion
        let all = [Self.defaultChannel] + serialChannelsFromCache().filter { $0 != Self.defaultChannel }
        let shift = all.isEmpty ? 0 : skip % all.count
        candidates = Array(all.dropFirst(shift)) + Array(all.prefix(shift))
        DiagnosticLog.write("transport", "channels to try: \(candidates); services the earbuds announce: \(describeServices())")
        openNextCandidate()
    }

    private func describeServices() -> String {
        let records = device.services as? [IOBluetoothSDPServiceRecord] ?? []
        return records.map { record -> String in
            var id: BluetoothRFCOMMChannelID = 0
            let channel = record.getRFCOMMChannelID(&id) == kIOReturnSuccess ? "ch \(id)" : "-"
            return "\(record.getServiceName() ?? "?") (\(channel))"
        }.joined(separator: ", ")
    }

    public func send(_ bytes: [UInt8]) throws {
        guard let channel, channel.isOpen() else { throw TransportError.notOpen }
        var buffer = bytes
        let status = channel.writeSync(&buffer, length: UInt16(buffer.count))
        guard status == kIOReturnSuccess else { throw TransportError.writeFailed(status) }
    }

    public func close() {
        isClosing = true
        channel?.setDelegate(nil)
        _ = channel?.close()
        channel = nil
    }

    // MARK: - Opening

    /// Extra serial-port channels the SDP cache knows about, in case a model uses another one.
    private func serialChannelsFromCache() -> [BluetoothRFCOMMChannelID] {
        let records = device.services as? [IOBluetoothSDPServiceRecord] ?? []
        return records.compactMap { record in
            let name = record.getServiceName() ?? ""
            guard name.contains("Serial") || name.contains("COM") else { return nil }
            var id: BluetoothRFCOMMChannelID = 0
            return record.getRFCOMMChannelID(&id) == kIOReturnSuccess ? id : nil
        }
    }

    private func openNextCandidate() {
        guard !candidates.isEmpty else {
            finishOpen(.failure(lastError == kIOReturnSuccess ? TransportError.noChannel : TransportError.openFailed(lastError)))
            return
        }
        let id = candidates.removeFirst()
        DiagnosticLog.write("transport", "opening channel \(id)")
        var newChannel: IOBluetoothRFCOMMChannel?
        let status = device.openRFCOMMChannelAsync(&newChannel, withChannelID: id, delegate: self)
        if status == kIOReturnSuccess {
            channel = newChannel
        } else {
            lastError = status
            openNextCandidate()
        }
    }

    private func finishOpen(_ result: Result<Void, Error>) {
        let completion = openCompletion
        openCompletion = nil
        completion?(result)
    }

    // MARK: - IOBluetoothRFCOMMChannelDelegate

    public func rfcommChannelOpenComplete(_ rfcommChannel: IOBluetoothRFCOMMChannel!, status error: IOReturn) {
        guard openCompletion != nil else { return }
        if error == kIOReturnSuccess {
            finishOpen(.success(()))
        } else {
            lastError = error
            channel = nil
            openNextCandidate()
        }
    }

    public func rfcommChannelData(_ rfcommChannel: IOBluetoothRFCOMMChannel!, data dataPointer: UnsafeMutableRawPointer!, length dataLength: Int) {
        guard dataLength > 0, let dataPointer else { return }
        onData?(Array(UnsafeBufferPointer(start: dataPointer.assumingMemoryBound(to: UInt8.self), count: dataLength)))
    }

    public func rfcommChannelClosed(_ rfcommChannel: IOBluetoothRFCOMMChannel!) {
        channel = nil
        if openCompletion != nil {
            openNextCandidate()
            return
        }
        if !isClosing { onClose?() }
    }
}
#endif
