import SwiftUI
import FreeBudsKit

/// Settings page: the devices the earbuds are paired with, which one has priority, and multi-connection.
struct DevicesPage: View {
    @EnvironmentObject private var client: FreeBudsClient
    @State private var confirmingMultiOff = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                multiConnection
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel("Devices")
                    if client.devices.isEmpty {
                        Text("Connect the earbuds to see their devices.").font(.callout).foregroundStyle(.secondary)
                    }
                    ForEach(client.devices) { device in
                        DeviceCard(device: device)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .disabled(client.status != .connected)
        .onAppear { client.refreshDevices() }
        .confirmationDialog("Turn off multi-connection?", isPresented: $confirmingMultiOff, titleVisibility: .visible) {
            Button("Turn off", role: .destructive) { client.setMultiConnect(false) }
        } message: {
            Text("Turning this off disconnects every device but one, which may be this Mac.")
        }
    }

    @ViewBuilder
    private var multiConnection: some View {
        if let enabled = client.multiConnect {
            Card {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Multi-connection").font(.callout.weight(.medium))
                        Spacer()
                        Toggle("Multi-connection", isOn: Binding(
                            get: { enabled },
                            set: { if $0 { client.setMultiConnect(true) } else { confirmingMultiOff = true } }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                    }
                    Text("Stay connected to several devices and switch between them.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct DeviceCard: View {
    @EnvironmentObject private var client: FreeBudsClient
    let device: ConnectedDevice

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                DeviceRow(device: device, showsPriorityIcons: false)
                if device.isConnected {
                    Divider()
                    priority("Prioritize all audio", "The earbuds play audio only from this device, including calls and the assistant.",
                             isOn: device.audioPriority, enabled: true) { client.setAudioPriority(device, enabled: $0) }
                    priority("Prioritize voice messages", "The earbuds work only with this device's assistant.",
                             isOn: device.voicePriority, enabled: !device.audioPriority) { client.setVoicePriority(device, enabled: $0) }
                }
            }
        }
    }

    private func priority(_ title: LocalizedStringKey, _ detail: LocalizedStringKey, isOn: Bool, enabled: Bool,
                          set: @escaping (Bool) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(.callout)
                Spacer()
                Toggle(title, isOn: Binding(get: { isOn }, set: set)).labelsHidden().toggleStyle(.switch).controlSize(.small)
            }
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
        .opacity(enabled ? 1 : 0.45)
        .disabled(!enabled)
    }
}
