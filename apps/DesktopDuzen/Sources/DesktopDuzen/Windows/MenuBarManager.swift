import Foundation
import AppKit

public class MenuBarManager: NSObject, NSMenuDelegate {
    public static let shared = MenuBarManager()
    
    private var statusItem: NSStatusItem?
    
    public func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            // Use custom icon or SF Symbol
            let image = NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: "DesktopDüzen")
            image?.isTemplate = true
            button.image = image
            button.toolTip = "DesktopDüzen"
        }
        
        rebuildMenu()
    }
    
    // Rebuild every time the menu opens so titles and check marks always reflect current state.
    public func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === statusItem?.menu else { return }
        populate(menu)
    }
    
    public func rebuildMenu() {
        let menu = statusItem?.menu ?? NSMenu()
        menu.delegate = self
        populate(menu)
        statusItem?.menu = menu
    }
    
    private func populate(_ menu: NSMenu) {
        menu.removeAllItems()
        
        // Header info
        let titleItem = NSMenuItem(title: "DesktopDüzen", action: nil, keyEquivalent: "")
        titleItem.attributedTitle = NSAttributedString(
            string: "DesktopDüzen",
            attributes: [.font: NSFont.boldSystemFont(ofSize: 13)]
        )
        menu.addItem(titleItem)
        
        let proStatus = AppState.shared.isPro ? "★ Pro Active" : "Free Tier"
        let statusSubItem = NSMenuItem(title: "  \(proStatus)", action: #selector(openPaywall), keyEquivalent: "")
        statusSubItem.target = self
        menu.addItem(statusSubItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let hubItem = NSMenuItem(title: "Open DesktopDüzen Hub...", action: #selector(openHub), keyEquivalent: "o")
        hubItem.target = self
        hubItem.image = NSImage(systemSymbolName: "macwindow.on.rectangle", accessibilityDescription: nil)
        menu.addItem(hubItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Zone creation actions
        let newFileZoneItem = NSMenuItem(title: "New File Zone...", action: #selector(newFileZone), keyEquivalent: "n")
        newFileZoneItem.target = self
        newFileZoneItem.image = NSImage(systemSymbolName: "folder.badge.plus", accessibilityDescription: nil)
        menu.addItem(newFileZoneItem)
        
        let newFolderZoneItem = NSMenuItem(title: "New Folder Zone (Quick Access)...", action: #selector(newFolderZone), keyEquivalent: "f")
        newFolderZoneItem.target = self
        newFolderZoneItem.image = NSImage(systemSymbolName: "arrow.up.right.square", accessibilityDescription: nil)
        menu.addItem(newFolderZoneItem)
        
        let newAppZoneItem = NSMenuItem(title: "New App Zone...", action: #selector(newAppZone), keyEquivalent: "a")
        newAppZoneItem.target = self
        newAppZoneItem.image = NSImage(systemSymbolName: "square.grid.2x2.fill", accessibilityDescription: nil)
        menu.addItem(newAppZoneItem)
        
        // Widgets & Stickers submenu
        let widgetsMenu = NSMenu()
        for widgetType in WidgetType.allCases {
            let item = NSMenuItem(title: "Add \(widgetType.displayName)", action: #selector(addWidget(_:)), keyEquivalent: "")
            item.representedObject = widgetType
            item.target = self
            item.image = NSImage(systemSymbolName: widgetType.iconName, accessibilityDescription: nil)
            widgetsMenu.addItem(item)
        }
        widgetsMenu.addItem(NSMenuItem.separator())
        let addStickerItem = NSMenuItem(title: "Add Desktop Sticker...", action: #selector(addSticker), keyEquivalent: "")
        addStickerItem.target = self
        addStickerItem.image = NSImage(systemSymbolName: "star.fill", accessibilityDescription: nil)
        widgetsMenu.addItem(addStickerItem)
        
        let widgetsParentItem = NSMenuItem(title: "Widgets & Stickers", action: nil, keyEquivalent: "")
        widgetsParentItem.submenu = widgetsMenu
        widgetsParentItem.image = NSImage(systemSymbolName: "wand.and.stars", accessibilityDescription: nil)
        menu.addItem(widgetsParentItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Layout and View actions
        let alignItem = NSMenuItem(title: "Auto-Align All Zones", action: #selector(autoAlignAll), keyEquivalent: "l")
        alignItem.target = self
        alignItem.image = NSImage(systemSymbolName: "rectangle.3.group", accessibilityDescription: nil)
        menu.addItem(alignItem)
        
        let gridItem = NSMenuItem(title: "Align All Zones to Grid", action: #selector(alignToGrid), keyEquivalent: "g")
        gridItem.target = self
        gridItem.image = NSImage(systemSymbolName: "grid", accessibilityDescription: nil)
        menu.addItem(gridItem)
        
        let snapState = "Snap Zones While Dragging"
        let snapItem = NSMenuItem(title: snapState, action: #selector(toggleGridSnapping), keyEquivalent: "")
        snapItem.target = self
        snapItem.state = AppState.shared.settings.alignmentMode ? .on : .off
        menu.addItem(snapItem)
        
        let hoverTitles = NSMenuItem(title: "Hide Title Bars Until Hover", action: #selector(toggleHoverTitles), keyEquivalent: "")
        hoverTitles.target = self
        hoverTitles.state = AppState.shared.settings.hideTitleBarsUntilHover ? .on : .off
        menu.addItem(hoverTitles)

        let dockItem = NSMenuItem(title: "Show in Dock", action: #selector(toggleDockIcon), keyEquivalent: "")
        dockItem.target = self
        dockItem.state = AppState.shared.settings.showDockIcon ? .on : .off
        menu.addItem(dockItem)
        
        let hideZonesTitle = AppState.shared.areAllZonesHidden ? "Show All Zones" : "Hide All Zones"
        let hideZonesItem = NSMenuItem(title: hideZonesTitle, action: #selector(toggleHideAllZones), keyEquivalent: "h")
        hideZonesItem.target = self
        menu.addItem(hideZonesItem)
        
        let hideDesktopTitle = "Hide Finder Desktop Icons"
        let hideDesktopItem = NSMenuItem(title: hideDesktopTitle, action: #selector(toggleDesktopIcons), keyEquivalent: "")
        hideDesktopItem.target = self
        hideDesktopItem.state = AppState.shared.settings.hideLooseDesktopIcons ? .on : .off
        menu.addItem(hideDesktopItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Smart Auto Sort
        let autoSortMenu = NSMenu()
        let runSortNow = NSMenuItem(title: "Run Auto-Sort Now…", action: #selector(runAutoSortNow), keyEquivalent: "s")
        runSortNow.target = self
        runSortNow.image = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: nil)
        autoSortMenu.addItem(runSortNow)
        
        let autoSortToggle = NSMenuItem(title: "Sort New Desktop Files Automatically", action: #selector(toggleAutoSort), keyEquivalent: "")
        autoSortToggle.target = self
        autoSortToggle.state = AppState.shared.settings.autoSortEnabled ? .on : .off
        autoSortMenu.addItem(autoSortToggle)
        
        let autoSortParent = NSMenuItem(title: "Smart Auto-Sort Rules", action: nil, keyEquivalent: "")
        autoSortParent.submenu = autoSortMenu
        autoSortParent.image = NSImage(systemSymbolName: "tray.full.fill", accessibilityDescription: nil)
        menu.addItem(autoSortParent)
        
        // Search
        let searchItem = NSMenuItem(title: "Search Across All Zones...", action: #selector(openSearch), keyEquivalent: " ")
        searchItem.keyEquivalentModifierMask = [.command, .shift]
        searchItem.target = self
        searchItem.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)
        menu.addItem(searchItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Settings / Preferences
        let settingsItem = NSMenuItem(title: "Preferences...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        settingsItem.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
        menu.addItem(settingsItem)
        
        let paywallItem = NSMenuItem(title: AppState.shared.isPro ? "Pro License Details..." : "Upgrade to Pro...", action: #selector(openPaywall), keyEquivalent: "")
        paywallItem.target = self
        paywallItem.image = NSImage(systemSymbolName: "crown.fill", accessibilityDescription: nil)
        menu.addItem(paywallItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let aboutItem = NSMenuItem(title: "About DesktopDüzen", action: #selector(openAbout), keyEquivalent: "")
        aboutItem.target = self
        aboutItem.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: nil)
        menu.addItem(aboutItem)
        
        let quitItem = NSMenuItem(title: "Quit DesktopDüzen", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }
    
    // MARK: - Actions
    
    @objc private func openHub() {
        NSApp.activate(ignoringOtherApps: true)
        WindowManager.shared.showHub()
    }
    
    @objc private func newFileZone() { ZoneActions.createFileZone() }
    
    @objc private func newFolderZone() { ZoneActions.createFolderZone() }
    
    @objc private func newAppZone() { ZoneActions.createAppZone() }
    
    @objc private func addWidget(_ sender: NSMenuItem) {
        guard let widgetType = sender.representedObject as? WidgetType else { return }
        ZoneActions.addWidget(widgetType)
    }
    
    @objc private func addSticker() { ZoneActions.addSticker() }
    
    @objc private func toggleHoverTitles() { AppState.shared.settings.hideTitleBarsUntilHover.toggle() }

    @objc private func toggleDockIcon() { AppState.shared.settings.showDockIcon.toggle() }
    
    @objc private func alignToGrid() { AppState.shared.alignAllZonesToGrid() }
    
    @objc private func autoAlignAll() {
        AppState.shared.autoAlignAllZones()
    }
    
    @objc private func toggleGridSnapping() {
        AppState.shared.settings.alignmentMode.toggle()
    }
    
    @objc private func toggleHideAllZones() {
        AppState.shared.areAllZonesHidden.toggle()
    }
    
    @objc private func toggleDesktopIcons() {
        ZoneActions.setDesktopIconsHidden(!AppState.shared.settings.hideLooseDesktopIcons)
    }
    
    @objc private func runAutoSortNow() { ZoneActions.runAutoSortInteractively() }
    
    @objc private func toggleAutoSort() {
        ZoneActions.setContinuousAutoSort(!AppState.shared.settings.autoSortEnabled)
    }
    
    @objc private func openSearch() {
        NSApp.activate(ignoringOtherApps: true)
        WindowManager.shared.toggleGlobalSearch()
    }
    
    @objc private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        WindowManager.shared.showSettings()
    }
    
    @objc private func openPaywall() {
        NSApp.activate(ignoringOtherApps: true)
        WindowManager.shared.showPaywall()
    }
    
    @objc private func openAbout() { WindowManager.shared.showAbout() }
    
    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
