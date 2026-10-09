// Developer tool: renders the app's screens to PNG with sample data, so the design can be checked without
// earbuds or screen-recording permission.  Usage: FreeBudsPreview <output-dir>
import AppKit
import SwiftUI
import FreeBudsKit
import FreeBudsUI

@MainActor
func render<V: View>(_ view: V, width: CGFloat, height: CGFloat? = nil, dark: Bool, name: String, into directory: String) {
    let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
    let content = view
        .background(Color(nsColor: dark ? NSColor(white: 0.16, alpha: 1) : NSColor(white: 0.96, alpha: 1)))
    let host = NSHostingView(rootView: content)
    host.appearance = appearance
    host.frame = CGRect(x: 0, y: 0, width: width, height: height ?? 800)
    let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
    window.appearance = appearance
    window.contentView = host
    host.layoutSubtreeIfNeeded()
    let finalHeight = height ?? max(host.fittingSize.height, 100)
    host.frame = CGRect(x: 0, y: 0, width: width, height: finalHeight)
    window.setContentSize(host.frame.size)
    host.layoutSubtreeIfNeeded()
    RunLoop.current.run(until: Date().addingTimeInterval(0.4))
    guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
    host.cacheDisplay(in: host.bounds, to: rep)
    let url = URL(fileURLWithPath: directory).appendingPathComponent("\(name).png")
    try? rep.representation(using: .png, properties: [:])?.write(to: url)
    print("wrote \(url.path)")
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)

if CommandLine.arguments.contains("--panel-test") {
    MainActor.assumeIsolated { runPanelTest() }
    exit(0)
}

GlassPreview.approximate = true
let output = CommandLine.arguments.dropFirst().first ?? "build/preview"
try? FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)

MainActor.assumeIsolated {
    let defaults = UserDefaults.standard
    defaults.set("#00F0FF", forKey: "neonColorHex")
    for theme in ["gold", "black", "white", "neon", "classic"] {
        defaults.set(theme, forKey: "appTheme")
        // The system is always dark here: the white theme must still be readable on a dark Mac.
        let dark = true
        render(MenuContentView().environmentObject(FreeBudsClient.sample()), width: 340, dark: dark, name: "menu-\(theme)", into: output)
        let awareness = FreeBudsClient.sample()
        awareness.setAwarenessMode()
        render(MenuContentView().environmentObject(awareness), width: 340, dark: dark, name: "menu-awareness-\(theme)", into: output)
        render(SettingsView(page: "appearance").environmentObject(FreeBudsClient.sample()), width: 780, height: 620, dark: dark,
               name: "settings-appearance-\(theme)", into: output)
    }
    defaults.set("gold", forKey: "appTheme")
    for page in ["equalizer", "equalizer-edit", "devices"] {
        render(SettingsView(page: page).environmentObject(FreeBudsClient.sample()), width: 780, height: 640, dark: true,
               name: "settings-\(page)-gold", into: output)
    }
    render(MenuContentView().environmentObject(FreeBudsClient.sample()), width: 340, dark: true, name: "menu-gold-devices", into: output)
    defaults.set("glass", forKey: "appTheme")
    render(MenuContentView().environmentObject(FreeBudsClient.sample()), width: 340, dark: true, name: "menu-glass", into: output)
    render(SettingsView(page: "appearance").environmentObject(FreeBudsClient.sample()), width: 780, height: 640, dark: true,
           name: "settings-appearance-glass", into: output)
    defaults.set("neon", forKey: "appTheme")
    render(SettingsView(page: "equalizer-edit").environmentObject(FreeBudsClient.sample()), width: 780, height: 640, dark: true,
           name: "settings-equalizer-edit-neon", into: output)
    defaults.set("neon", forKey: "appTheme")
    defaults.set("#FF2BD6", forKey: "neonColorHex")
    render(MenuContentView().environmentObject(FreeBudsClient.sample()), width: 340, dark: true, name: "menu-neon-magenta", into: output)
    render(SettingsView(page: "gestures").environmentObject(FreeBudsClient.sample()), width: 780, height: 620, dark: true,
           name: "settings-gestures-neon", into: output)
    defaults.set("gold", forKey: "appTheme")
    render(SettingsView(page: "gestures").environmentObject(FreeBudsClient.sample()), width: 780, height: 620, dark: true,
           name: "settings-gestures-gold", into: output)
    render(MenuContentView().environmentObject(FreeBudsClient.sample(status: .disconnected)), width: 340, dark: true,
           name: "menu-disconnected-gold", into: output)
    render(MenuContentView().environmentObject(FreeBudsClient.sample(status: .noAnswer)), width: 340, dark: true,
           name: "menu-noanswer-gold", into: output)
}


/// Checks the menu-bar panel behaves: opens under the icon, keeps its top edge when it shrinks and grows,
/// and closes from code (as the Settings button does).
@MainActor
func runPanelTest() {
    func pump(_ seconds: Double = 0.4) { RunLoop.current.run(until: Date().addingTimeInterval(seconds)) }
    var failures = 0
    func check(_ name: String, _ ok: Bool, _ detail: String = "") {
        print(ok ? "PASS" : "FAIL", name, detail)
        if !ok { failures += 1 }
    }

    let theme = CommandLine.arguments.contains("--glass") ? "glass" : "gold"
    UserDefaults.standard.set(theme, forKey: "appTheme")
    let client = FreeBudsClient.sample()
    let controller = MenuBarController(client: client, startClient: false)
    print("theme:", theme)
    pump(1.0)
    let titled = NSApp.windows.filter { $0.isVisible && $0.styleMask.contains(.titled) }
    check("no window opens at launch", titled.isEmpty, "\(titled.map { $0.title })")

    controller.showPanel()
    pump(0.6)
    let opened = controller.panelFrame
    check("panel opens", controller.isPanelVisible, "frame \(opened)")
    if let icon = controller.statusItemFrame {
        check("panel sits under the icon", abs(opened.maxY - (icon.minY - 6)) < 2, "top \(opened.maxY) icon bottom \(icon.minY)")
    }
    let top = opened.maxY

    // The earbuds disconnect while the panel is open: the content shrinks.
    client.simulateStatus(.disconnected)
    pump(0.8)
    let shrunk = controller.panelFrame
    check("panel shrinks", shrunk.height < opened.height, "\(Int(opened.height)) -> \(Int(shrunk.height))")
    check("top edge stays put when it shrinks", abs(shrunk.maxY - top) < 2, "top \(shrunk.maxY) vs \(top)")

    client.simulateStatus(.connected)
    pump(0.8)
    check("top edge stays put when it grows", abs(controller.panelFrame.maxY - top) < 2, "top \(controller.panelFrame.maxY)")

    controller.showSettings()
    pump(0.5)
    check("opening Settings closes the panel", !controller.isPanelVisible)
    check("settings window opens", controller.isSettingsVisible)

    controller.showPanel()
    pump(0.4)
    controller.hidePanel()
    pump(0.3)
    check("panel closes from code", !controller.isPanelVisible)

    print(failures == 0 ? "ALL PASSED" : "\(failures) FAILED")
}
