import Foundation

/// Builds the packets the phone app sends, so they can be checked byte for byte against real captures.
enum Requests {
    static func feature(_ id: UInt8, value: UInt8) -> HuaweiPacket {
        .write(Command.feature, [(1, [id]), (2, [value])])
    }

    static func featureRead(_ id: UInt8) -> HuaweiPacket {
        HuaweiPacket(command: Command.feature, parameters: [Parameter(1, [id]), Parameter(2)])
    }

    static func awareness(_ level: AwarenessLevel, adaptiveIntensity: Int? = nil) -> HuaweiPacket {
        var parameters = [Parameter(1, [UInt8(ANCMode.awareness.rawValue), UInt8(level.rawValue)])]
        if level == .adaptive {
            parameters += [Parameter(3, [1]), Parameter(4, [UInt8(max(0, min(10, adaptiveIntensity ?? 5)))])]
        }
        return HuaweiPacket(command: Command.ancWrite, parameters: parameters)
    }

    static func equalizer(_ preset: EqualizerPreset) -> HuaweiPacket {
        guard preset == .classic else {
            return .write(Command.eqWrite, [(1, [UInt8(preset.rawValue)])])
        }
        // "Classic" is not a built-in id: the phone app sends it as a ten-band curve named "201".
        return HuaweiPacket(command: Command.eqWrite, parameters: [
            Parameter(1, [UInt8(preset.rawValue)]),
            Parameter(2, [UInt8(EqualizerPreset.classicBands.count)]),
            Parameter(5, [1]),
            Parameter(3, EqualizerPreset.classicBands),
            Parameter(4, Array(String(preset.rawValue).utf8)),
        ])
    }

    /// `scenario`: `1` during a call, `2` otherwise, `0` for pinch and hold.
    static func pinch(_ kind: PinchKind, scenario: UInt8, left: Int8?, right: Int8?) -> HuaweiPacket {
        var parameters = [Parameter(1, [kind.rawValue]), Parameter(2, [scenario])]
        if let left { parameters.append(Parameter(3, [UInt8(bitPattern: left)])) }
        if let right { parameters.append(Parameter(4, [UInt8(bitPattern: right)])) }
        return HuaweiPacket(command: Command.pinchWrite, parameters: parameters)
    }

    static func tripleTap(_ side: Side, code: Int8) -> HuaweiPacket {
        .write(Command.tripleTapWrite, [(side == .left ? 1 : 2, [UInt8(bitPattern: code)])])
    }

    static func hold(_ side: Side, code: Int8) -> HuaweiPacket {
        .write(Command.longTapWrite, [(side == .left ? 1 : 2, [UInt8(bitPattern: code)])])
    }

    static func ancCycle(_ code: Int8) -> HuaweiPacket {
        .write(Command.longTapANCWrite, [(1, [UInt8(bitPattern: code)])])
    }

    // MARK: Multi-connection

    static func deviceAction(_ step: UInt8, address: [UInt8]) -> HuaweiPacket {
        .write(Command.deviceAction, [(step, address)])
    }

    /// Picks the device whose assistant the earbuds work with; `nil` clears it.
    static func voicePriority(address: [UInt8]?) -> HuaweiPacket {
        .write(Command.devicePriority, [(1, address ?? [UInt8](repeating: 0, count: 6))])
    }

    static func multiConnect(_ enabled: Bool) -> HuaweiPacket {
        .write(Command.multiConnectWrite, [(1, [enabled ? 1 : 0])])
    }

    // MARK: Equalizer

    static func equalizerID(_ id: Int) -> HuaweiPacket {
        .write(Command.eqWrite, [(1, [UInt8(id)])])
    }

    static func customEqualizer(_ profile: CustomEqualizer, action: CustomEqualizerAction) -> HuaweiPacket {
        let gains = profile.gains.map { UInt8(bitPattern: Int8(clamping: $0)) }
        var name = Array(profile.name.utf8)
        while name.count > CustomEqualizer.maxNameBytes { name.removeLast() }
        return HuaweiPacket(command: Command.eqWrite, parameters: [
            Parameter(1, [UInt8(profile.id)]),
            Parameter(2, [UInt8(gains.count)]),
            Parameter(5, [action.rawValue]),
            Parameter(3, gains),
            Parameter(4, name),
        ])
    }

    // MARK: Charging case

    static func caseTone(_ enabled: Bool) -> HuaweiPacket {
        .write(Command.caseTone, [(1, [enabled ? 1 : 0])])
    }

    /// The case options block is written back whole, with only the opening-tone flag changed.
    static func caseOpeningTone(_ enabled: Bool, block: [UInt8]) -> HuaweiPacket {
        var copy = block
        if copy.count > 1 { copy[1] = enabled ? 1 : 0 }
        return .write(Command.feature, [(1, [FeatureID.caseOptions]), (2, copy)])
    }
}
