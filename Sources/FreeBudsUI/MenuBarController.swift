import SwiftUI
import AppKit
import Combine
import FreeBudsKit

/// What the menu needs to open the settings window (the popover lives outside SwiftUI's scene system).
public struct SettingsOpener {
    public var open: () -> Void
    public init(_ open: @escaping () -> Void) { self.open = open }
}

private struct SettingsOpenerKey: EnvironmentKey {
    static let defaultValue = SettingsOpener {}
}

extension EnvironmentValues {
    var settingsOpener: SettingsOpener {
        get { self[SettingsOpenerKey.self] }
        set { self[SettingsOpenerKey.self] = newValue }
    }
}

/// Puts a view on a Liquid Glass backdrop: the real `NSGlassEffectView` on macOS 26 and later, a
/// translucent blur on earlier systems.
@MainActor
enum GlassChrome {
    static func wrap(_ content: NSView, radius: CGFloat, material: NSVisualEffectView.Material) -> NSView {
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = radius
            glass.contentView = content
            return glass
        }
        let effect = NSVisualEffectView()
        effect.material = material
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = radius
        effect.layer?.cornerCurve = .continuous
        effect.layer?.masksToBounds = true
        content.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(content)
        pin(content, to: effect)
        return effect
    }

    static func pin(_ view: NSView, to parent: NSView) {
        view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: parent.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: parent.trailingAnchor),
            view.topAnchor.constraint(equalTo: parent.topAnchor),
            view.bottomAnchor.constraint(equalTo: parent.bottomAnchor),
        ])
    }
}

/// A plain container whose child is the hosting controller, so the glass or flat backdrop can be swapped.
private final class ContainerController: NSViewController {
    override func loadView() { view = NSView() }
}

/// A borderless panel that can take focus without activating a window of its own.
private final class PopoverPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// The menu-bar icon, its popover and the settings window.
///
/// This replaces SwiftUI's `MenuBarExtra`, whose window cannot be closed from code and slides down when its
/// content shrinks. Here the panel opens under the icon, keeps its top edge where it is when the content
/// changes, and closes on demand, when it loses focus, or on a click anywhere else.
@MainActor
public final class MenuBarController: NSObject {
    public let client: FreeBudsClient
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let panel: PopoverPanel
    private let host: NSHostingController<AnyView>
    private let panelContainer = ContainerController()
    private var panelIsGlass: Bool?
    private var settingsHost: NSHostingController<AnyView>?
    private let settingsContainer = ContainerController()
    private var settingsIsGlass: Bool?
    private var settingsWindow: NSWindow?
    private var cancellables: Set<AnyCancellable> = []
    private var clickMonitor: Any?
    private var lastHidden = Date.distantPast
    private var sizeObservation: NSKeyValueObservation?

    private let cornerRadius: CGFloat = 14

    public init(client: FreeBudsClient, startClient: Bool = true) {
        self.client = client
        panel = PopoverPanel(contentRect: NSRect(x: 0, y: 0, width: 340, height: 200),
                             styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        host = NSHostingController(rootView: AnyView(EmptyView()))
        super.init()

        host.rootView = AnyView(MenuContentView()
            .environmentObject(client)
            .environment(\.settingsOpener, SettingsOpener { [weak self] in self?.showSettings() }))
        host.sizingOptions = [.preferredContentSize]

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panelContainer.addChild(host)
        panel.contentViewController = panelContainer
        applyPanelChrome()

        // Keep the top edge fixed when the content changes height.
        sizeObservation = host.observe(\.preferredContentSize, options: [.new]) { [weak self] _, change in
            guard let size = change.newValue else { return }
            MainActor.assumeIsolated { self?.resizePanel(to: size) }
        }

        NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: panel, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.hidePanel() }
        }

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseDown])
        }
        client.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in DispatchQueue.main.async { self?.updateLabel() } }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateLabel()
                self?.applyPanelChrome()
                self?.applySettingsChrome()
            }
            .store(in: &cancellables)
        updateLabel()
        if startClient { client.start() }
    }

    // MARK: - Status item

    private func updateLabel() {
        guard let button = statusItem.button else { return }
        let image = NSImage(systemSymbolName: "earbuds", accessibilityDescription: "FreeBuds")
        image?.isTemplate = true
        button.image = image
        let showBattery = UserDefaults.standard.object(forKey: "showBatteryInMenuBar") as? Bool ?? true
        if showBattery, client.status == .connected, let level = client.battery.summary {
            button.title = " \(level)%"
            button.imagePosition = .imageLeading
        } else {
            button.title = ""
            button.imagePosition = .imageOnly
        }
    }

    @objc private func statusItemClicked() {
        // Clicking the icon of an open panel first makes the panel lose focus (hiding it), then lands here.
        if panel.isVisible || Date().timeIntervalSince(lastHidden) < 0.25 {
            hidePanel()
        } else {
            showPanel()
        }
    }

    // MARK: - Backdrop (flat, or Liquid Glass)

    private var isGlassTheme: Bool { UserDefaults.standard.string(forKey: "appTheme") == AppTheme.glass.rawValue }

    private func applyPanelChrome() {
        let glass = isGlassTheme
        guard panelIsGlass != glass else { return }
        panelIsGlass = glass
        let container = panelContainer.view
        container.subviews.forEach { $0.removeFromSuperview() }
        host.view.removeFromSuperview()
        let radius: CGFloat = glass ? 24 : cornerRadius
        host.view.wantsLayer = true
        host.view.layer?.cornerRadius = glass ? 0 : cornerRadius
        host.view.layer?.cornerCurve = .continuous
        host.view.layer?.masksToBounds = true
        let content: NSView = glass ? GlassChrome.wrap(host.view, radius: radius, material: .popover) : host.view
        container.addSubview(content)
        GlassChrome.pin(content, to: container)
        container.wantsLayer = true
        container.layer?.cornerRadius = radius
        container.layer?.cornerCurve = .continuous
        container.layer?.masksToBounds = true
    }

    private func applySettingsChrome() {
        guard let window = settingsWindow, let settingsHost else { return }
        let glass = isGlassTheme
        guard settingsIsGlass != glass else { return }
        settingsIsGlass = glass
        let container = settingsContainer.view
        container.subviews.forEach { $0.removeFromSuperview() }
        settingsHost.view.removeFromSuperview()
        let content: NSView = glass ? GlassChrome.wrap(settingsHost.view, radius: 0, material: .underWindowBackground) : settingsHost.view
        container.addSubview(content)
        GlassChrome.pin(content, to: container)
        window.isOpaque = !glass
        window.backgroundColor = glass ? .clear : .windowBackgroundColor
    }

    // MARK: - Panel

    public var isPanelVisible: Bool { panel.isVisible }
    /// The panel's frame, for tests.
    public var panelFrame: NSRect { panel.frame }
    /// The status item's frame in screen coordinates, for tests.
    public var statusItemFrame: NSRect? { statusItem.button?.window?.frame }

    public func showPanel() {
        guard let buttonWindow = statusItem.button?.window else { return }
        let size = host.preferredContentSize == .zero ? host.view.fittingSize : host.preferredContentSize
        let anchor = buttonWindow.frame
        var x = anchor.midX - size.width / 2
        if let screen = buttonWindow.screen ?? NSScreen.main {
            x = min(max(x, screen.visibleFrame.minX + 8), screen.visibleFrame.maxX - size.width - 8)
        }
        let top = anchor.minY - 6
        panel.setFrame(NSRect(x: x, y: top - size.height, width: size.width, height: size.height), display: true)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        client.refresh()

        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.hidePanel() }
        }
    }

    public func hidePanel() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        lastHidden = Date()
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = nil
    }

    private func resizePanel(to size: NSSize) {
        guard size.width > 0, size.height > 0 else { return }
        let frame = panel.frame
        guard abs(frame.height - size.height) > 0.5 || abs(frame.width - size.width) > 0.5 else { return }
        panel.setFrame(NSRect(x: frame.minX, y: frame.maxY - size.height, width: size.width, height: size.height), display: true)
    }

    // MARK: - Settings window

    public func showSettings() {
        hidePanel()
        if settingsWindow == nil {
            let controller = NSHostingController(rootView: AnyView(SettingsView().environmentObject(client)))
            controller.sizingOptions = [.preferredContentSize]
            settingsHost = controller
            settingsContainer.addChild(controller)
            let window = NSWindow(contentViewController: settingsContainer)
            window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.title = "Free Buds Manager"
            settingsWindow = window
            settingsIsGlass = nil
            applySettingsChrome()
            window.setContentSize(controller.view.fittingSize)
            window.center()
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    public var isSettingsVisible: Bool { settingsWindow?.isVisible ?? false }
}
