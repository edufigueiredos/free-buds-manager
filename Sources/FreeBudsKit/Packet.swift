import Foundation

/// CRC-16/XMODEM (poly 0x1021, init 0x0000, no reflection) — the checksum Huawei uses on every frame.
public enum CRC16 {
    public static func xmodem<S: Sequence>(_ bytes: S) -> UInt16 where S.Element == UInt8 {
        var crc: UInt16 = 0
        for byte in bytes {
            crc ^= UInt16(byte) << 8
            for _ in 0..<8 {
                crc = (crc & 0x8000) != 0 ? (crc << 1) ^ 0x1021 : crc << 1
            }
        }
        return crc
    }
}

/// One `type / length / value` entry inside a packet.
public struct Parameter: Equatable, Sendable {
    public var type: UInt8
    public var value: [UInt8]

    public init(_ type: UInt8, _ value: [UInt8] = []) {
        self.type = type
        self.value = value
    }
}

/// A frame of the Huawei earbuds control protocol.
///
///     5A | length (2, BE) | 00 | command (2) | parameters… | CRC16 (2, BE)
///
/// `length` counts the command and parameters plus one.
public struct HuaweiPacket: Equatable, Sendable {
    public var command: UInt16
    public var parameters: [Parameter]

    public init(command: UInt16, parameters: [Parameter] = []) {
        self.command = command
        self.parameters = parameters
    }

    /// Asks the device for the listed parameters of `command`.
    public static func read(_ command: UInt16, _ types: [UInt8]) -> HuaweiPacket {
        HuaweiPacket(command: command, parameters: types.map { Parameter($0) })
    }

    /// Writes parameters to the device. Takes `Parameter`s directly, which older Swift compilers need when a value is
    /// a variable (they read the literal in `(1, value)` as an `Int`).
    public static func write(_ command: UInt16, _ parameters: [Parameter]) -> HuaweiPacket {
        HuaweiPacket(command: command, parameters: parameters)
    }

    /// Writes values to the device.
    public static func write(_ command: UInt16, _ values: [(UInt8, [UInt8])]) -> HuaweiPacket {
        HuaweiPacket(command: command, parameters: values.map { Parameter($0.0, $0.1) })
    }

    public func value(of type: UInt8) -> [UInt8]? {
        parameters.first { $0.type == type }?.value
    }

    /// The parameter's value when it is exactly one byte long.
    public func byte(_ type: UInt8) -> UInt8? {
        guard let v = value(of: type), v.count == 1 else { return nil }
        return v[0]
    }

    public func int8(_ type: UInt8) -> Int8? {
        byte(type).map { Int8(bitPattern: $0) }
    }

    /// A parameter holding a list of signed bytes (used for "available options"); `nil` when absent or empty.
    public func int8List(_ type: UInt8) -> [Int8]? {
        guard let v = value(of: type), !v.isEmpty else { return nil }
        return v.map { Int8(bitPattern: $0) }
    }

    public func encoded() -> [UInt8] {
        var body: [UInt8] = [UInt8(command >> 8), UInt8(command & 0xFF)]
        for p in parameters {
            let value = Array(p.value.prefix(255))
            body.append(p.type)
            body.append(UInt8(value.count))
            body += value
        }
        let length = body.count + 1
        var frame: [UInt8] = [0x5A, UInt8(length >> 8), UInt8(length & 0xFF), 0x00] + body
        let crc = CRC16.xmodem(frame)
        frame += [UInt8(crc >> 8), UInt8(crc & 0xFF)]
        return frame
    }
}

/// Reassembles packets from the RFCOMM byte stream, which may split or merge frames arbitrarily.
public struct PacketDecoder {
    private var buffer: [UInt8] = []

    public init() {}

    public mutating func reset() { buffer.removeAll() }

    public mutating func feed(_ bytes: [UInt8]) -> [HuaweiPacket] {
        buffer += bytes
        var packets: [HuaweiPacket] = []

        while true {
            if let start = buffer.firstIndex(of: 0x5A) {
                if start > 0 { buffer.removeFirst(start) }
            } else {
                buffer.removeAll()
                break
            }
            guard buffer.count >= 4 else { break }

            let length = Int(buffer[1]) << 8 | Int(buffer[2])
            guard buffer[3] == 0x00, length >= 3 else {
                buffer.removeFirst()
                continue
            }
            let total = length + 5
            guard buffer.count >= total else { break }

            let frame = Array(buffer.prefix(total))
            let expected = CRC16.xmodem(frame.dropLast(2))
            let received = UInt16(frame[total - 2]) << 8 | UInt16(frame[total - 1])
            guard expected == received else {
                // Not a real frame boundary: resynchronise on the next 0x5A.
                buffer.removeFirst()
                continue
            }
            buffer.removeFirst(total)

            var packet = HuaweiPacket(command: UInt16(frame[4]) << 8 | UInt16(frame[5]))
            var position = 6
            let end = total - 2
            while position + 2 <= end {
                let type = frame[position]
                let size = Int(frame[position + 1])
                guard position + 2 + size <= end else { break }
                packet.parameters.append(Parameter(type, Array(frame[(position + 2)..<(position + 2 + size)])))
                position += 2 + size
            }
            packets.append(packet)
        }
        return packets
    }
}
