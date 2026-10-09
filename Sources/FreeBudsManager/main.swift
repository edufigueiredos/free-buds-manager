import AppKit
import FreeBudsKit
import FreeBudsUI

/// The app has no window of its own: the menu-bar icon, its panel and the settings window are all created by
/// `MenuBarController`. It is plain AppKit on purpose: a SwiftUI `App` needs at least one scene, and an empty
/// one made macOS open a blank "Settings" window on the first launch.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: MenuBarController?
    private var client: FreeBudsClient?

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMainMenu()
        let client = FreeBudsClient()
        self.client = client
        controller = MenuBarController(client: client)
        // Handy for testing: `open "Free Buds Manager.app" --args --connect` asks macOS to connect the earbuds.
        if CommandLine.arguments.contains("--connect") { client.connectToMac() }
    }

    /// Closes the control channel properly, so the earbuds do not keep a dead session.
    func applicationWillTerminate(_ notification: Notification) {
        client?.shutdown()
    }

    /// An app without a main menu gets no Cut / Copy / Paste in its text fields (the equalizer profile name),
    /// so give it the standard Edit menu, plus Quit.
    private func installMainMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Hide Free Buds Manager", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Free Buds Manager", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)

        NSApp.mainMenu = main
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
    withExtendedLifetime(delegate) {}
}
