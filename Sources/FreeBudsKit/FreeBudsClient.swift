import Foundation
#if canImport(IOBluetooth)
import IOBluetooth
import os

let log = Logger(subsystem: "io.github.edufigueiredos.FreeBudsManager", category: "client")

private func hex(_ bytes: [UInt8]) -> String { bytes.map { String(format: "%02x", $0) }.joined() }

public enum ClientError: Error, LocalizedError {
    case notConnected
    case timeout
    case busy

    public var errorDescription: String? {
        switch self {
        case .notConnected: return "The earbuds are not connected."
        case .timeout: return "The earbuds did not answer."
        case .busy: return "The earbuds are busy."
        }
    }
}

/// Talks to one pair of Huawei earbuds and publishes what they report.
@MainActor
public final class FreeBudsClient: ObservableObject {
    public enum Status: Equatable, Sendable {
        case noDevice
        case disconnected
        case connecting
        /// Connected over Bluetooth, but the earbuds do not answer the app.
        case noAnswer
        case connected
    }

    @Published public private(set) var status: Status = .noDevice {
        didSet { if status != oldValue { log.info("status -> \(String(describing: self.status), privacy: .public)") } }
    }
    @Published public private(set) var deviceName = ""
    @Published public private(set) var candidates: [PairedDevice] = []
    @Published public private(set) var battery = BatteryState()
    @Published public private(set) var anc = ANCState()
    @Published public private(set) var info = DeviceInfo()
    @Published public private(set) var gestures = GestureSettings()
    @Published public private(set) var inEar: Bool?
    @Published public private(set) var autoPause: Bool?
    @Published public private(set) var lowLatency: Bool?
    @Published public private(set) var soundPreference: SoundPreference?
    @Published public private(set) var spatialAudio: SpatialAudio?
    @Published public private(set) var equalizer: Int?
    @Published public private(set) var toggles = ToggleState()
    @Published public private(set) var devices: [ConnectedDevice] = []
    @Published public private(set) var multiConnect: Bool?
    @Published public private(set) var customEqualizers: [CustomEqualizer] = []
    @Published public private(set) var wear = WearState()
    /// The Accessibility permission, needed to pause and resume this Mac's music.
    @Published public private(set) var canControlMacPlayback = MacPlayback.isTrusted
    @Published public private(set) var caseTone: Bool?
    /// The case tones can only be changed with both earbuds in an open case.
    @Published public private(set) var caseToneChangeable = false
    @Published public private(set) var caseOpeningTone: Bool?
    private var caseOptionsBlock: [UInt8] = []
    @Published public private(set) var lastError: String?

    private static let savedAddressKey = "selectedDeviceAddress"

    private var transport: RFCOMMTransport?
    private var decoder = PacketDecoder()
    private var timer: Timer?
    private var wearTimer: Timer?
    private var lastReceived = Date()
    private var receivedSinceOpen = false
    private var silentAttempts = 0
    private var isOpening = false
    private var nextAttempt = Date.distantPast
    private var pending: [UInt16: (token: Int, continuation: CheckedContinuation<HuaweiPacket, Error>)] = [:]
    private var tokenCounter = 0
    private var deviceRefreshTask: Task<Void, Never>?
    private var playbackPolicy = PlaybackPolicy()
    private var pausedMedia = MacPlayback.PausedMedia()
    private var pauseTask: Task<Void, Never>?
    private var wearSeen = false
    private var resumeTask: Task<Void, Never>?
    private var askedForAccessibility = false
    private var lastEqualizerPreview = Date.distantPast

    public init() {}

    public var selectedAddress: String? {
        get { UserDefaults.standard.string(forKey: Self.savedAddressKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.savedAddressKey) }
    }

    // MARK: - Lifecycle

    public func start() {
        guard timer == nil else { return }
        tick()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        // The earbuds push "worn / taken out" reports only now and then, so ask for them as well.
        wearTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pollWear() }
        }
    }

    public func selectDevice(address: String) {
        selectedAddress = address
        tearDown()
        nextAttempt = .distantPast
        tick()
    }

    /// Asks macOS to connect the earbuds (they must be in range and not busy with another device).
    public func connectToMac() {
        guard let address = resolveAddress(), let device = BluetoothDirectory.device(address: address) else { return }
        DispatchQueue.global(qos: .userInitiated).async { _ = device.openConnection() }
    }

    private func resolveAddress() -> String? {
        let all = BluetoothDirectory.pairedDevices()
        candidates = all.filter { BluetoothDirectory.looksLikeHuaweiBuds($0.name) }
        if let saved = selectedAddress, all.contains(where: { $0.address == saved }) { return saved }
        return candidates.first?.address
    }

    private func tick() {
        if canControlMacPlayback != MacPlayback.isTrusted { canControlMacPlayback = MacPlayback.isTrusted }
        guard let address = resolveAddress(),
              let device = BluetoothDirectory.device(address: address) else {
            tearDown()
            status = .noDevice
            return
        }
        deviceName = candidates.first { $0.address == address }?.name ?? device.nameOrAddress ?? ""

        guard device.isConnected() else {
            if transport != nil { tearDown() }
            status = .disconnected
            return
        }
        if transport != nil, status == .connected { checkChannelIsAlive() }
        guard transport == nil, !isOpening, Date() >= nextAttempt else { return }
        openChannel(to: device)
    }

    private func openChannel(to device: IOBluetoothDevice) {
        isOpening = true
        if status != .noAnswer { status = .connecting }
        let transport = RFCOMMTransport(device: device)
        transport.onData = { [weak self] bytes in
            MainActor.assumeIsolated { self?.receive(bytes) }
        }
        transport.onClose = { [weak self] in
            MainActor.assumeIsolated { self?.channelClosed() }
        }
        self.transport = transport
        transport.open { [weak self] result in
            MainActor.assumeIsolated {
                guard let self, self.transport === transport else { return }
                self.isOpening = false
                switch result {
                case .success:
                    self.lastError = nil
                    self.lastReceived = Date()
                    self.receivedSinceOpen = false
                    if self.silentAttempts == 0 { self.status = .connected }
                    Task { await self.readEverything() }
                case .failure(let error):
                    log.error("open failed: \(error.localizedDescription, privacy: .public)")
                    self.lastError = error.localizedDescription
                    self.nextAttempt = Date().addingTimeInterval(8)
                    self.tearDown()
                    self.status = .disconnected
                }
            }
        }
    }

    /// The earbuds can leave the channel open and not answer: they seem to talk to one control session at a
    /// time, and until something resets them (closing the case does) they ignore the next one. Resetting the
    /// Bluetooth link from here does not help and cuts the music, so the app only says what is happening and
    /// keeps trying, gently.
    private func checkChannelIsAlive() {
        if autoPause != true { try? send(.read(Command.wearState, [1, 2, 3, 4])) }
        guard Date().timeIntervalSince(lastReceived) > 8 else { return }

        tearDown()
        if receivedSinceOpen {
            // It worked and then stopped: a new channel is usually enough.
            log.error("the earbuds stopped answering; reopening the control channel")
            status = .disconnected
            nextAttempt = Date().addingTimeInterval(2)
        } else {
            silentAttempts += 1
            log.error("the earbuds do not answer the control channel (attempt \(self.silentAttempts, privacy: .public))")
            status = .noAnswer
            nextAttempt = Date().addingTimeInterval(silentAttempts < 3 ? 6 : 20)
        }
    }

    /// Lets the user try again right now.
    public func retryNow() {
        nextAttempt = .distantPast
        tick()
    }

    /// Closes the control channel cleanly. Called when the app quits, so the earbuds do not keep a dead session.
    public func shutdown() {
        timer?.invalidate()
        wearTimer?.invalidate()
        timer = nil
        wearTimer = nil
        transport?.onData = nil
        transport?.onClose = nil
        transport?.close()
        transport = nil
        // The channel closes asynchronously; give it a moment before the process goes away.
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
    }

    /// Asks for the worn state while "Pause when removed" is on, which is when anything depends on it.
    private func pollWear() {
        guard status == .connected, autoPause == true, transport != nil else { return }
        try? send(.read(Command.wearState, [1, 2, 3, 4]))
    }

    private func channelClosed() {
        tearDown()
        status = .disconnected
        nextAttempt = Date().addingTimeInterval(2)
    }

    private func tearDown() {
        transport?.onData = nil
        transport?.onClose = nil
        transport?.close()
        transport = nil
        isOpening = false
        decoder.reset()
        for (_, entry) in pending { entry.continuation.resume(throwing: ClientError.notConnected) }
        pending.removeAll()
        if status == .connected || status == .connecting {
            battery = BatteryState()
            anc = ANCState()
            inEar = nil
            devices = []
        }
    }

    // MARK: - Requests

    private func receive(_ bytes: [UInt8]) {
        lastReceived = Date()
        receivedSinceOpen = true
        silentAttempts = 0
        if status == .noAnswer { status = .connected }
        for packet in decoder.feed(bytes) {
            if packet.command != Command.wearState { log.info("RX \(hex(packet.encoded()), privacy: .public)") }
            apply(packet)
            if let entry = pending.removeValue(forKey: packet.command) {
                entry.continuation.resume(returning: packet)
            }
        }
    }

    /// Sends a packet and waits for the device to answer with the same command id.
    @discardableResult
    private func request(_ packet: HuaweiPacket, timeout: TimeInterval = 2) async throws -> HuaweiPacket {
        var waited = 0
        while pending[packet.command] != nil {
            try await Task.sleep(for: .milliseconds(40))
            waited += 1
            if waited > 150 { throw ClientError.busy }
        }
        guard let transport else { throw ClientError.notConnected }

        log.info("TX \(hex(packet.encoded()), privacy: .public)")
        tokenCounter += 1
        let token = tokenCounter
        let command = packet.command
        return try await withCheckedThrowingContinuation { continuation in
            pending[command] = (token, continuation)
            do {
                try transport.send(packet.encoded())
            } catch {
                pending[command] = nil
                continuation.resume(throwing: error)
                return
            }
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(timeout))
                guard let self, let entry = self.pending[command], entry.token == token else { return }
                self.pending[command] = nil
                entry.continuation.resume(throwing: ClientError.timeout)
            }
        }
    }

    private func send(_ packet: HuaweiPacket) throws {
        guard let transport else { throw ClientError.notConnected }
        if packet.command != Command.wearState { log.info("TX \(hex(packet.encoded()), privacy: .public)") }
        try transport.send(packet.encoded())
    }

    /// Reads one feature, retrying once; unsupported features simply stay `nil`.
    private func read(_ packet: HuaweiPacket) async {
        for _ in 0..<2 {
            if (try? await request(packet)) != nil { return }
            if transport == nil { return }
        }
    }

    private func readEverything() async {
        await read(.read(Command.batteryRead, [1, 2, 3]))
        await read(.read(Command.ancRead, [1, 2]))
        await read(.read(Command.deviceInfo, Array(0..<32)))
        await read(.read(Command.autoPauseRead, [1]))
        await read(.read(Command.wearState, [1, 2, 3, 4]))
        await read(.read(Command.lowLatency, [2]))
        await read(.read(Command.soundQualityRead, [1]))
        await read(.read(Command.eqState, [2]))
        await read(.read(Command.multiConnectRead, [1]))
        await read(.read(Command.caseTone, [2, 3]))
        await read(featureRead(FeatureID.caseOptions))
        await read(.read(Command.deviceList, [1]))
        for id in [FeatureID.spatialAudio, FeatureID.headControl, FeatureID.singleEarbudANC,
                   FeatureID.adaptiveVolume, FeatureID.conversationAwareness] {
            await read(featureRead(id))
        }
        for slot in Self.pinchSlots { await read(pinchRead(slot)) }
        await read(pinchRead(.init(.hold)))
        await read(.read(Command.doubleTapRead, [1, 2, 4]))
        await read(.read(Command.tripleTapRead, [1, 2]))
        await read(.read(Command.longTapRead, [1, 2]))
        await read(.read(Command.longTapANCRead, [1, 2]))
        await read(.read(Command.swipeRead, [1, 2]))
    }

    private static let pinchSlots: [GestureSettings.PinchSlot] = [
        .init(.once), .init(.twice), .init(.thrice),
        .init(.once, inCall: true), .init(.twice, inCall: true),
    ]

    /// Pinch gestures are addressed by kind and scenario: `1` in a call, `2` otherwise, `0` for pinch-and-hold.
    private func pinchScenario(_ slot: GestureSettings.PinchSlot) -> UInt8 {
        slot.kind == .hold ? 0 : (slot.inCall ? 1 : 2)
    }

    private func pinchRead(_ slot: GestureSettings.PinchSlot) -> HuaweiPacket {
        HuaweiPacket(command: Command.pinchRead,
                     parameters: [Parameter(1, [slot.kind.rawValue]), Parameter(2, [pinchScenario(slot)])])
    }

    private func featureRead(_ id: UInt8) -> HuaweiPacket { Requests.featureRead(id) }

    /// Runs a write, then reads the value back so the UI always shows what the device really holds.
    private func change(_ write: HuaweiPacket, awaitAck: Bool, thenRead readBack: HuaweiPacket) {
        Task {
            do {
                if awaitAck {
                    // Some firmwares do not acknowledge every write; the read-back is the truth.
                    _ = try? await request(write, timeout: 1.5)
                } else {
                    try send(write)
                    try await Task.sleep(for: .milliseconds(250))
                }
                try await request(readBack)
                lastError = nil
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    // MARK: - Public actions

    public func refresh() {
        Task { await readEverything() }
    }

    public func setANCMode(_ mode: ANCMode) {
        anc.mode = mode
        let value: [UInt8] = [UInt8(mode.rawValue), mode == .off ? 0x00 : 0xFF]
        change(.write(Command.ancWrite, [Parameter(1, value)]), awaitAck: false, thenRead: .read(Command.ancRead, [1, 2]))
    }

    public func setCancellationLevel(_ level: CancellationLevel) {
        anc.cancellationLevel = level
        let value: [UInt8] = [UInt8(ANCMode.cancellation.rawValue), UInt8(level.rawValue)]
        change(.write(Command.ancWrite, [Parameter(1, value)]), awaitAck: false, thenRead: .read(Command.ancRead, [1, 2]))
    }

    public func setAwarenessLevel(_ level: AwarenessLevel) {
        anc.awarenessLevel = level
        if level == .adaptive { anc.adaptiveIntensity = anc.adaptiveIntensity ?? 5 }
        change(Requests.awareness(level, adaptiveIntensity: anc.adaptiveIntensity), awaitAck: false,
               thenRead: .read(Command.ancRead, [1, 2]))
    }

    /// `0` lets in more outside noise, `10` less (adaptive awareness only).
    public func setAdaptiveIntensity(_ value: Int) {
        let clamped = max(0, min(10, value))
        anc.adaptiveIntensity = clamped
        change(Requests.awareness(.adaptive, adaptiveIntensity: clamped), awaitAck: false,
               thenRead: .read(Command.ancRead, [1, 2]))
    }

    public func setSpatialAudio(_ mode: SpatialAudio) {
        spatialAudio = mode
        setFeature(FeatureID.spatialAudio, value: UInt8(mode.rawValue))
    }

    public func setAdaptiveVolume(_ enabled: Bool) {
        toggles.adaptiveVolume = enabled
        setFeature(FeatureID.adaptiveVolume, value: enabled ? 1 : 0)
    }

    public func setConversationAwareness(_ enabled: Bool) {
        toggles.conversationAwareness = enabled
        setFeature(FeatureID.conversationAwareness, value: enabled ? 1 : 0)
    }

    public func setSingleEarbudANC(_ enabled: Bool) {
        toggles.singleEarbudANC = enabled
        setFeature(FeatureID.singleEarbudANC, value: enabled ? 1 : 0)
    }

    public func setHeadControl(_ enabled: Bool) {
        toggles.headControl = enabled
        setFeature(FeatureID.headControl, value: enabled ? 1 : 0)
    }

    private func setFeature(_ id: UInt8, value: UInt8) {
        change(Requests.feature(id, value: value), awaitAck: true, thenRead: featureRead(id))
    }

    public func setEqualizer(_ preset: EqualizerPreset) {
        equalizer = preset.rawValue
        change(Requests.equalizer(preset), awaitAck: false, thenRead: .read(Command.eqState, [2]))
    }

    public func setAutoPause(_ enabled: Bool) {
        autoPause = enabled
        if enabled { askForPlaybackControlIfNeeded() }
        change(.write(Command.autoPauseWrite, [(1, [enabled ? 1 : 0])]), awaitAck: true,
               thenRead: .read(Command.autoPauseRead, [1]))
    }

    public func setLowLatency(_ enabled: Bool) {
        lowLatency = enabled
        change(.write(Command.lowLatency, [(1, [enabled ? 1 : 0])]), awaitAck: true,
               thenRead: .read(Command.lowLatency, [2]))
    }

    public func setSoundPreference(_ preference: SoundPreference) {
        soundPreference = preference
        change(.write(Command.soundQualityWrite, [(1, [UInt8(preference.rawValue)])]), awaitAck: true,
               thenRead: .read(Command.soundQualityRead, [1]))
    }

    /// Sets a pinch gesture on both earbuds, like the phone app does.
    public func setPinch(_ slot: GestureSettings.PinchSlot, code: Int8) {
        gestures.pinch[slot] = code
        change(Requests.pinch(slot.kind, scenario: pinchScenario(slot), left: code, right: code),
               awaitAck: true, thenRead: pinchRead(slot))
    }

    public func setPinchHold(_ side: Side, code: Int8) {
        if side == .left { gestures.pinchHoldLeft = code } else { gestures.pinchHoldRight = code }
        change(Requests.pinch(.hold, scenario: 0, left: side == .left ? code : nil, right: side == .right ? code : nil),
               awaitAck: true, thenRead: pinchRead(.init(.hold)))
    }

    public func setDoubleTap(code: Int8) {
        gestures.doubleTap = code
        let value = [UInt8(bitPattern: code)]
        change(.write(Command.doubleTapWrite, [Parameter(1, value), Parameter(2, value)]), awaitAck: true,
               thenRead: .read(Command.doubleTapRead, [1, 2, 4]))
    }

    public func setDoubleTapInCall(code: Int8) {
        gestures.doubleTapInCall = code
        change(.write(Command.doubleTapWrite, [(4, [UInt8(bitPattern: code)])]), awaitAck: true,
               thenRead: .read(Command.doubleTapRead, [1, 2, 4]))
    }

    public func setTripleTap(_ side: Side, code: Int8) {
        if side == .left { gestures.tripleTapLeft = code } else { gestures.tripleTapRight = code }
        change(Requests.tripleTap(side, code: code), awaitAck: true, thenRead: .read(Command.tripleTapRead, [1, 2]))
    }

    public func setHold(_ side: Side, code: Int8) {
        if side == .left { gestures.holdLeft = code } else { gestures.holdRight = code }
        change(Requests.hold(side, code: code), awaitAck: true, thenRead: .read(Command.longTapRead, [1, 2]))
    }

    /// The earbuds store a single cycle for both sides (writing one side changes the other), so send it once.
    public func setANCCycle(code: Int8) {
        gestures.ancCycle = code
        let value = [UInt8(bitPattern: code)]
        change(.write(Command.longTapANCWrite, [Parameter(1, value), Parameter(2, value)]),
               awaitAck: true, thenRead: .read(Command.longTapANCRead, [1, 2]))
    }

    public func setSwipe(code: Int8) {
        gestures.swipe = code
        let value = [UInt8(bitPattern: code)]
        change(.write(Command.swipeWrite, [Parameter(1, value), Parameter(2, value)]), awaitAck: true,
               thenRead: .read(Command.swipeRead, [1, 2]))
    }

    // MARK: - Charging case

    public func setCaseTone(_ enabled: Bool) {
        caseTone = enabled
        change(Requests.caseTone(enabled), awaitAck: true, thenRead: .read(Command.caseTone, [2, 3]))
    }

    public func setCaseOpeningTone(_ enabled: Bool) {
        guard !caseOptionsBlock.isEmpty else { return }
        caseOpeningTone = enabled
        change(Requests.caseOpeningTone(enabled, block: caseOptionsBlock), awaitAck: true,
               thenRead: featureRead(FeatureID.caseOptions))
    }

    // MARK: - Devices

    public func refreshDevices() {
        Task { _ = try? await request(.read(Command.deviceList, [1])) }
    }

    public func connect(_ device: ConnectedDevice) {
        runDeviceSteps(DeviceAction.connectSteps, on: device)
    }

    /// Disconnecting this Mac also ends this app's own link to the earbuds; the panel then offers "Connect".
    public func disconnect(_ device: ConnectedDevice) {
        runDeviceSteps(DeviceAction.disconnectSteps, on: device)
    }

    private func runDeviceSteps(_ steps: [UInt8], on device: ConnectedDevice) {
        Task {
            for step in steps {
                try? send(Requests.deviceAction(step, address: device.address))
                try? await Task.sleep(for: .milliseconds(60))
            }
            try? await Task.sleep(for: .milliseconds(1200))
            refreshDevices()
        }
    }

    /// The earbuds play audio only from this device. Turning it on clears the voice priority, as the phone app does.
    public func setAudioPriority(_ device: ConnectedDevice, enabled: Bool) {
        updateDevices { devices in
            for index in devices.indices {
                devices[index].audioPriority = enabled && devices[index].id == device.id
                if enabled { devices[index].voicePriority = false }
            }
        }
        Task {
            try? send(Requests.deviceAction(enabled ? DeviceAction.audioPriorityOn : DeviceAction.audioPriorityOff,
                                            address: device.address))
            try? send(Requests.voicePriority(address: nil))
            try? await Task.sleep(for: .milliseconds(500))
            refreshDevices()
        }
    }

    public func setVoicePriority(_ device: ConnectedDevice, enabled: Bool) {
        updateDevices { devices in
            for index in devices.indices { devices[index].voicePriority = enabled && devices[index].id == device.id }
        }
        Task {
            try? send(Requests.voicePriority(address: enabled ? device.address : nil))
            try? await Task.sleep(for: .milliseconds(500))
            refreshDevices()
        }
    }

    /// Turning it off disconnects every device but one, which may be this Mac.
    public func setMultiConnect(_ enabled: Bool) {
        multiConnect = enabled
        change(Requests.multiConnect(enabled), awaitAck: true, thenRead: .read(Command.multiConnectRead, [1]))
    }

    private func updateDevices(_ change: (inout [ConnectedDevice]) -> Void) {
        var copy = devices
        change(&copy)
        devices = copy
    }

    // MARK: - Custom equalizer

    public func selectEqualizer(id: Int) {
        equalizer = id
        change(Requests.equalizerID(id), awaitAck: false, thenRead: .read(Command.eqState, [2]))
    }

    /// The next free profile id, or `nil` when the earbuds cannot hold more.
    public var nextCustomEqualizerID: Int? {
        guard customEqualizers.count < CustomEqualizer.maxProfiles else { return nil }
        return (customEqualizers.map(\.id).max() ?? (CustomEqualizer.firstID - 1)) + 1
    }

    /// Plays a curve without saving it, so it can be heard while a slider moves. Rate-limited.
    public func previewCustomEqualizer(_ profile: CustomEqualizer) {
        guard Date().timeIntervalSince(lastEqualizerPreview) > 0.12 else { return }
        lastEqualizerPreview = Date()
        try? send(Requests.customEqualizer(profile, action: .preview))
    }

    public func saveCustomEqualizer(_ profile: CustomEqualizer) {
        var copy = customEqualizers
        if let index = copy.firstIndex(where: { $0.id == profile.id }) { copy[index] = profile } else { copy.append(profile) }
        customEqualizers = copy
        equalizer = profile.id
        change(Requests.customEqualizer(profile, action: .save), awaitAck: false, thenRead: .read(Command.eqState, [2]))
    }

    public func deleteCustomEqualizer(_ profile: CustomEqualizer) {
        customEqualizers.removeAll { $0.id == profile.id }
        if equalizer == profile.id { equalizer = EqualizerPreset.adaptive.rawValue }
        change(Requests.customEqualizer(profile, action: .delete), awaitAck: false, thenRead: .read(Command.eqState, [2]))
    }

    // MARK: - Incoming data

    private func apply(_ packet: HuaweiPacket) {
        switch packet.command {
        case Command.batteryRead, Command.batteryNotify:
            applyBattery(packet)
        case Command.ancRead:
            applyANC(packet)
        case Command.deviceInfo:
            applyInfo(packet)
        case Command.stateNotify:
            if let value = packet.byte(8) ?? packet.byte(9) { inEar = value == 1 }
        case Command.wearState:
            applyWear(packet)
        case Command.autoPauseRead:
            if let value = packet.byte(1) { autoPause = value == 1 }
        case Command.lowLatency:
            if let value = packet.byte(2) { lowLatency = value == 1 }
        case Command.soundQualityRead:
            if let value = packet.byte(2) { soundPreference = SoundPreference(rawValue: Int(value)) }
        case Command.doubleTapRead:
            if let value = packet.int8(1) { gestures.doubleTap = value }
            if let value = packet.int8(4) { gestures.doubleTapInCall = value }
        case Command.tripleTapRead:
            if let value = packet.int8(1) { gestures.tripleTapLeft = value }
            if let value = packet.int8(2) { gestures.tripleTapRight = value }
        case Command.longTapRead:
            if let value = packet.int8(1) { gestures.holdLeft = value }
            if let value = packet.int8(2) { gestures.holdRight = value }
        case Command.longTapANCRead:
            if let value = packet.int8(1) ?? packet.int8(2) { gestures.ancCycle = value }
        case Command.swipeRead:
            if let value = packet.int8(1) { gestures.swipe = value }
        case Command.pinchRead:
            applyPinch(packet)
        case Command.eqState:
            if let value = packet.byte(2) { equalizer = Int(value) }
            if let stored = packet.value(of: 8) { customEqualizers = Self.parseCustomEqualizers(stored) }
        case Command.caseTone:
            if let value = packet.byte(2) { caseTone = value == 1 }
            if let value = packet.byte(3) { caseToneChangeable = value == 1 }
        case Command.multiConnectRead:
            if let value = packet.byte(1) { multiConnect = value == 1 }
        case Command.deviceList:
            applyDevice(packet)
        case Command.deviceEvent:
            applyDeviceEvent(packet)
        case Command.feature:
            applyFeature(packet)
        default:
            break
        }
    }

    /// One record per profile: id, band count, ten gains, then the name padded to 24 bytes.
    nonisolated static func parseCustomEqualizers(_ data: [UInt8]) -> [CustomEqualizer] {
        let recordSize = 2 + 10 + CustomEqualizer.maxNameBytes
        return stride(from: 0, to: data.count - recordSize + 1, by: recordSize).map { start in
            let record = Array(data[start..<(start + recordSize)])
            let gains = record[2..<12].map { Int(Int8(bitPattern: $0)) }
            let name = record[12...].prefix { $0 != 0 }
            return CustomEqualizer(id: Int(record[0]), name: String(decoding: name, as: UTF8.self), gains: gains)
        }
    }

    private static func addressID(_ bytes: [UInt8]) -> String { bytes.map { String(format: "%02x", $0) }.joined() }

    /// This Mac's own address as the earbuds write it (reversed), to tell which entry is this computer.
    private static let thisMacID: String? = {
        guard let text = IOBluetoothHostController.default()?.addressAsString() else { return nil }
        let bytes = text.split(whereSeparator: { $0 == "-" || $0 == ":" }).compactMap { UInt8($0, radix: 16) }
        return bytes.count == 6 ? addressID(bytes.reversed()) : nil
    }()

    private func applyDevice(_ packet: HuaweiPacket) {
        guard let address = packet.value(of: 4), address.count == 6 else { return }
        let id = Self.addressID(address)
        var device = devices.first { $0.id == id }
            ?? ConnectedDevice(id: id, name: "", kind: .other, isConnected: false, audioPriority: false,
                               voicePriority: false, isThisMac: id == Self.thisMacID)
        if let name = packet.value(of: 9), !name.isEmpty { device.name = String(decoding: name, as: UTF8.self) }
        if let state = packet.byte(5) { device.isConnected = state != 0 }
        if let kind = packet.byte(6) { device.kind = kind == 4 ? .computer : (kind == 1 ? .phone : .other) }
        if let voice = packet.byte(7) { device.voicePriority = voice == 1 }
        if let audio = packet.byte(13) { device.audioPriority = audio == 1 }
        var copy = devices
        if let index = copy.firstIndex(where: { $0.id == id }) { copy[index] = device } else { copy.append(device) }
        devices = copy
    }

    /// The earbuds announce connection and priority changes; re-read the list shortly after to stay exact.
    private func applyDeviceEvent(_ packet: HuaweiPacket) {
        if let value = packet.value(of: 5), value.count == 7 {
            let id = Self.addressID(Array(value.prefix(6)))
            updateDevices { list in
                if let index = list.firstIndex(where: { $0.id == id }) { list[index].isConnected = value[6] != 0 }
            }
        }
        if let value = packet.value(of: 7), value.count == 6 {
            let id = Self.addressID(value)
            updateDevices { list in for index in list.indices { list[index].voicePriority = list[index].id == id } }
        }
        if let value = packet.value(of: 9), value.count == 7 {
            let id = Self.addressID(Array(value.prefix(6)))
            updateDevices { list in
                if let index = list.firstIndex(where: { $0.id == id }) { list[index].audioPriority = value[6] == 1 }
            }
        }
        deviceRefreshTask?.cancel()
        deviceRefreshTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled, let self else { return }
            self.refreshDevices()
        }
    }

    private func applyPinch(_ packet: HuaweiPacket) {
        guard let rawKind = packet.byte(1), let kind = PinchKind(rawValue: rawKind),
              let scenario = packet.byte(2) else { return }
        if kind == .hold {
            if let value = packet.int8(3) { gestures.pinchHoldLeft = value }
            if let value = packet.int8(4) { gestures.pinchHoldRight = value }
        } else if let value = packet.int8(3) {
            gestures.pinch[.init(kind, inCall: scenario == 1)] = value
        }
    }

    private func applyFeature(_ packet: HuaweiPacket) {
        if packet.byte(1) == FeatureID.caseOptions, let block = packet.value(of: 2), block.count > 1 {
            caseOptionsBlock = block
            caseOpeningTone = block[1] == 1
            return
        }
        guard let id = packet.byte(1), let value = packet.byte(2) else { return }
        switch id {
        case FeatureID.spatialAudio: spatialAudio = SpatialAudio(rawValue: Int(value))
        case FeatureID.adaptiveVolume: toggles.adaptiveVolume = value == 1
        case FeatureID.conversationAwareness: toggles.conversationAwareness = value == 1
        case FeatureID.singleEarbudANC: toggles.singleEarbudANC = value == 1
        case FeatureID.headControl: toggles.headControl = value == 1
        default: break
        }
    }

    /// Called when the earbuds report which of them are in the ears.
    private func applyWear(_ packet: HuaweiPacket) {
        var state = wear
        state.update(from: packet)
        guard state != wear || !wearSeen else { return }
        wearSeen = true
        wear = state
        inEar = state.anyInEar
        log.info("wear: left \(state.leftInEar ? "in" : "out", privacy: .public) right \(state.rightInEar ? "in" : "out", privacy: .public) (case: \(state.leftInCase, privacy: .public)/\(state.rightInCase, privacy: .public))")
        handleWearChange()
    }

    /// Pauses this Mac's music when an earbud comes out and resumes it when one goes back in, but only if the
    /// user has "Pause when removed" on and the app is the one that paused it (see `PlaybackPolicy`).
    private func handleWearChange() {
        let count = (wear.leftInEar ? 1 : 0) + (wear.rightInEar ? 1 : 0)
        let action = playbackPolicy.update(earCount: count, enabled: autoPause == true) {
            MacPlayback.isPlaying(to: deviceName)
        }
        log.info("ears in: \(count, privacy: .public), pause when removed: \(String(describing: self.autoPause), privacy: .public), playing: \(MacPlayback.playingBundles(to: self.deviceName).joined(separator: ","), privacy: .public), action: \(String(describing: action), privacy: .public)")
        switch action {
        case .none:
            break
        case .pause:
            resumeTask?.cancel()
            pauseMusic()
        case .resume:
            resumeMusic()
        }
    }

    /// Pauses whatever is playing to the earbuds (see `MacPlayback.pause`) and remembers what it stopped.
    /// If nothing could be paused (a browser tab without the Accessibility permission), there is nothing to
    /// resume later, so the policy forgets this pause.
    private func pauseMusic() {
        let playing = MacPlayback.playingBundles(to: deviceName)
        let name = deviceName
        pauseTask = Task { [weak self] in
            let paused = await MacPlayback.pause(playing, deviceName: name)
            guard let self else { return }
            self.pausedMedia = paused
            if paused.isEmpty {
                self.playbackPolicy.finishedResuming()
                self.askForPlaybackControlIfNeeded()
                log.info("could not pause the Mac's music (playing: \(playing.joined(separator: ","), privacy: .public))")
            } else {
                log.info("paused the Mac's music (earbud removed): players \(paused.players.joined(separator: ","), privacy: .public), key \(paused.byKey, privacy: .public)")
            }
        }
    }

    /// The player can still be finishing the pause (the Mac keeps reporting sound for a moment), so wait for
    /// it to settle before pressing Play; if sound is still playing after a few seconds, leave it alone.
    private func resumeMusic() {
        resumeTask?.cancel()
        resumeTask = Task { [weak self] in
            guard let self else { return }
            await self.pauseTask?.value // a pause that is still being checked has to finish first
            guard !Task.isCancelled else { return }
            self.playbackPolicy.finishedResuming()
            let paused = self.pausedMedia
            self.pausedMedia = MacPlayback.PausedMedia()
            guard !paused.isEmpty else { return }
            // What was paused may still be listed as playing for a few seconds (browsers), so only sound
            // from some other app means the user started something else and it must be left alone.
            let others = MacPlayback.playingBundles(to: self.deviceName).filter { !paused.bundles.contains($0) }
            guard others.isEmpty else {
                log.info("did not resume: \(others.joined(separator: ","), privacy: .public) is playing")
                return
            }
            MacPlayback.resume(paused)
            log.info("resumed the Mac's music (an earbud is back in)")
        }
    }

    /// Asks for the Accessibility permission, at most once per launch.
    public func askForPlaybackControlIfNeeded() {
        guard !MacPlayback.isTrusted, !askedForAccessibility else { return }
        askedForAccessibility = true
        MacPlayback.requestTrust()
    }

    private func applyBattery(_ packet: HuaweiPacket) {
        var state = battery
        if let value = packet.byte(1) { state.global = Int(value) }
        if let levels = packet.value(of: 2), levels.count == 3 {
            state.left = Int(levels[0])
            state.right = Int(levels[1])
            state.caseLevel = Int(levels[2])
        }
        if let charging = packet.value(of: 3) {
            if charging.count == 3 {
                state.chargingLeft = charging[0] == 1
                state.chargingRight = charging[1] == 1
                state.chargingCase = charging[2] == 1
            } else {
                let any = charging.contains(1)
                state.chargingLeft = any
                state.chargingRight = any
            }
        }
        battery = state
    }

    private func applyANC(_ packet: HuaweiPacket) {
        guard let data = packet.value(of: 1), data.count == 2,
              let mode = ANCMode(rawValue: Int(data[1])) else { return }
        var state = anc
        state.mode = mode
        switch mode {
        case .cancellation: state.cancellationLevel = CancellationLevel(rawValue: Int(data[0]))
        case .awareness: state.awarenessLevel = AwarenessLevel(rawValue: Int(data[0]))
        case .off: break
        }
        if let intensity = packet.byte(2) { state.adaptiveIntensity = Int(intensity) }
        anc = state
    }

    private func applyInfo(_ packet: HuaweiPacket) {
        func text(_ type: UInt8) -> String? {
            guard let value = packet.value(of: type), !value.isEmpty else { return nil }
            return String(bytes: value, encoding: .utf8)?.trimmingCharacters(in: .controlCharacters)
        }
        var state = info
        state.hardware = text(3) ?? state.hardware
        state.firmware = text(7) ?? state.firmware
        state.serial = text(9) ?? state.serial
        state.submodel = text(10) ?? state.submodel
        state.model = text(15) ?? state.model
        info = state
    }

}
#endif

#if DEBUG
extension FreeBudsClient {
    /// A client filled with plausible values, for rendering the UI without earbuds.
    public static func sample(status: Status = .connected) -> FreeBudsClient {
        let client = FreeBudsClient()
        client.status = status
        client.deviceName = "HUAWEI FreeBuds Pro 5"
        guard status == .connected else { return client }
        client.battery.left = 95
        client.battery.right = 92
        client.battery.caseLevel = 62
        client.battery.global = 92
        client.battery.chargingCase = true
        client.anc.mode = .cancellation
        client.anc.cancellationLevel = .dynamic
        client.anc.awarenessLevel = .normal
        client.anc.adaptiveIntensity = 5
        client.inEar = true
        client.autoPause = true
        client.canControlMacPlayback = true
        client.lowLatency = false
        client.soundPreference = .connectivity
        client.spatialAudio = .off
        client.equalizer = EqualizerPreset.adaptive.rawValue
        client.toggles.adaptiveVolume = false
        client.toggles.conversationAwareness = false
        client.toggles.singleEarbudANC = false
        client.toggles.headControl = false
        client.multiConnect = true
        client.caseTone = true
        client.caseToneChangeable = true
        client.caseOpeningTone = false
        client.devices = [
            ConnectedDevice(id: "a1b2c3d4e5f6", name: "MacBook Pro", kind: .computer, isConnected: true,
                            audioPriority: false, voicePriority: false, isThisMac: true),
            ConnectedDevice(id: "0123456789ab", name: "Galaxy Z Fold7", kind: .phone, isConnected: true,
                            audioPriority: false, voicePriority: false, isThisMac: false),
        ]
        client.customEqualizers = [
            CustomEqualizer(id: 100, name: "My sound effect 1", gains: [40, 0, 30, 0, 0, 0, 0, 10, 20, 30]),
            CustomEqualizer(id: 101, name: "Late night", gains: [-20, -10, 0, 10, 20, 10, 0, -10, -20, -30]),
        ]
        client.info.model = "FreeBuds Pro 5"
        client.info.firmware = "5.4.12"
        client.info.hardware = "HL1SAKM2"
        client.gestures.pinch = [
            .init(.once): GestureCode.playPause, .init(.twice): GestureCode.nextTrack, .init(.thrice): GestureCode.previousTrack,
            .init(.once, inCall: true): GestureCode.answerCall, .init(.twice, inCall: true): GestureCode.rejectCall,
        ]
        client.gestures.pinchHoldLeft = GestureCode.holdNoiseControl
        client.gestures.pinchHoldRight = GestureCode.holdNoiseControl
        client.gestures.ancCycle = 2
        client.gestures.doubleTap = GestureCode.tapPlayPause
        client.gestures.doubleTapInCall = GestureCode.tapAnswerCall
        client.gestures.tripleTapLeft = GestureCode.tapNext
        client.gestures.tripleTapRight = GestureCode.tapNext
        client.gestures.holdLeft = GestureCode.pressAssistant
        client.gestures.holdRight = GestureCode.pressAssistant
        client.gestures.swipe = GestureCode.swipeVolume
        return client
    }
}
#endif

#if DEBUG
extension FreeBudsClient {
    /// Preview helper: the sample client, switched to adaptive awareness.
    public func setAwarenessMode() {
        anc.mode = .awareness
        anc.awarenessLevel = .adaptive
        anc.adaptiveIntensity = 7
    }
}
#endif

#if DEBUG
extension FreeBudsClient {
    /// Preview and test helper: pretend the connection state changed.
    public func simulateStatus(_ newStatus: Status) { status = newStatus }
}
#endif
