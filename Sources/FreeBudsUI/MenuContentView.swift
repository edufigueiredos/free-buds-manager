import SwiftUI
import FreeBudsKit

public struct MenuContentView: View {
    public init() {}

    public var body: some View {
        ThemedRoot { MenuBody() }
    }
}

struct MenuBody: View {
    @EnvironmentObject private var client: FreeBudsClient
    @Environment(\.settingsOpener) private var settingsOpener
    @Environment(\.style) private var style

    var body: some View {
        VStack(spacing: 12) {
            header

            switch client.status {
            case .connected:
                BatteryRow(battery: client.battery)
                NoiseControlSection()
                if client.spatialAudio != nil || client.equalizer != nil {
                    SoundSection()
                }
                togglesCard
                if client.devices.count > 1 { DevicesCard() }
            case .connecting:
                Card {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Connecting…").foregroundStyle(.secondary)
                    }
                }
            case .noAnswer:
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("The earbuds are connected but not answering the app.")
                            .font(.callout.weight(.medium))
                        Text("They talk to one app at a time. Close the Huawei app on your phone, or put the earbuds in the case and take them out.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Try again") { client.retryNow() }
                            .buttonStyle(AccentButtonStyle())
                    }
                }
            case .disconnected:
                Card {
                    HStack {
                        Text("Open the case near this Mac.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Connect") { client.connectToMac() }
                            .buttonStyle(AccentButtonStyle())
                    }
                }
            case .noDevice:
                Card {
                    Text("Pair your FreeBuds in System Settings › Bluetooth, then come back.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            footer
        }
        .padding(14)
        .frame(width: 340)
        .overlay {
            if !style.isGlass {
                RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.14), lineWidth: 1)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 11) {
            Image(systemName: "earbuds")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(style.selectedForeground)
                .frame(width: 40, height: 40)
                .background(SelectableBackground(selected: true))
            VStack(alignment: .leading, spacing: 2) {
                Text(client.deviceName.isEmpty ? "FreeBuds" : client.deviceName)
                    .font(.headline)
                HStack(spacing: 5) {
                    Circle().fill(statusColor).frame(width: 7, height: 7)
                    Text(statusText).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if client.status == .connected, let inEar = client.inEar {
                Image(systemName: inEar ? "ear.fill" : "ear")
                    .foregroundStyle(inEar ? style.accent : Color.secondary)
                    .help("Earbuds in ear")
            }
        }
    }

    private var statusColor: Color {
        switch client.status {
        case .connected: return Palette.good
        case .connecting, .noAnswer: return .orange
        case .disconnected, .noDevice: return .gray
        }
    }

    private var statusText: LocalizedStringKey {
        switch client.status {
        case .connected: return "Connected"
        case .connecting: return "Connecting…"
        case .noAnswer: return "Connected, not answering"
        case .disconnected: return "Not connected to this Mac"
        case .noDevice: return "No earbuds found"
        }
    }

    // MARK: - Toggles

    private var togglesCard: some View {
        Card(padding: 10) {
            VStack(spacing: 0) {
                rows
                playbackPermissionHint
            }
        }
    }

    @ViewBuilder
    private var rows: some View {
        let items = toggleItems
        ForEach(items.indices, id: \.self) { index in
            if index > 0 { Divider().padding(.leading, 34) }
            items[index]
        }
    }

    private var toggleItems: [ToggleRow] {
        var items: [ToggleRow] = []
        if let value = client.autoPause {
            items.append(ToggleRow(icon: "pause.fill", title: "Pause when removed", isOn: value, set: client.setAutoPause))
        }
        if let value = client.lowLatency {
            items.append(ToggleRow(icon: "gamecontroller.fill", title: "Low latency (games)", isOn: value, set: client.setLowLatency))
        }
        if let value = client.toggles.adaptiveVolume {
            items.append(ToggleRow(icon: "speaker.wave.2.fill", title: "Adaptive volume", isOn: value, set: client.setAdaptiveVolume))
        }
        if let value = client.toggles.conversationAwareness {
            items.append(ToggleRow(icon: "bubble.left.and.bubble.right.fill", title: "Conversation awareness",
                                   isOn: value, set: client.setConversationAwareness))
        }
        return items
    }

    /// Pausing this Mac's music needs the Accessibility permission; say so right where the switch is.
    @ViewBuilder
    private var playbackPermissionHint: some View {
        if client.autoPause == true && !client.canControlMacPlayback {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.caption)
                Text("To pause this Mac's music, allow Accessibility.").font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Button("Allow") { MacPlayback.repairAndRequestAccess() }
                    .buttonStyle(QuietButtonStyle())
            }
            .padding(.top, 6)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button {
                settingsOpener.open()
            } label: {
                Label("Settings…", systemImage: "gearshape")
            }
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
        .buttonStyle(.plain)
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 2)
    }
}

// MARK: - Battery

struct BatteryRow: View {
    let battery: BatteryState

    var body: some View {
        HStack(spacing: 8) {
            BatteryTile(icon: "l.circle.fill", title: "Left", level: battery.left ?? battery.global, charging: battery.chargingLeft)
            BatteryTile(icon: "r.circle.fill", title: "Right", level: battery.right ?? battery.global, charging: battery.chargingRight)
            if let caseLevel = battery.caseLevel {
                BatteryTile(icon: "earbuds.case.fill", title: "Case", level: caseLevel, charging: battery.chargingCase)
            }
        }
    }
}

struct BatteryTile: View {
    @Environment(\.style) private var style
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let icon: String
    let title: LocalizedStringKey
    let level: Int?
    let charging: Bool
    @State private var pulse = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.caption).foregroundStyle(.secondary)
                Text(title).font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if charging {
                    Image(systemName: "bolt.fill")
                        .font(.caption2)
                        .foregroundStyle(color)
                        .opacity(glowing ? 1 : 0.45)
                        .shadow(color: color.opacity(glowing ? 0.9 : 0), radius: glowing ? 6 : 0)
                }
            }
            Text(level.map { "\($0)%" } ?? "–")
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .monospacedDigit()
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.12))
                    Capsule().fill(color).frame(width: proxy.size.width * CGFloat(level ?? 0) / 100)
                        .opacity(charging ? (glowing ? 1 : 0.6) : 1)
                        .shadow(color: color.opacity(glowRadius > 0 ? 0.85 : 0), radius: glowRadius)
                }
            }
            .frame(height: 4)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(style.card))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(style.cardStroke, lineWidth: 1))
        .accessibilityElement(children: .combine)
        .onAppear { updatePulse() }
        .onChange(of: charging) { _, _ in updatePulse() }
    }

    /// While charging the bar breathes in the theme's own color; otherwise it is steady.
    private var glowing: Bool { !charging || reduceMotion || pulse }

    private var glowRadius: CGFloat {
        if charging { return reduceMotion ? 4 : (pulse ? 10 : 2) }
        return style.isNeon ? 4 : 0
    }

    private func updatePulse() {
        pulse = false
        guard charging, !reduceMotion else { return }
        withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { pulse = true }
    }

    private var color: Color {
        guard let level else { return .gray }
        if charging { return style.batteryGood }
        return level <= 15 ? .red : (level <= 30 ? .orange : style.batteryGood)
    }
}

// MARK: - Noise control

struct NoiseControlSection: View {
    @EnvironmentObject private var client: FreeBudsClient

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Noise control")

            HStack(spacing: 8) {
                ForEach(ANCMode.allCases) { mode in
                    ModeTile(icon: icon(mode), title: Labels.ancMode(mode), selected: client.anc.mode == mode) {
                        client.setANCMode(mode)
                    }
                }
            }

            switch client.anc.mode {
            case .cancellation:
                ChipRow(options: CancellationLevel.allCases.map { .init(value: $0, title: Labels.cancellationLevel($0)) },
                        selection: client.anc.cancellationLevel) { client.setCancellationLevel($0) }
            case .awareness:
                ChipRow(options: AwarenessLevel.allCases.map { .init(value: $0, title: Labels.awarenessLevel($0)) },
                        selection: client.anc.awarenessLevel) { client.setAwarenessLevel($0) }
                if client.anc.awarenessLevel == .adaptive {
                    AdaptiveIntensitySlider()
                }
            default:
                EmptyView()
            }
        }
    }

    private func icon(_ mode: ANCMode) -> String {
        switch mode {
        case .off: return "speaker.slash"
        case .cancellation: return "waveform.slash"
        case .awareness: return "ear.and.waveform"
        }
    }
}

struct AdaptiveIntensitySlider: View {
    @EnvironmentObject private var client: FreeBudsClient
    @State private var value = 5.0
    @State private var isDragging = false

    var body: some View {
        VStack(spacing: 2) {
            Slider(value: $value, in: 0...10, step: 1) { editing in
                isDragging = editing
                if !editing { client.setAdaptiveIntensity(Int(value)) }
            }
            .controlSize(.small)
            HStack {
                Text("More noise")
                Spacer()
                Text("Less noise")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .onAppear { value = Double(client.anc.adaptiveIntensity ?? 5) }
        .onChange(of: client.anc.adaptiveIntensity) { _, new in
            if !isDragging, let new { value = Double(new) }
        }
    }
}

// MARK: - Sound

struct SoundSection: View {
    @EnvironmentObject private var client: FreeBudsClient

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if client.spatialAudio != nil {
                SectionLabel("Spatial audio")
                ChipRow(options: SpatialAudio.allCases.map { .init(value: $0, title: Labels.spatialAudio($0)) },
                        selection: client.spatialAudio) { client.setSpatialAudio($0) }
            }
            if let current = client.equalizer {
                HStack {
                    SectionLabel("Equalizer")
                    Spacer()
                    Menu {
                        ForEach(EqualizerPreset.allCases) { preset in
                            Button { client.selectEqualizer(id: preset.rawValue) } label: {
                                if preset.rawValue == current {
                                    Label(Labels.equalizer(preset), systemImage: "checkmark")
                                } else {
                                    Text(Labels.equalizer(preset))
                                }
                            }
                        }
                        if !client.customEqualizers.isEmpty {
                            Divider()
                            ForEach(client.customEqualizers) { profile in
                                Button { client.selectEqualizer(id: profile.id) } label: {
                                    if profile.id == current {
                                        Label(profile.name, systemImage: "checkmark")
                                    } else {
                                        Text(verbatim: profile.name)
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Labels.equalizerName(id: current, custom: client.customEqualizers)
                            Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .bold))
                        }
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(SelectableBackground(selected: false, capsule: true))
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                    .menuIndicator(.hidden)
                    .fixedSize()
                }
            }
        }
    }
}

// MARK: - Devices

/// The devices the earbuds are connected to, with a switch to connect or release each one.
struct DevicesCard: View {
    @EnvironmentObject private var client: FreeBudsClient

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Devices")
            Card(padding: 10) {
                VStack(spacing: 0) {
                    ForEach(Array(client.devices.enumerated()), id: \.element.id) { index, device in
                        if index > 0 { Divider().padding(.leading, 34) }
                        DeviceRow(device: device)
                    }
                }
            }
        }
    }
}

struct DeviceRow: View {
    @EnvironmentObject private var client: FreeBudsClient
    @Environment(\.style) private var style
    let device: ConnectedDevice
    /// The quick panel shows the two priorities as small icon switches; the settings page has full rows.
    var showsPriorityIcons = true

    var body: some View {
        HStack(spacing: 10) {
            IconBadge(systemName: device.kind == .phone ? "iphone" : "laptopcomputer", size: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: device.name).font(.callout).lineLimit(1)
                Text(device.isThisMac ? "This Mac" : (device.isConnected ? "Connected" : "Not connected"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if showsPriorityIcons && device.isConnected {
                PriorityIcon(systemName: "lock.fill", isOn: device.audioPriority, enabled: true,
                             help: "Prioritize all audio") { client.setAudioPriority(device, enabled: $0) }
                PriorityIcon(systemName: "bell.badge.fill", isOn: device.voicePriority, enabled: !device.audioPriority,
                             help: "Prioritize voice messages") { client.setVoicePriority(device, enabled: $0) }
            }
            if showsPriorityIcons {
                // Quick panel: an icon, so the name keeps its room. The same button works for this Mac.
                let help: LocalizedStringKey = device.isConnected ? (device.isThisMac ? "Disconnect this Mac" : "Disconnect") : "Connect"
                Button {
                    if device.isConnected { client.disconnect(device) } else { client.connect(device) }
                } label: {
                    Image(systemName: device.isConnected ? "xmark" : "link")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 26, height: 26)
                        .foregroundStyle(device.isConnected ? Color.secondary : style.selectedForeground)
                        .background(SelectableBackground(selected: !device.isConnected, capsule: true))
                }
                .buttonStyle(.plain)
                .help(help)
                .accessibilityLabel(Text(help))
            } else {
                Button(device.isConnected ? "Disconnect" : "Connect") {
                    if device.isConnected { client.disconnect(device) } else { client.connect(device) }
                }
                .buttonStyle(device.isConnected ? AnyButtonStyle(QuietButtonStyle()) : AnyButtonStyle(AccentButtonStyle()))
                .fixedSize()
            }
        }
        .padding(.vertical, 5)
    }
}

/// A small round switch for one of the two device priorities.
struct PriorityIcon: View {
    @Environment(\.style) private var style
    let systemName: String
    let isOn: Bool
    let enabled: Bool
    let help: LocalizedStringKey
    let set: (Bool) -> Void

    var body: some View {
        Button { set(!isOn) } label: {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 26, height: 26)
                .foregroundStyle(isOn ? style.selectedForeground : Color.secondary)
                .background(SelectableBackground(selected: isOn, capsule: true))
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1 : 0.4)
        .disabled(!enabled)
        .help(help)
        .accessibilityLabel(Text(help))
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

struct QuietButtonStyle: ButtonStyle {
    @Environment(\.style) private var style

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(SelectableBackground(selected: false, capsule: true))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// Lets two different button styles be chosen at runtime.
struct AnyButtonStyle: ButtonStyle {
    private let make: (Configuration) -> AnyView

    init<S: ButtonStyle>(_ style: S) {
        make = { AnyView(style.makeBody(configuration: $0)) }
    }

    func makeBody(configuration: Configuration) -> some View { make(configuration) }
}
