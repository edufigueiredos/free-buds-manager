import SwiftUI
import ServiceManagement
import FreeBudsKit

public struct SettingsView: View {
    private let initialPage: String?

    public init() { initialPage = nil }

    /// Used by the preview tool to open a specific page.
    public init(page: String) { initialPage = page }

    public var body: some View {
        ThemedRoot { SettingsBody(initialPage: initialPage) }
    }
}

enum SettingsPage: String, CaseIterable, Identifiable {
    case gestures, sound, equalizer, devices, appearance, app, device

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .gestures: return "Gestures"
        case .sound: return "Sound"
        case .equalizer: return "Equalizer"
        case .devices: return "Devices"
        case .appearance: return "Appearance"
        case .app: return "App"
        case .device: return "Device"
        }
    }

    var icon: String {
        switch self {
        case .gestures: return "hand.tap.fill"
        case .sound: return "speaker.wave.2.fill"
        case .equalizer: return "slider.vertical.3"
        case .devices: return "laptopcomputer.and.iphone"
        case .appearance: return "paintpalette.fill"
        case .app: return "gearshape.fill"
        case .device: return "earbuds"
        }
    }
}

struct SettingsBody: View {
    @EnvironmentObject private var client: FreeBudsClient
    @Environment(\.style) private var style
    @State private var page: SettingsPage
    private let startEditing: Bool

    init(initialPage: String?) {
        startEditing = initialPage == "equalizer-edit"
        let name = initialPage == "equalizer-edit" ? "equalizer" : initialPage
        _page = State(initialValue: name.flatMap(SettingsPage.init(rawValue:)) ?? .gestures)
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(Color.primary.opacity(0.08)).frame(width: 1)
            Group {
                switch page {
                case .gestures: GesturesTab()
                case .sound: SoundTab()
                case .equalizer: EqualizerPage(startEditing: startEditing)
                case .devices: DevicesPage()
                case .appearance: AppearanceTab()
                case .app: AppTab()
                case .device: AboutTab()
                }
            }
            .scrollContentBackground(.hidden)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.top, 26)
        }
        .frame(width: 780, height: 640)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(SettingsPage.allCases) { item in
                let selected = item == page
                Button { page = item } label: {
                    HStack(spacing: 10) {
                        IconBadge(systemName: item.icon, size: 24)
                        Text(item.title).font(.callout.weight(selected ? .semibold : .regular))
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(selected ? style.accent.opacity(style.isNeon ? 0.16 : 0.18) : Color.clear)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(selected && style.isNeon ? style.accent.opacity(0.7) : Color.clear, lineWidth: 1)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.top, 40)
        .frame(width: 190)
    }
}

// MARK: - Gestures

private struct GesturesTab: View {
    @EnvironmentObject private var client: FreeBudsClient

    private var g: GestureSettings { client.gestures }

    var body: some View {
        Form {
            if client.status != .connected {
                Text("Connect the earbuds to change their gestures.").foregroundStyle(.secondary)
            }

            Section("Pinch (squeeze the stem)") {
                pinch("Once", .once, [GestureCode.playPause, GestureCode.none])
                pinch("Twice", .twice, [GestureCode.nextTrack, GestureCode.none])
                pinch("Three times", .thrice, [GestureCode.previousTrack, GestureCode.none])
                pinch("Once, during a call", .once, [GestureCode.answerCall, GestureCode.none], inCall: true)
                pinch("Twice, during a call", .twice, [GestureCode.rejectCall, GestureCode.none], inCall: true)
            }

            Section("Pinch and hold") {
                picker("Left earbud", g.pinchHoldLeft, [GestureCode.holdNoiseControl, GestureCode.holdAssistant, GestureCode.none],
                       Labels.pinchHold) { client.setPinchHold(.left, code: $0) }
                picker("Right earbud", g.pinchHoldRight, [GestureCode.holdNoiseControl, GestureCode.holdAssistant, GestureCode.none],
                       Labels.pinchHold) { client.setPinchHold(.right, code: $0) }
            }

            Section("Noise control cycle") {
                picker("Pinch and hold switches between", g.ancCycle, GestureCode.ancCycles, Labels.ancCycle) {
                    client.setANCCycle(code: $0)
                }
                if g.ancCycle != nil {
                    Text("The earbuds keep one cycle for both sides.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Tap (touch panel)") {
                picker("Double tap", g.doubleTap, [GestureCode.tapPlayPause, GestureCode.none], Labels.doubleTap) {
                    client.setDoubleTap(code: $0)
                }
                picker("Double tap, during a call", g.doubleTapInCall, [GestureCode.tapAnswerCall, GestureCode.none],
                       Labels.doubleTap) { client.setDoubleTapInCall(code: $0) }
                picker("Triple tap, left", g.tripleTapLeft, [GestureCode.tapNext, GestureCode.tapPrevious, GestureCode.none],
                       Labels.tripleTap) { client.setTripleTap(.left, code: $0) }
                picker("Triple tap, right", g.tripleTapRight, [GestureCode.tapNext, GestureCode.tapPrevious, GestureCode.none],
                       Labels.tripleTap) { client.setTripleTap(.right, code: $0) }
            }

            Section("Press and hold") {
                picker("Left earbud", g.holdLeft, [GestureCode.pressAssistant, GestureCode.pressNoiseControl, GestureCode.none],
                       Labels.hold) { client.setHold(.left, code: $0) }
                picker("Right earbud", g.holdRight, [GestureCode.pressAssistant, GestureCode.pressNoiseControl, GestureCode.none],
                       Labels.hold) { client.setHold(.right, code: $0) }
            }

            Section("Swipe") {
                picker("Swipe up / down", g.swipe, [GestureCode.swipeVolume, GestureCode.none], Labels.swipe) {
                    client.setSwipe(code: $0)
                }
            }
        }
        .formStyle(.grouped)
        .disabled(client.status != .connected)
    }

    private func pinch(_ title: LocalizedStringKey, _ kind: PinchKind, _ options: [Int8], inCall: Bool = false) -> some View {
        let slot = GestureSettings.PinchSlot(kind, inCall: inCall)
        return picker(title, g.pinch[slot], options, Labels.pinch) { client.setPinch(slot, code: $0) }
    }

    @ViewBuilder
    private func picker(_ title: LocalizedStringKey, _ selection: Int8?, _ options: [Int8],
                        _ label: @escaping (Int8) -> LocalizedStringKey, _ set: @escaping (Int8) -> Void) -> some View {
        if let selection {
            Picker(title, selection: Binding(get: { selection }, set: set)) {
                // Never hide the value the device currently has, even if we do not know its name.
                ForEach(options.contains(selection) ? options : options + [selection], id: \.self) {
                    Text(label($0)).tag($0)
                }
            }
        }
    }
}

// MARK: - Sound

private struct SoundTab: View {
    @EnvironmentObject private var client: FreeBudsClient

    var body: some View {
        Form {
            if let preference = client.soundPreference {
                Section("Connection") {
                    Picker("Connection", selection: Binding(get: { preference }, set: client.setSoundPreference)) {
                        ForEach(SoundPreference.allCases) { Text(Labels.soundPreference($0)).tag($0) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
            }
            Section {
                toggle("Low latency (games)", client.lowLatency, client.setLowLatency)
                toggle("Pause when removed", client.autoPause, client.setAutoPause)
                toggle("Adaptive volume", client.toggles.adaptiveVolume, client.setAdaptiveVolume)
                toggle("Conversation awareness", client.toggles.conversationAwareness, client.setConversationAwareness)
                toggle("Noise cancelling with one earbud", client.toggles.singleEarbudANC, client.setSingleEarbudANC)
                toggle("Head control (nod to answer a call)", client.toggles.headControl, client.setHeadControl)
            }
            if client.autoPause == true {
                Section("Pause when removed") {
                    HStack {
                        Image(systemName: client.canControlMacPlayback ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(client.canControlMacPlayback ? Palette.good : Color.orange)
                        Text(client.canControlMacPlayback ? "This Mac's music pauses and resumes with the earbuds."
                                                          : "Allow Accessibility so the app can pause this Mac's music.")
                            .font(.callout)
                        Spacer()
                        if !client.canControlMacPlayback {
                            Button("Allow") { MacPlayback.repairAndRequestAccess() }
                                .buttonStyle(AccentButtonStyle())
                        }
                    }
                    Text("The earbuds do not send a pause to the Mac, so the app sends the Play/Pause key when an earbud comes out and again when both are back in. It only resumes what it paused.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !client.canControlMacPlayback {
                        Text("After an update the switch can look on and still not apply, because macOS ties the permission to one build. Allow clears the old one: then switch this app on in the list.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if client.caseTone != nil {
                Section("Charging case") {
                    toggle("Charging case tone", client.caseTone, client.setCaseTone)
                        .disabled(!client.caseToneChangeable)
                    if client.caseTone == true {
                        toggle("Case opening tone", client.caseOpeningTone, client.setCaseOpeningTone)
                            .disabled(!client.caseToneChangeable)
                    }
                    if !client.caseToneChangeable {
                        Text("The case tones can only be changed with both earbuds in the case and the lid open.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if client.status != .connected {
                Text("Connect the earbuds to see their sound options.").foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .disabled(client.status != .connected)
    }

    @ViewBuilder
    private func toggle(_ title: LocalizedStringKey, _ value: Bool?, _ set: @escaping (Bool) -> Void) -> some View {
        if let value {
            Toggle(title, isOn: Binding(get: { value }, set: set))
        }
    }
}

// MARK: - Appearance

private struct AppearanceTab: View {
    @Environment(\.style) private var style
    @AppStorage("appTheme") private var themeName = AppTheme.gold.rawValue
    @AppStorage("neonColorHex") private var neonHex = "#00F0FF"

    private static let neonPresets = ["#00F0FF", "#FF2BD6", "#39FF14", "#FF9F0A", "#8F5BFF", "#FF3B5C"]

    var body: some View {
        Form {
            Section("Theme") {
                HStack(spacing: 14) {
                    ForEach(AppTheme.allCases) { theme in
                        ThemeSwatch(theme: theme, neon: Color(hex: neonHex), selected: themeName == theme.rawValue) {
                            themeName = theme.rawValue
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }

            if themeName == AppTheme.neon.rawValue {
                Section("Neon color") {
                    HStack(spacing: 10) {
                        ForEach(Self.neonPresets, id: \.self) { hex in
                            Button { neonHex = hex } label: {
                                Circle()
                                    .fill(Color(hex: hex))
                                    .frame(width: 24, height: 24)
                                    .overlay(Circle().stroke(Color.white.opacity(neonHex.uppercased() == hex ? 0.95 : 0), lineWidth: 2))
                                    .shadow(color: Color(hex: hex).opacity(0.8), radius: 5)
                            }
                            .buttonStyle(.plain)
                        }
                        Spacer()
                        ColorPicker("Custom", selection: Binding(get: { Color(hex: neonHex) }, set: { neonHex = $0.hexString }),
                                    supportsOpacity: false)
                    }
                    Text("Pure black background: on OLED and Retina XDR displays the unlit pixels stay off.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct ThemeSwatch: View {
    let theme: AppTheme
    let neon: Color
    let selected: Bool
    let action: () -> Void

    var body: some View {
        let style = ThemeStyle.make(theme, neon: neon)
        Button(action: action) {
            VStack(spacing: 7) {
                ZStack {
                    if style.isGlass {
                        Circle().fill(LinearGradient(colors: [.cyan.opacity(0.7), .indigo.opacity(0.7), .pink.opacity(0.6)],
                                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                        Circle().fill(Color.white.opacity(0.35)).frame(width: 30, height: 30)
                            .overlay(Circle().strokeBorder(Color.white.opacity(0.7), lineWidth: 1.2))
                    } else {
                        Circle().fill(style.background ?? Color(nsColor: .windowBackgroundColor))
                        Circle().fill(style.accentGradient).frame(width: 22, height: 22)
                            .shadow(color: style.isNeon ? style.accent : .clear, radius: 6)
                    }
                }
                .frame(width: 46, height: 46)
                .overlay(Circle().stroke(Color.primary.opacity(0.25), lineWidth: 1))
                .overlay(Circle().stroke(style.accent, lineWidth: selected ? 2.5 : 0).padding(-4))
                Text(theme.title).font(.caption.weight(selected ? .semibold : .regular))
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - App

private struct AppTab: View {
    @EnvironmentObject private var client: FreeBudsClient
    @AppStorage("showBatteryInMenuBar") private var showBattery = true
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Toggle("Show battery level in the menu bar", isOn: $showBattery)

            Toggle("Open at login", isOn: Binding(get: { launchAtLogin }, set: setLaunchAtLogin))
            if let loginError {
                Text(loginError).font(.caption).foregroundStyle(.red)
            }

            UpdateSection(updates: client.updates)

            DiagnosticSection()

            if client.candidates.count > 1 {
                Picker("Earbuds", selection: Binding(
                    get: { client.selectedAddress ?? client.candidates.first?.address ?? "" },
                    set: { client.selectDevice(address: $0) }
                )) {
                    ForEach(client.candidates) { Text($0.name).tag($0.address) }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = error.localizedDescription
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}

// MARK: - Diagnostic log

/// A switch for the diagnostic log, plus what is needed to send it with a bug report.
private struct DiagnosticSection: View {
    @State private var enabled = DiagnosticLog.isEnabled
    @State private var copied = false

    var body: some View {
        Section("Diagnostic log") {
            Toggle("Record a diagnostic log", isOn: Binding(get: { enabled }, set: { value in
                DiagnosticLog.setEnabled(value)
                enabled = value
                copied = false
            }))
            Text("Records what the app sees and decides (earbuds in or out, which apps were making sound, permissions) to help find bugs. It does not record Bluetooth addresses, other devices' names or what you play. Turn it on, repeat the problem, then send the log.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if enabled {
                HStack {
                    Button("Copy log") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(DiagnosticLog.contents(), forType: .string)
                        copied = true
                    }
                    Button("Show in Finder") {
                        if FileManager.default.fileExists(atPath: DiagnosticLog.fileURL.path) {
                            NSWorkspace.shared.activateFileViewerSelecting([DiagnosticLog.fileURL])
                        } else {
                            NSWorkspace.shared.open(DiagnosticLog.directory)
                        }
                    }
                    Button("Clear log") { DiagnosticLog.clear(); copied = false }
                    if copied { Text("Copied").font(.caption).foregroundStyle(.secondary) }
                }
            }
        }
    }
}

// MARK: - Updates

/// Checks GitHub for a newer release, only when the button is pressed, and downloads it.
private struct UpdateSection: View {
    @ObservedObject var updates: UpdateChecker

    var body: some View {
        Section("Updates") {
            LabeledContent("Version") { Text(updates.currentVersion).textSelection(.enabled) }
            switch updates.state {
            case .idle, .upToDate, .failed:
                HStack {
                    Button("Check for updates") { Task { await updates.check() } }
                    if updates.state == .upToDate {
                        Text("You have the latest version.").font(.caption).foregroundStyle(.secondary)
                    }
                    if case .failed(let message) = updates.state {
                        Text(message).font(.caption).foregroundStyle(.red)
                    }
                }
            case .checking:
                HStack { ProgressView().controlSize(.small); Text("Checking…").font(.caption).foregroundStyle(.secondary) }
            case .available(let version):
                HStack {
                    Button("Download version \(version)") { Task { await updates.download() } }
                    Text("A new version is available.").font(.caption).foregroundStyle(.secondary)
                }
            case .downloading(let version):
                HStack { ProgressView().controlSize(.small); Text("Downloading version \(version)…").font(.caption).foregroundStyle(.secondary) }
            }
            Text("The app only contacts GitHub when you press the button. After the download, drag the app to Applications and replace the old one.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - About

private struct AboutTab: View {
    @EnvironmentObject private var client: FreeBudsClient

    var body: some View {
        Form {
            row("Name", client.deviceName)
            row("Model", client.info.model)
            row("Firmware", client.info.firmware)
            row("Hardware", client.info.hardware)
            row("Serial number", client.info.serial)
            if let error = client.lastError {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            Section {
                Button("Reload from earbuds") { client.refresh() }
                    .disabled(client.status != .connected)
            }
            Section {
                Text("Unofficial. Not affiliated with or endorsed by Huawei.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private func row(_ title: LocalizedStringKey, _ value: String?) -> some View {
        if let value, !value.isEmpty {
            LabeledContent(title) { Text(value).textSelection(.enabled) }
        }
    }
}
