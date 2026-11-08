import Combine
import Cocoa
import SwiftUI

public class AppDelegate: NSObject, NSApplicationDelegate {
    private var keyMonitor: Any?
    private var dockPolicyObserver: AnyCancellable?

    static func applyDockIconPolicy(_ show: Bool) {
        let policy: NSApplication.ActivationPolicy = show ? .regular : .accessory
        guard NSApp.activationPolicy() != policy else { return }
        NSApp.setActivationPolicy(policy)
        // Switching to .accessory can leave a visible Hub or Settings window behind other apps.
        if !show, NSApp.windows.contains(where: { $0.isVisible && !($0 is DesktopPanel) && $0.canBecomeKey && $0.frame.width > 40 }) {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        // Single instance: hand over to the copy that is already running.
        let bundleID = Bundle.main.bundleIdentifier ?? "com.desktopduzen.app"
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0 != NSRunningApplication.current && !$0.isTerminated }
        if let existing = others.first {
            existing.activate(options: [])
            NSApp.terminate(nil)
            return
        }

        installMainMenu()

        let state = AppState.shared
        // Info.plist marks the app as menu-bar only (LSUIElement), so no Dock icon flashes at launch.
        AppDelegate.applyDockIconPolicy(state.settings.showDockIcon)
        dockPolicyObserver = state.$settings.map(\.showDockIcon).removeDuplicates().dropFirst()
            .receive(on: RunLoop.main)
            .sink { AppDelegate.applyDockIconPolicy($0) }
        MenuBarManager.shared.setupMenuBar()
        WindowManager.shared.start()

        // Keep the stored preference consistent with what macOS actually has registered.
        let registered = LaunchAtLoginService.shared.isEnabled
        if state.settings.launchAtLogin != registered { state.settings.launchAtLogin = registered }

        ZoneActions.applyAutoSortMonitoring()

        if !state.settings.hasCompletedOnboarding {
            WindowManager.shared.showOnboarding()
        } else if state.settings.showHubOnLaunch || state.recoveredCorruptStateFile != nil {
            WindowManager.shared.showHub()
        }

        // Launching makes the app active; with no window to show, give focus straight back.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { WindowManager.shared.handFocusBackIfIdle() }

        // Cmd-Shift-Space opens search while DesktopDüzen is active.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if flags == [.command, .shift] && event.keyCode == 49 && AppState.shared.settings.globalHotkeyEnabled {
                WindowManager.shared.toggleGlobalSearch()
                return nil
            }
            return event
        }
    }

    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        WindowManager.shared.showHub()
        return true
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    public func applicationWillTerminate(_ notification: Notification) {
        // Flush immediately; the debounced autosave may not have fired yet.
        AppState.shared.saveState()
        AutoSortService.shared.stopMonitoring()
        WindowManager.shared.tearDown()
        if let monitor = keyMonitor { NSEvent.removeMonitor(monitor) }
    }

    /// Without a main menu, Cut/Copy/Paste/Undo and Select All do not reach text fields.
    private func installMainMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        let about = NSMenuItem(title: "About DesktopDüzen", action: #selector(openAbout), keyEquivalent: "")
        about.target = self
        appMenu.addItem(about)
        appMenu.addItem(.separator())
        let prefs = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        prefs.target = self
        appMenu.addItem(prefs)
        let hub = NSMenuItem(title: "Open Hub", action: #selector(openHub), keyEquivalent: "0")
        hub.target = self
        appMenu.addItem(hub)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide DesktopDüzen", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quit DesktopDüzen", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let fileItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        let newZone = NSMenuItem(title: "New File Zone…", action: #selector(newFileZone), keyEquivalent: "n")
        newZone.target = self
        fileMenu.addItem(newZone)
        let search = NSMenuItem(title: "Search Zones…", action: #selector(openSearch), keyEquivalent: "f")
        search.target = self
        fileMenu.addItem(search)
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        fileItem.submenu = fileMenu
        main.addItem(fileItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redo)
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        main.addItem(editItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowItem.submenu = windowMenu
        main.addItem(windowItem)
        NSApp.windowsMenu = windowMenu

        NSApp.mainMenu = main
    }

    @objc private func openSettings() { WindowManager.shared.showSettings() }
    @objc private func openAbout() { WindowManager.shared.showAbout() }
    @objc private func openHub() { WindowManager.shared.showHub() }
    @objc private func newFileZone() { ZoneActions.createFileZone() }
    @objc private func openSearch() { WindowManager.shared.toggleGlobalSearch() }
}
