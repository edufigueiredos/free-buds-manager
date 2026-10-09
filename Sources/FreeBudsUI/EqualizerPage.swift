import SwiftUI
import FreeBudsKit

/// Settings page: pick a preset or a custom profile, and edit custom ones band by band.
struct EqualizerPage: View {
    @EnvironmentObject private var client: FreeBudsClient
    @Environment(\.style) private var style
    @State private var editing: CustomEqualizer?
    @State private var deleting: CustomEqualizer?

    init(startEditing: Bool = false) {
        _editing = State(initialValue: startEditing
                         ? CustomEqualizer(id: 102, name: "My sound effect 3", gains: [40, 0, 30, 0, 0, 0, 0, 10, 20, 30]) : nil)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let profile = editing {
                    CustomEqualizerEditor(profile: profile) { saved in
                        if let saved { client.saveCustomEqualizer(saved) }
                        editing = nil
                    }
                } else {
                    presets
                    customProfiles
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .disabled(client.status != .connected)
        .confirmationDialog("Delete this profile?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let deleting { client.deleteCustomEqualizer(deleting) }
                deleting = nil
            }
        } message: {
            Text(verbatim: deleting?.name ?? "")
        }
    }

    private var presets: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Presets")
            let columns = [GridItem(.adaptive(minimum: 130), spacing: 8)]
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(EqualizerPreset.allCases) { preset in
                    row(selected: client.equalizer == preset.rawValue, title: Text(Labels.equalizer(preset))) {
                        client.selectEqualizer(id: preset.rawValue)
                    }
                }
            }
        }
    }

    private var customProfiles: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Custom profiles")
            if client.customEqualizers.isEmpty {
                Text("No custom profiles yet.").font(.callout).foregroundStyle(.secondary)
            }
            ForEach(client.customEqualizers) { profile in
                HStack(spacing: 8) {
                    row(selected: client.equalizer == profile.id, title: Text(verbatim: profile.name)) {
                        client.selectEqualizer(id: profile.id)
                    }
                    Button { editing = profile } label: { Image(systemName: "slider.vertical.3") }
                        .help("Edit")
                    Button { deleting = profile } label: { Image(systemName: "trash") }
                        .help("Delete")
                }
                .buttonStyle(.plain)
            }
            if let id = client.nextCustomEqualizerID {
                Button {
                    editing = CustomEqualizer(id: id, name: "\(String(localized: "My sound effect")) \(id - CustomEqualizer.firstID + 1)")
                } label: {
                    Label("New profile", systemImage: "plus")
                }
                .buttonStyle(AccentButtonStyle())
            } else {
                Text("The earbuds are full: delete a profile to add another.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func row(selected: Bool, title: Text, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                title.font(.callout.weight(selected ? .semibold : .regular))
                Spacer(minLength: 0)
                if selected { Image(systemName: "checkmark").font(.caption.weight(.bold)) }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .foregroundStyle(selected ? style.selectedForeground : Color.primary)
            .background(SelectableBackground(selected: selected))
        }
        .buttonStyle(.plain)
    }
}

/// Ten vertical sliders, a name field and Save / Cancel. Dragging plays the curve on the earbuds.
struct CustomEqualizerEditor: View {
    @EnvironmentObject private var client: FreeBudsClient
    @Environment(\.style) private var style
    @State var profile: CustomEqualizer
    let finish: (CustomEqualizer?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                SectionLabel("Name")
                TextField("Name", text: $profile.name)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: profile.name) { _, name in
                        if name.utf8.count > CustomEqualizer.maxNameBytes { profile.name = String(name.prefix(CustomEqualizer.maxNameBytes)) }
                    }
            }

            Card(padding: 14) {
                VStack(spacing: 10) {
                    HStack {
                        Text("+6 dB").font(.caption2).foregroundStyle(.secondary)
                        Spacer()
                        Button { reset() } label: { Label("Reset", systemImage: "arrow.counterclockwise") }
                            .buttonStyle(.plain)
                            .font(.caption)
                    }
                    HStack(alignment: .top, spacing: 0) {
                        ForEach(profile.gains.indices, id: \.self) { band in
                            VStack(spacing: 6) {
                                VerticalGainSlider(value: Binding(
                                    get: { profile.gains[band] },
                                    set: { profile.gains[band] = $0; client.previewCustomEqualizer(profile) }
                                ))
                                .frame(height: 190)
                                Text(CustomEqualizer.bandLabels[band]).font(.caption2).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    HStack {
                        Text("−6 dB").font(.caption2).foregroundStyle(.secondary)
                        Spacer()
                    }
                }
            }
            Text("Drag the sliders while music is playing to hear the change.").font(.caption).foregroundStyle(.secondary)

            HStack {
                Button("Cancel") {
                    // Put the earbuds back on what they were playing before the preview.
                    if let current = client.equalizer { client.selectEqualizer(id: current) }
                    finish(nil)
                }
                .buttonStyle(QuietButtonStyle())
                Spacer()
                Button("Save") { finish(profile) }
                    .buttonStyle(AccentButtonStyle())
                    .disabled(profile.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func reset() {
        profile.gains = CustomEqualizer.flat
        client.previewCustomEqualizer(profile)
    }
}

/// A vertical slider in 1 dB steps, from −6 to +6 dB, with the zero line marked.
struct VerticalGainSlider: View {
    @Environment(\.style) private var style
    @Binding var value: Int

    private let step = 10

    var body: some View {
        GeometryReader { proxy in
            let height = proxy.size.height
            let range = CustomEqualizer.gainRange
            let span = CGFloat(range.upperBound - range.lowerBound)
            let y = { (v: Int) in height * (1 - CGFloat(v - range.lowerBound) / span) }
            ZStack(alignment: .top) {
                Capsule().fill(Color.primary.opacity(0.14)).frame(width: 5).frame(maxHeight: .infinity)
                Capsule()
                    .fill(style.accent)
                    .frame(width: 5, height: abs(y(value) - y(0)))
                    .offset(y: min(y(value), y(0)))
                    .shadow(color: style.isNeon ? style.accent.opacity(0.8) : .clear, radius: 4)
                Rectangle().fill(Color.primary.opacity(0.35)).frame(width: 14, height: 1).offset(y: y(0))
                Circle()
                    .fill(Color.white)
                    .frame(width: 16, height: 16)
                    .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                    .offset(y: y(value) - 8)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                let fraction = 1 - min(max(drag.location.y / height, 0), 1)
                let raw = Double(range.lowerBound) + Double(fraction) * Double(span)
                let snapped = Int((raw / Double(step)).rounded()) * step
                let clamped = min(max(snapped, range.lowerBound), range.upperBound)
                if clamped != value { value = clamped }
            })
        }
        .frame(width: 28)
        .accessibilityValue(Text("\(Double(value) / 10, specifier: "%.0f") dB"))
    }
}
