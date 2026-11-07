import Foundation
import AppKit
import SwiftUI
import Combine

/// Per-zone runtime objects that must outlive SwiftUI view rebuilds.
public final class ZoneController: ObservableObject {
    public let zoneID: UUID
    public let panel: ZonePanel
    public let store: ZoneFileStore
    @Published public var isHoverExpanded = false
    /// True while the pointer is over the zone (drives auto-hiding title bars).
    @Published public var isPointerInside = false
    /// Lives here (not in view @State) so no view rebuild can dismiss the style popover.
    @Published public var isStylePickerPresented = false
    var appliedPaletteDark: Bool?

    init(zone: ZoneModel, frame: NSRect, fileService: FileManagerService) {
        self.zoneID = zone.id
        self.panel = ZonePanel(zone: zone, contentRect: frame)
        self.store = ZoneFileStore(fileService: fileService)
    }
}

public final class WindowManager: ObservableObject {
    public static let shared = WindowManager()

    private var controllers: [UUID: ZoneController] = [:]
    private var widgetPanels: [UUID: DesktopPanel] = [:]
    private var stickerPanels: [UUID: DesktopPanel] = [:]

    private var settingsWindow: NSWindow?
    private var paywallWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var searchWindow: KeyablePanel?
    private var hubWindow: NSWindow?
    private var aboutWindow: NSWindow?
    private var styleWindow: NSPanel?
    private var styleZoneID: UUID?

    private var cancellables = Set<AnyCancellable>()
    private var started = false
    private var state: AppState { AppState.shared }

    public init() {}

    /// The app that was frontmost before DesktopDüzen was activated (to hand focus back).
    private var previousApp: NSRunningApplication?
    private var outsideClickMonitor: Any?

    public func start() {
        guard !started else { return }
        started = true
        observeFocusHandBack()
        observeAppState()
        observeSystem()
        syncAllZones()
        syncAllWidgets()
        syncAllStickers()
    }

    public func controller(for id: UUID) -> ZoneController? { controllers[id] }

    // MARK: - Observation

    private func observeAppState() {
        state.$zones.receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.syncAllZones() }
            .store(in: &cancellables)
        state.$widgets.receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.syncAllWidgets() }
            .store(in: &cancellables)
        state.$stickers.receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.syncAllStickers() }
            .store(in: &cancellables)
        state.$areAllZonesHidden.removeDuplicates().receive(on: RunLoop.main)
            .sink { [weak self] hidden in self?.setAllZonesHidden(hidden) }
            .store(in: &cancellables)
        state.$settings.map(\.showZonesOnAllSpaces).removeDuplicates().receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshAllPanels() }
            .store(in: &cancellables)
        state.$settings.map(\.zonesTakeKeyboardFocus).removeDuplicates().receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.syncAllZones() }
            .store(in: &cancellables)
    }

    private func observeSystem() {
        let center = NotificationCenter.default
        center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            self?.refreshAllPanels()
        }
        let ws = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification,
                     NSWorkspace.sessionDidBecomeActiveNotification, NSWorkspace.activeSpaceDidChangeNotification] {
            ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                // Give WindowServer a moment to settle display configuration after wake.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self?.refreshAllPanels() }
            }
        }
    }

    /// Re-applies frames, levels and ordering; used after display, Space, sleep and login changes.
    public func refreshAllPanels() {
        syncAllZones(forceFrames: true)
        let allSpaces = state.settings.showZonesOnAllSpaces
        for panel in Array(widgetPanels.values) + Array(stickerPanels.values) {
            panel.applySpacesBehavior(allSpaces: allSpaces)
            panel.setFrame(displayFrame(for: panel.frame), display: true)
            if !state.areAllZonesHidden { panel.orderFront(nil) }
        }
    }

    // MARK: - Focus hand-back

    /// DesktopDüzen activates itself to show the Hub, Settings, About or a dialog. When the last of
    /// those windows closes it must give focus back; otherwise it stays the active app with no
    /// windows and silently swallows the user's keyboard shortcuts.
    private func observeFocusHandBack() {
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            if app.processIdentifier != ProcessInfo.processInfo.processIdentifier {
                self?.previousApp = app
                self?.dropDesktopKeyFocusSoon()
            }
        }
        // Zones and widgets are non-activating panels: a click into a sticky note or a rename field
        // makes them key while another app stays frontmost. They then keep receiving every keystroke
        // (Cmd-Shift-E and friends) even after the user clicks back into their editor, because that
        // click does not change the active app. A click anywhere outside DesktopDüzen drops it.
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            self?.dropDesktopKeyFocusSoon()
        }
        let nc = NotificationCenter.default
        for name in [NSWindow.willCloseNotification, NSWindow.didMiniaturizeNotification] {
            nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                guard let window = note.object as? NSWindow, !(window is DesktopPanel) else { return }
                // Let the window finish closing, then check what is left.
                DispatchQueue.main.async { self?.handFocusBackIfIdle(closing: window) }
            }
        }
    }

    /// Standard (non-desktop) windows the user can see.
    private func visibleAppWindows(excluding closing: NSWindow? = nil) -> [NSWindow] {
        NSApp.windows.filter { w in
            w !== closing && w.isVisible && !w.isMiniaturized && !(w is DesktopPanel)
                && w.level != DesktopPanel.desktopLevel && w.className != "NSStatusBarWindow"
                && !w.className.contains("Menu") && w.frame.width > 40
        }
    }

    private func dropDesktopKeyFocusSoon() {
        // Let the click land first; if DesktopDüzen became active from it, normal rules apply.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in self?.dropDesktopKeyFocus() }
    }

    /// Removes keyboard focus from any zone or widget panel while another app is frontmost.
    public func dropDesktopKeyFocus() {
        guard !NSApp.isActive else { return }
        for case let panel as DesktopPanel in NSApp.windows where panel.isKeyWindow {
            panel.makeFirstResponder(nil)
            // There is no public "resign key" call; re-ordering the panel hands key status back
            // to the window server without moving or hiding it for longer than one frame.
            let wasVisible = panel.isVisible
            panel.orderOut(nil)
            if wasVisible { panel.orderFrontRegardless() }
        }
    }

    public func handFocusBackIfIdle(closing: NSWindow? = nil) {
        guard NSApp.isActive, visibleAppWindows(excluding: closing).isEmpty, NSApp.modalWindow == nil else { return }
        if let app = previousApp, !app.isTerminated {
            app.activate(options: [])
        } else {
            NSApp.deactivate()
        }
    }

    // MARK: - Display placement

    /// Returns `frame` if enough of it (including the title strip) is on a connected display;
    /// otherwise a copy moved onto the main display. The stored layout is not modified, so a
    /// zone returns to its place when the external display comes back.
    public func displayFrame(for frame: NSRect) -> NSRect {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return frame }
        let titleStrip = NSRect(x: frame.minX + 20, y: frame.maxY - 30, width: max(1, frame.width - 40), height: 30)
        let titleVisible = screens.contains { $0.visibleFrame.intersects(titleStrip) }
        let visibleArea = screens.reduce(CGFloat(0)) { sum, screen in
            let i = screen.frame.intersection(frame)
            return sum + (i.isNull ? 0 : i.width * i.height)
        }
        if titleVisible && visibleArea >= frame.width * frame.height * 0.3 { return frame }

        let target = (NSScreen.main ?? screens[0]).visibleFrame
        var moved = frame
        moved.size.width = min(frame.width, target.width - 40)
        moved.size.height = min(frame.height, target.height - 40)
        moved.origin.x = min(max(frame.minX, target.minX + 20), target.maxX - moved.width - 20)
        moved.origin.y = min(max(frame.minY, target.minY + 20), target.maxY - moved.height - 20)
        return moved
    }

    // MARK: - Zones

    public func syncAllZones(forceFrames: Bool = false) {
        let zones = state.zones
        let ids = Set(zones.map { $0.id })

        if let styleID = styleZoneID, !ids.contains(styleID) {
            styleWindow?.orderOut(nil)
            styleZoneID = nil
        } else if let styleID = styleZoneID, let z = zones.first(where: { $0.id == styleID }) {
            styleWindow?.title = "Style – \(z.title)"
        }
        for (id, controller) in controllers where !ids.contains(id) {
            controller.store.stop()
            controller.panel.orderOut(nil)
            controller.panel.close()
            controllers.removeValue(forKey: id)
        }

        let allSpaces = state.settings.showZonesOnAllSpaces
        for zone in zones {
            let controller = controllers[zone.id] ?? createZoneController(for: zone)
            let panel = controller.panel
            panel.applyLevel(pinned: zone.isPinnedOnTop)
            panel.applySpacesBehavior(allSpaces: allSpaces)
            panel.applyKeyboardFocusPolicy(takesFocusOnClick: state.settings.zonesTakeKeyboardFocus)
            panel.minimumContentSize = NSSize(width: 220, height: zone.isCollapsed ? zone.collapsedHeight : 120)

            let palette = ZonePalette.forZone(zone)
            let wantsShadow = zone.showShadow && !palette.isClear
            if panel.hasShadow != wantsShadow {
                panel.hasShadow = wantsShadow
                panel.invalidateShadow()
            }
            if controller.appliedPaletteDark != palette.isDark {
                panel.appearance = palette.appearance
                controller.appliedPaletteDark = palette.isDark
            }

            if !controller.isHoverExpanded && !panel.inLiveResize {
                let target = displayFrame(for: zone.frame)
                if forceFrames || !panel.frame.equalTo(target) {
                    panel.setFrame(target, display: true)
                }
            }
            if zone.type == .app {
                controller.store.stop()
            } else {
                controller.store.watch(path: zone.resolvedFolderPath, manualOrder: zone.manualOrder)
            }
            if !state.areAllZonesHidden && !panel.isVisible { panel.orderFront(nil) }
        }
    }

    @discardableResult
    private func createZoneController(for zone: ZoneModel) -> ZoneController {
        let controller = ZoneController(zone: zone, frame: displayFrame(for: zone.frame), fileService: state.fileService)
        let panel = controller.panel
        let id = zone.id

        panel.onFrameCommitted = { [weak self] frame in
            self?.state.updateZoneFrame(id: id, frame: frame)
        }
        panel.onHoverChanged = { [weak self, weak controller] inside in
            guard let self = self, let controller = controller else { return }
            self.handleHover(inside: inside, controller: controller)
        }

        let root = ZoneContentView(zoneID: id)
            .environmentObject(state)
            .environmentObject(controller)
            .environmentObject(controller.store)
        panel.contentView = NSHostingView(rootView: root)
        panel.installHoverTracking()

        controllers[id] = controller
        if !state.areAllZonesHidden { panel.orderFront(nil) }
        return controller
    }

    private func handleHover(inside: Bool, controller: ZoneController) {
        if controller.isPointerInside != inside {
            if inside {
                controller.isPointerInside = true
            } else {
                // Exits caused by menus or the pointer sitting on the border are ignored.
                let mouse = NSEvent.mouseLocation
                if !controller.panel.frame.insetBy(dx: 1, dy: 1).contains(mouse) { controller.isPointerInside = false }
            }
        }
        guard let zone = state.zone(id: controller.zoneID), zone.isCollapsed,
              zone.autoExpandOnHover, state.canAutoExpand() else {
            if !inside && controller.isHoverExpanded { controller.isHoverExpanded = false }
            return
        }
        let panel = controller.panel
        let top = panel.frame.maxY
        if inside && !controller.isHoverExpanded {
            controller.isHoverExpanded = true
            let height = zone.expandedHeight
            let target = NSRect(x: panel.frame.minX, y: top - height, width: panel.frame.width, height: height)
            panel.setFrame(target, display: true, animate: true)
        } else if !inside && controller.isHoverExpanded {
            // Ignore exits caused by the mouse moving into a popover or menu owned by the panel.
            let mouse = NSEvent.mouseLocation
            if panel.frame.insetBy(dx: -2, dy: -2).contains(mouse) { return }
            controller.isHoverExpanded = false
            let target = NSRect(x: panel.frame.minX, y: top - zone.collapsedHeight, width: panel.frame.width, height: zone.collapsedHeight)
            panel.setFrame(target, display: true, animate: true)
        }
    }

    public func getOtherZoneFrames(excluding id: UUID) -> [NSRect] {
        controllers.filter { $0.key != id && $0.value.panel.isVisible }.map { $0.value.panel.frame }
    }

    public func snapFunction(for id: UUID) -> (NSRect, Bool) -> NSRect {
        return { [weak self] rect, includeGrid in
            guard let self = self else { return rect }
            return Snapping.snap(rect, otherFrames: self.getOtherZoneFrames(excluding: id),
                                 settings: self.state.settings, includeGrid: includeGrid)
        }
    }

    public func updatePanelFrame(id: UUID, newFrame: NSRect, animate: Bool = false) {
        controllers[id]?.panel.setFrame(displayFrame(for: newFrame), display: true, animate: animate)
    }

    /// Temporarily raises a zone above other windows so the user can find it.
    public func focusZone(id: UUID) {
        guard let controller = controllers[id], let zone = state.zone(id: id) else { return }
        if state.areAllZonesHidden { state.areAllZonesHidden = false }
        let panel = controller.panel
        panel.level = .floating
        panel.orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let current = self?.state.zone(id: id) else { return }
            panel.applyLevel(pinned: current.isPinnedOnTop)
            _ = zone
        }
    }

    public func setAllZonesHidden(_ hidden: Bool) {
        let panels: [NSWindow] = controllers.values.map { $0.panel } + Array(widgetPanels.values) + Array(stickerPanels.values)
        for panel in panels {
            if hidden { panel.orderOut(nil) } else { panel.orderFront(nil) }
        }
    }

    // MARK: - Widgets

    public func syncAllWidgets() {
        let widgets = state.widgets
        let ids = Set(widgets.map { $0.id })
        for (id, panel) in widgetPanels where !ids.contains(id) {
            panel.orderOut(nil)
            panel.close()
            widgetPanels.removeValue(forKey: id)
        }
        for widget in widgets {
            if widgetPanels[widget.id] == nil { createWidgetPanel(for: widget) }
            guard let panel = widgetPanels[widget.id] else { continue }
            let palette = ZonePalette.forWidget(widget)
            let appearance = palette.appearance
            if panel.appearance?.name != appearance?.name { panel.appearance = appearance }
            let wantsShadow = !palette.isClear
            if panel.hasShadow != wantsShadow {
                panel.hasShadow = wantsShadow
                panel.invalidateShadow()
            }
        }
    }

    private func createWidgetPanel(for widget: DesktopWidget) {
        let panel = DesktopPanel(contentRect: displayFrame(for: widget.frame), resizable: true)
        panel.minimumContentSize = NSSize(width: 160, height: 100)
        panel.appearance = ZonePalette.forWidget(widget).appearance
        panel.applySpacesBehavior(allSpaces: state.settings.showZonesOnAllSpaces)
        let id = widget.id
        panel.onFrameCommitted = { [weak self] frame in self?.commitWidgetFrame(id: id, frame: frame) }
        panel.contentView = NSHostingView(rootView: WidgetContainerView(widgetID: id).environmentObject(state))
        widgetPanels[id] = panel
        if !state.areAllZonesHidden { panel.orderFront(nil) }
    }

    /// Brings an existing widget into view: onto a visible display if needed, raised for a few seconds.
    public func focusWidget(id: UUID) {
        if state.areAllZonesHidden { state.areAllZonesHidden = false }
        guard let panel = widgetPanels[id] else { return }
        let onScreen = NSScreen.screens.contains { $0.visibleFrame.intersects(panel.frame.insetBy(dx: 20, dy: 20)) }
        if !onScreen, let screen = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame {
            let frame = NSRect(x: screen.midX - panel.frame.width / 2, y: screen.midY - panel.frame.height / 2,
                               width: panel.frame.width, height: panel.frame.height)
            panel.setFrame(frame, display: true)
            commitWidgetFrame(id: id, frame: frame)
        }
        panel.level = .floating
        panel.orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            panel.level = DesktopPanel.desktopLevel
        }
    }

    public func commitWidgetFrame(id: UUID, frame: NSRect) {
        if let idx = state.widgets.firstIndex(where: { $0.id == id }), state.widgets[idx].frame != frame.integral {
            state.widgets[idx].frame = frame.integral
        }
    }

    // MARK: - Stickers

    public func syncAllStickers() {
        let stickers = state.stickers
        let ids = Set(stickers.map { $0.id })
        for (id, panel) in stickerPanels where !ids.contains(id) {
            panel.orderOut(nil)
            panel.close()
            stickerPanels.removeValue(forKey: id)
        }
        for sticker in stickers where stickerPanels[sticker.id] == nil {
            createStickerPanel(for: sticker)
        }
    }

    private func createStickerPanel(for sticker: DesktopSticker) {
        let panel = DesktopPanel(contentRect: displayFrame(for: sticker.frame), resizable: false)
        panel.hasShadow = false
        panel.applySpacesBehavior(allSpaces: state.settings.showZonesOnAllSpaces)
        panel.contentView = NSHostingView(rootView: StickerView(stickerID: sticker.id).environmentObject(state))
        stickerPanels[sticker.id] = panel
        if !state.areAllZonesHidden { panel.orderFront(nil) }
    }

    public func commitStickerFrame(id: UUID, frame: NSRect) {
        if let idx = state.stickers.firstIndex(where: { $0.id == id }), state.stickers[idx].frame != frame.integral {
            state.stickers[idx].frame = frame.integral
        }
    }

    // MARK: - Standard windows

    private func makeWindow(title: String, size: NSSize, closable: Bool = true, resizable: Bool = false) -> NSWindow {
        var style: NSWindow.StyleMask = [.titled, .miniaturizable]
        if closable { style.insert(.closable) }
        if resizable { style.insert(.resizable) }
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: style, backing: .buffered, defer: false)
        window.title = title
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }

    private func present(_ window: NSWindow) {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    public func showHub() {
        if let window = hubWindow { present(window); return }
        let window = makeWindow(title: "DesktopDüzen Hub", size: NSSize(width: 700, height: 560), resizable: true)
        window.contentMinSize = NSSize(width: 620, height: 460)
        window.contentView = NSHostingView(rootView: HubView().environmentObject(state))
        window.setFrameAutosaveName("DesktopDuzenHub")
        hubWindow = window
        present(window)
    }

    public func closeHub() { hubWindow?.orderOut(nil); handFocusBackIfIdle() }

    /// Zone style settings in a solid, floating window (a popover attached to a desktop-level
    /// zone was translucent and could be covered by other zones).
    public func showStyleWindow(for zoneID: UUID) {
        guard let zone = state.zone(id: zoneID) else { return }
        let panel: NSPanel
        if let existing = styleWindow {
            panel = existing
        } else {
            panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 380, height: 680),
                            styleMask: [.titled, .closable, .resizable, .utilityWindow],
                            backing: .buffered, defer: false)
            panel.isFloatingPanel = true
            panel.level = .floating
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.becomesKeyOnlyIfNeeded = false
            panel.isOpaque = true
            panel.backgroundColor = .windowBackgroundColor
            panel.contentMinSize = NSSize(width: 360, height: 420)
            panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            styleWindow = panel
        }
        styleZoneID = zoneID
        panel.title = "Style – \(zone.title)"
        panel.contentView = NSHostingView(rootView:
            ScrollView { ZoneStylePickerView(zoneID: zoneID) }
                .background(Color(nsColor: .windowBackgroundColor))
                .environmentObject(state))

        // Place beside the zone, on the same display, fully on screen.
        let zoneFrame = controllers[zoneID]?.panel.frame ?? zone.frame
        let screen = NSScreen.screens.first(where: { $0.frame.intersects(zoneFrame) })?.visibleFrame
            ?? NSScreen.main?.visibleFrame ?? zoneFrame
        let size = panel.frame.size
        var x = zoneFrame.maxX + 12
        if x + size.width > screen.maxX { x = zoneFrame.minX - size.width - 12 }
        x = min(max(x, screen.minX + 8), screen.maxX - size.width - 8)
        var y = zoneFrame.maxY - size.height
        y = min(max(y, screen.minY + 8), screen.maxY - size.height - 8)
        panel.setFrameOrigin(NSPoint(x: x, y: y))
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    public func showAbout() {
        if let window = aboutWindow { present(window); return }
        let window = makeWindow(title: "About DesktopDüzen", size: NSSize(width: 480, height: 520))
        // A fixed width lets the wrapped text compute a real height (an unconstrained width
        // made fittingSize report thousands of points).
        let host = NSHostingView(rootView: AboutView().frame(width: 480).fixedSize())
        window.contentView = host
        let fitting = host.fittingSize
        window.setContentSize(NSSize(width: 480, height: min(max(fitting.height, 300), 700)))
        window.center()
        aboutWindow = window
        present(window)
    }

    public func showSettings() {
        if let window = settingsWindow { present(window); return }
        let window = makeWindow(title: "DesktopDüzen Preferences", size: NSSize(width: 720, height: 560), resizable: true)
        window.contentMinSize = NSSize(width: 660, height: 460)
        window.contentView = NSHostingView(rootView: SettingsView().environmentObject(state))
        settingsWindow = window
        present(window)
    }

    public func showPaywall() {
        if let window = paywallWindow { present(window); return }
        let window = makeWindow(title: "DesktopDüzen Pro", size: NSSize(width: 680, height: 600))
        window.contentView = NSHostingView(rootView: PaywallView().environmentObject(state))
        paywallWindow = window
        present(window)
    }

    public func closePaywall() { paywallWindow?.orderOut(nil); handFocusBackIfIdle() }

    public func showOnboarding() {
        if let window = onboardingWindow { present(window); return }
        let window = makeWindow(title: "Welcome to DesktopDüzen", size: NSSize(width: 560, height: 420))
        window.contentView = NSHostingView(rootView: OnboardingView().environmentObject(state))
        onboardingWindow = window
        present(window)
    }

    public func closeOnboarding() { onboardingWindow?.orderOut(nil); handFocusBackIfIdle() }

    public func toggleGlobalSearch() {
        if let search = searchWindow, search.isVisible {
            search.orderOut(nil)
            return
        }
        if searchWindow == nil {
            let panel = KeyablePanel(contentRect: NSRect(x: 0, y: 0, width: 560, height: 380),
                                     styleMask: [.borderless, .titled, .fullSizeContentView],
                                     backing: .buffered, defer: false)
            panel.titleVisibility = .hidden
            panel.titlebarAppearsTransparent = true
            panel.standardWindowButton(.closeButton)?.isHidden = true
            panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
            panel.standardWindowButton(.zoomButton)?.isHidden = true
            panel.isMovableByWindowBackground = true
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.level = .floating
            panel.hidesOnDeactivate = true
            panel.isReleasedWhenClosed = false
            panel.onCancel = { [weak panel] in panel?.orderOut(nil) }
            panel.contentView = NSHostingView(rootView: GlobalSearchView().environmentObject(state))
            searchWindow = panel
        }
        searchWindow?.center()
        NSApp.activate(ignoringOtherApps: true)
        searchWindow?.makeKeyAndOrderFront(nil)
    }

    public func closeSearch() { searchWindow?.orderOut(nil); handFocusBackIfIdle() }

    /// Releases every panel (used on termination so the state is flushed before windows vanish).
    public func tearDown() {
        for controller in controllers.values { controller.store.stop() }
        if let monitor = outsideClickMonitor { NSEvent.removeMonitor(monitor); outsideClickMonitor = nil }
    }
}
