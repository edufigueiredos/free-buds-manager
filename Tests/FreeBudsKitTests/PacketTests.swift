import XCTest
@testable import FreeBudsKit

func bytes(_ hex: String) -> [UInt8] {
    stride(from: 0, to: hex.count, by: 2).map {
        let start = hex.index(hex.startIndex, offsetBy: $0)
        return UInt8(hex[start..<hex.index(start, offsetBy: 2)], radix: 16)!
    }
}

/// Frames below were captured from a real FreeBuds Pro 5 (firmware 5.4.12); device addresses in them are made up.
final class PacketTests: XCTestCase {
    func testEncodesBatteryRequestLikeTheDeviceExpects() {
        let packet = HuaweiPacket.read(0x0108, [1, 2, 3])
        XCTAssertEqual(packet.encoded(), bytes("5a0009000108010002000300fbb9"))
    }

    func testEncodesANCReadRequest() {
        XCTAssertEqual(HuaweiPacket.read(0x2B2A, [1, 2]).encoded(), bytes("5a0007002b2a010002001d33"))
    }

    func testDecodesBatteryResponse() {
        var decoder = PacketDecoder()
        let packets = decoder.feed(bytes("5a001b000108010160020361605a030300000004020a140502000006010a0f77"))
        XCTAssertEqual(packets.count, 1)
        let battery = packets[0]
        XCTAssertEqual(battery.command, 0x0108)
        XCTAssertEqual(battery.byte(1), 0x60)
        XCTAssertEqual(battery.value(of: 2), [0x61, 0x60, 0x5a])
        XCTAssertEqual(battery.value(of: 3), [0, 0, 0])
    }

    func testDecodesANCResponse() {
        var decoder = PacketDecoder()
        let packets = decoder.feed(bytes("5a000a002b2a01020000020105b843"))
        XCTAssertEqual(packets.first?.command, 0x2B2A)
        XCTAssertEqual(packets.first?.value(of: 1), [0, 0])
    }

    func testDecodesAcknowledgementWithoutParameters() {
        var decoder = PacketDecoder()
        let packets = decoder.feed(bytes("5a00030001063ebd"))
        XCTAssertEqual(packets, [HuaweiPacket(command: 0x0106)])
    }

    func testReassemblesFramesSplitAcrossReads() {
        var decoder = PacketDecoder()
        let frame = bytes("5a000a002b2a01020000020105b843")
        XCTAssertTrue(decoder.feed(Array(frame[0..<3])).isEmpty)
        XCTAssertTrue(decoder.feed(Array(frame[3..<9])).isEmpty)
        XCTAssertEqual(decoder.feed(Array(frame[9...])).count, 1)
    }

    func testSplitsFramesGluedTogether() {
        var decoder = PacketDecoder()
        let glued = bytes("5a00030001063ebd") + bytes("5a000a002b2a01020000020105b843")
        XCTAssertEqual(decoder.feed(glued).map(\.command), [0x0106, 0x2B2A])
    }

    func testSkipsGarbageAndBadChecksums() {
        var decoder = PacketDecoder()
        var corrupted = bytes("5a00030001063ebd")
        corrupted[7] ^= 0xFF
        let stream = [0x00, 0x13] + corrupted + bytes("5a00030001063ebd")
        XCTAssertEqual(decoder.feed(stream).count, 1)
    }

    func testRoundTrip() {
        let original = HuaweiPacket.write(0x2B04, [(1, [1, 0xFF])])
        var decoder = PacketDecoder()
        XCTAssertEqual(decoder.feed(original.encoded()), [original])
    }
}

/// Frames sent by the Huawei phone app (AI Life) to a FreeBuds Pro 5, captured with the Android HCI log.
final class PhoneAppParityTests: XCTestCase {
    private func assertEncodes(_ packet: HuaweiPacket, _ hex: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(packet.encoded(), bytes(hex), file: file, line: line)
    }

    func testSpatialAudio() {
        assertEncodes(Requests.feature(FeatureID.spatialAudio, value: 2), "5a0009002bb401011802010240af")
        assertEncodes(Requests.feature(FeatureID.spatialAudio, value: 1), "5a0009002bb401011802010170cc")
    }

    func testFeatureToggles() {
        assertEncodes(Requests.feature(FeatureID.headControl, value: 1), "5a0009002bb401010b020101f0b7")
        assertEncodes(Requests.feature(FeatureID.singleEarbudANC, value: 1), "5a0009002bb4010105020101" + "52ed")
        assertEncodes(Requests.feature(FeatureID.adaptiveVolume, value: 1), "5a0009002bb4010102020101" + "03c0")
        assertEncodes(Requests.feature(FeatureID.conversationAwareness, value: 1), "5a0009002bb401011b020101eb10")
    }

    func testAdaptiveAwarenessWithSlider() {
        assertEncodes(Requests.awareness(.adaptive, adaptiveIntensity: 0), "5a000d002b0401020204030101040100a807")
    }

    func testEqualizerPresets() {
        assertEncodes(Requests.equalizer(.balanced), "5a0006002b490101056f9e")
        assertEncodes(Requests.equalizer(.impact), "5a0006002b490101102d0a")
        assertEncodes(Requests.equalizer(.classic),
                      "5a001d002b490101c902010a050101030afb141e0a0000e7f60a000403323031c367")
    }

    func testPinchGestures() {
        assertEncodes(Requests.pinch(.once, scenario: 2, left: -1, right: -1), "5a000f002b920101000201020301ff0401ff47fb")
        assertEncodes(Requests.pinch(.twice, scenario: 2, left: 4, right: 4), "5a000f002b92010101020102030104040104f798")
        assertEncodes(Requests.pinch(.twice, scenario: 1, left: 1, right: 1), "5a000f002b92010101020101030101040101c3fa")
        assertEncodes(Requests.pinch(.hold, scenario: 0, left: 5, right: nil), "5a000c002b92010103020100030105b169")
    }

    func testOtherGestureWrites() {
        assertEncodes(Requests.tripleTap(.left, code: 7), "5a00060001250101071726")
        assertEncodes(Requests.hold(.right, code: 10), "5a0006002b1602010a66f4")
        assertEncodes(Requests.ancCycle(4), "5a0006002b180101047c30")
    }
}

/// Multi-connection and custom equalizer, captured from the Huawei phone app on a FreeBuds Pro 5.
final class MultiConnectionTests: XCTestCase {
    /// A made-up Mac address, in the order the earbuds write it (least significant byte first).
    private let mac = bytes("a1b2c3d4e5f6")

    private func assertEncodes(_ packet: HuaweiPacket, _ hex: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(packet.encoded(), bytes(hex), file: file, line: line)
    }

    func testConnectAndDisconnectSteps() {
        assertEncodes(Requests.deviceAction(4, address: mac), "5a000b002b330406a1b2c3d4e5f664d6")
        assertEncodes(Requests.deviceAction(6, address: mac), "5a000b002b330606a1b2c3d4e5f6eb70")
        assertEncodes(Requests.deviceAction(1, address: mac), "5a000b002b330106a1b2c3d4e5f62c68")
        assertEncodes(Requests.deviceAction(5, address: mac), "5a000b002b330506a1b2c3d4e5f62305")
        assertEncodes(Requests.deviceAction(7, address: mac), "5a000b002b330706a1b2c3d4e5f6aca3")
        assertEncodes(Requests.deviceAction(2, address: mac), "5a000b002b330206a1b2c3d4e5f6e41d")
        XCTAssertEqual(DeviceAction.connectSteps, [4, 6, 1])
        XCTAssertEqual(DeviceAction.disconnectSteps, [5, 7, 2])
    }

    func testPriorities() {
        assertEncodes(Requests.deviceAction(DeviceAction.audioPriorityOn, address: mac), "5a000b002b330806a1b2c3d4e5f67561")
        assertEncodes(Requests.deviceAction(DeviceAction.audioPriorityOff, address: mac), "5a000b002b330906a1b2c3d4e5f632b2")
        assertEncodes(Requests.voicePriority(address: mac), "5a000b002b320106a1b2c3d4e5f6c74b")
        assertEncodes(Requests.voicePriority(address: nil), "5a000b002b320106000000000000f8cc")
    }

    func testMultiConnectToggle() {
        assertEncodes(Requests.multiConnect(false), "5a0006002b2e01010037c4")
        assertEncodes(Requests.multiConnect(true), "5a0006002b2e01010127e5")
    }

    func testCustomEqualizerWrites() {
        var profile = CustomEqualizer(id: 100, name: "My sound effect 1", gains: [40, 30, 0, 0, 0, 0, 0, 0, 0, 0])
        profile.gains = [40, 0, 30, 0, 0, 0, 0, 0, 0, 0]
        let save = Requests.customEqualizer(profile, action: .save)
        XCTAssertEqual(save.parameters, [
            Parameter(1, [0x64]), Parameter(2, [0x0a]), Parameter(5, [0x01]),
            Parameter(3, bytes("28001e00000000000000")), Parameter(4, bytes("4d7920736f756e64206566666563742031")),
        ])
        XCTAssertEqual(Requests.customEqualizer(profile, action: .preview).byte(5), 0)
        XCTAssertEqual(Requests.customEqualizer(profile, action: .delete).byte(5), 2)
    }

    func testNegativeGainsAreSignedBytes() {
        let profile = CustomEqualizer(id: 101, name: "x", gains: [-60, -10, 0, 10, 60, 0, 0, 0, 0, 0])
        XCTAssertEqual(Requests.customEqualizer(profile, action: .save).value(of: 3), [0xC4, 0xF6, 0, 10, 60, 0, 0, 0, 0, 0])
    }

    func testLongNamesAreTruncatedToTheDeviceLimit() {
        let profile = CustomEqualizer(id: 100, name: String(repeating: "a", count: 40))
        XCTAssertEqual(Requests.customEqualizer(profile, action: .save).value(of: 4)?.count, CustomEqualizer.maxNameBytes)
    }

    func testStoredProfilesAreParsedFromTheEqualizerState() {
        // Captured 2b4a, parameter 8: one stored profile (id 100, ten gains, name padded to 24 bytes).
        let record = bytes("640a28001e000000000000004d7920736f756e6420656666656374203100000000000000")
        let parsed = FreeBudsClient.parseCustomEqualizers(record)
        XCTAssertEqual(parsed, [CustomEqualizer(id: 100, name: "My sound effect 1", gains: [40, 0, 30, 0, 0, 0, 0, 0, 0, 0])])
        XCTAssertEqual(FreeBudsClient.parseCustomEqualizers(record + record).count, 2)
        XCTAssertTrue(FreeBudsClient.parseCustomEqualizers([]).isEmpty)
    }
}

final class ChargingCaseTests: XCTestCase {
    func testCaseTone() {
        XCTAssertEqual(Requests.caseTone(false).encoded(), bytes("5a0006002bb101010025b5"))
        XCTAssertEqual(Requests.caseTone(true).encoded(), bytes("5a0006002bb10101013594"))
    }

    func testCaseOpeningToneRewritesOnlyTheFlag() {
        let block = bytes("01000f000000000000000000")
        XCTAssertEqual(Requests.caseOpeningTone(true, block: block).encoded(), bytes("5a0014002bb4010110020c01010f000000000000000000db1d"))
        XCTAssertEqual(Requests.caseOpeningTone(false, block: bytes("01010f000000000000000000")).encoded(),
                       bytes("5a0014002bb4010110020c01000f0000000000000000000354"))
    }
}

final class WearStateTests: XCTestCase {
    private func state(_ hex: String) -> WearState {
        var decoder = PacketDecoder()
        var wear = WearState()
        for packet in decoder.feed(bytes(hex)) { wear.update(from: packet) }
        return wear
    }

    /// Frames the earbuds pushed while being put in and taken out (captured from the app's own log).
    func testBothInEar() {
        let wear = state("5a000f002b25010101020101030100040100e11b")
        XCTAssertTrue(wear.bothInEar)
        XCTAssertFalse(wear.leftInCase)
    }

    func testOnlyTheLeftEarbudInTheEar() {
        let wear = state("5a000f002b250101010201000301000401005 97a".replacingOccurrences(of: " ", with: ""))
        XCTAssertTrue(wear.leftInEar)
        XCTAssertFalse(wear.rightInEar)
        XCTAssertFalse(wear.bothInEar)
        XCTAssertTrue(wear.anyInEar)
    }

    func testOnlyTheRightEarbudInTheEar() {
        let wear = state("5a000f002b250101000201010301000401008e5e")
        XCTAssertFalse(wear.leftInEar)
        XCTAssertTrue(wear.rightInEar)
    }

    func testEarbudsInTheCase() {
        // Captured when both earbuds were put back in the charging case.
        let wear = state("5a000f002b2501010002010003010104010150aa")
        XCTAssertFalse(wear.anyInEar)
        XCTAssertTrue(wear.leftInCase && wear.rightInCase)
    }
}

final class PlaybackPolicyTests: XCTestCase {
    private var policy = PlaybackPolicy()
    private var clock = Date(timeIntervalSince1970: 1_000_000)

    private func step(_ count: Int, playing: Bool = true, enabled: Bool = true, after seconds: TimeInterval = 1) -> PlaybackPolicy.Action {
        clock.addTimeInterval(seconds)
        return policy.update(earCount: count, enabled: enabled, now: clock) { playing }
    }

    /// First report only records the state.
    private func start(with count: Int = 2) { XCTAssertEqual(step(count), .none) }

    func testTakingOneEarbudOutPausesAndPuttingItBackResumes() {
        start()
        XCTAssertEqual(step(1), .pause)
        XCTAssertEqual(step(2), .resume)
    }

    /// The reported bug: both out, then only one back in, must resume.
    func testOneEarbudBackAfterBothWereOutResumes() {
        start()
        XCTAssertEqual(step(0), .pause)
        XCTAssertEqual(step(1), .resume)
    }

    func testPuttingTheEarbudBackRightAwayStillResumes() {
        start()
        XCTAssertEqual(step(1), .pause)
        XCTAssertEqual(step(2, after: 0.3), .resume)
    }

    func testLeavingOneEarbudInAfterPausingDoesNotResume() {
        start()
        XCTAssertEqual(step(1), .pause)
        XCTAssertEqual(step(1), .none)
    }

    func testRemovingTheSecondEarbudWhileAlreadyPausedKeepsTheResume() {
        start()
        XCTAssertEqual(step(1), .pause)
        XCTAssertEqual(step(0, playing: false), .none)
        XCTAssertEqual(step(1), .resume)
    }

    func testMusicThatWasNotPlayingIsNeverStarted() {
        start()
        XCTAssertEqual(step(1, playing: false), .none)
        XCTAssertEqual(step(2, playing: false), .none)
    }

    func testNothingHappensWhenTheOptionIsOff() {
        XCTAssertEqual(step(2, enabled: false), .none)
        XCTAssertEqual(step(1, enabled: false), .none)
        XCTAssertEqual(step(2, enabled: false), .none)
    }

    func testTooLongAfterPausingItDoesNotResume() {
        start()
        XCTAssertEqual(step(1), .pause)
        XCTAssertEqual(step(2, after: PlaybackPolicy.resumeWindow + 1), .none)
    }

    func testResumeHappensOnlyOncePerPause() {
        start()
        XCTAssertEqual(step(1), .pause)
        XCTAssertEqual(step(2), .resume)
        policy.finishedResuming()
        XCTAssertEqual(step(1, playing: false), .none)
        XCTAssertEqual(step(2, playing: false), .none)
    }

    /// A browser still reports sound for a while after it pauses; the second earbud coming out must not press
    /// Play/Pause again, which would start the music.
    func testSecondEarbudOutDoesNotPauseAgain() {
        start()
        XCTAssertEqual(step(1), .pause)
        XCTAssertEqual(step(0, playing: true), .none)
        XCTAssertEqual(step(1), .resume)
    }

    /// The earbuds went into the case and came back: a pause made before must not be "resumed".
    func testNothingResumesAfterTheEarbudsWereAway() {
        start()
        XCTAssertEqual(step(1), .pause)
        policy.reset()
        XCTAssertEqual(step(1, playing: false), .none) // the first report only records the state
        XCTAssertEqual(step(2, playing: false), .none)
    }

    /// Measured on the earbuds: 03 = connected and idle, 09 = this Mac is streaming audio.
    func testStreamingStateBit() {
        XCTAssertTrue(FreeBudsClient.isStreaming(state: 0x09))
        XCTAssertFalse(FreeBudsClient.isStreaming(state: 0x03))
        XCTAssertFalse(FreeBudsClient.isStreaming(state: 0x01))
    }

    func testVersionComparison() {
        XCTAssertTrue(UpdateChecker.isNewer("1.0.3", than: "1.0.2"))
        XCTAssertTrue(UpdateChecker.isNewer("1.0.10", than: "1.0.9"))
        XCTAssertTrue(UpdateChecker.isNewer("1.1", than: "1.0.9"))
        XCTAssertFalse(UpdateChecker.isNewer("1.0.2", than: "1.0.2"))
        XCTAssertFalse(UpdateChecker.isNewer("1.0.2", than: "1.0.3"))
        XCTAssertEqual(UpdateChecker.stripV("v1.0.3"), "1.0.3")
    }
}
