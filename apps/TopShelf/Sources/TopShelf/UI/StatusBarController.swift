import AppKit
import Combine
import SwiftUI

private final class StatusItemDropOverlayView: NSView {
    var targetFolderURL: URL?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Pass clicks through to NSStatusBarButton; AppKit still delivers drags to registered views
        return nil
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard targetFolderURL != nil else { return [] }
        return .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let destDir = targetFolderURL else { return false }
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true
        ]) as? [URL], !urls.isEmpty else {
            return false
        }

        let fm = FileManager.default
        var copiedAny = false
        for srcURL in urls {
            guard srcURL.deletingLastPathComponent().standardizedFileURL != destDir.standardizedFileURL else {
                continue
            }
            var destURL = destDir.appendingPathComponent(srcURL.lastPathComponent)
            var counter = 2
            while fm.fileExists(atPath: destURL.path) {
                let base = srcURL.deletingPathExtension().lastPathComponent
                let ext = srcURL.pathExtension
                let newName = ext.isEmpty ? "\(base) \(counter)" : "\(base) \(counter).\(ext)"
                destURL = destDir.appendingPathComponent(newName)
                counter += 1
            }
            if (try? fm.copyItem(at: srcURL, to: destURL)) != nil {
                copiedAny = true
            }
        }
        return copiedAny
    }
}

@MainActor
final class StatusBarController: NSObject, FolderMenuPanelDelegate {
    private var statusItems: [UUID: NSStatusItem] = [:]
    private var orderedIDs: [UUID] = []
    private var fallbackStatusItem: NSStatusItem?

    private var activePanel: FolderMenuPanel?
    private var activeFolderID: UUID?
    private var isDragging = false

    private var globalClickMonitor: Any?
    private var localClickMonitor: Any?
    private var cancellables = Set<AnyCancellable>()

    private var settingsWindowController: SettingsWindowController?

    override init() {
        super.init()
        bindStore()
        rebuildStatusItems()
    }

    private func bindStore() {
        AppStore.shared.$pinnedFolders
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.rebuildStatusItems()
            }
            .store(in: &cancellables)
    }

    private func rebuildStatusItems() {
        dismissActivePanel()

        // Remove all existing items to preserve exact user-defined ordering
        for item in statusItems.values {
            NSStatusBar.system.removeStatusItem(item)
        }
        statusItems.removeAll()
        orderedIDs.removeAll()

        if let fallback = fallbackStatusItem {
            NSStatusBar.system.removeStatusItem(fallback)
            fallbackStatusItem = nil
        }

        let folders = AppStore.shared.pinnedFolders
        if folders.isEmpty {
            createFallbackStatusItem()
            return
        }

        // Insert in reverse so left-to-right menu bar order matches the list order
        for folder in folders.reversed() {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            configure(statusItem: item, for: folder)
            statusItems[folder.id] = item
            orderedIDs.append(folder.id)
        }
    }

    private func createFallbackStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            let cfg = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
            let img = NSImage(systemSymbolName: "folder.badge.plus", accessibilityDescription: "TopShelf")?
                .withSymbolConfiguration(cfg)
            img?.isTemplate = true
            button.image = img
            button.toolTip = "TopShelf — Click to pin folders"
            button.target = self
            button.action = #selector(fallbackClicked)
        }
        fallbackStatusItem = item
    }

    private func configure(statusItem: NSStatusItem, for folder: PinnedFolder) {
        guard let button = statusItem.button else { return }

        let cfg = NSImage.SymbolConfiguration(pointSize: 14.5, weight: .medium)
        var image = NSImage(systemSymbolName: folder.symbolName, accessibilityDescription: folder.displayName)?
            .withSymbolConfiguration(cfg)

        if let tintColor = folder.colorOption.nsColor, let base = image {
            image = tintedImage(base, color: tintColor)
            image?.isTemplate = false
        } else {
            image?.isTemplate = true
        }

        button.image = image
        button.imagePosition = folder.showTitleInMenuBar ? .imageLeading : .imageOnly
        button.title = folder.showTitleInMenuBar ? " \(folder.displayName)" : ""
        button.toolTip = "\(folder.displayName)\n\(folder.path)"
        button.target = self
        button.action = #selector(statusItemClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.identifier = NSUserInterfaceItemIdentifier(folder.id.uuidString)

        // Attach drag-and-drop overlay so files can be dropped directly onto the menu bar icon
        button.subviews.filter { $0 is StatusItemDropOverlayView }.forEach { $0.removeFromSuperview() }
        let overlay = StatusItemDropOverlayView(frame: button.bounds)
        overlay.autoresizingMask = [.width, .height]
        overlay.targetFolderURL = folder.url
        button.addSubview(overlay)
    }

    private func tintedImage(_ image: NSImage, color: NSColor) -> NSImage {
        let newImage = NSImage(size: image.size, flipped: false) { rect in
            image.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        newImage.isTemplate = false
        return newImage
    }

    @objc private func fallbackClicked() {
        openSettings(selectedFolderID: nil)
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        guard let idString = sender.identifier?.rawValue,
              let id = UUID(uuidString: idString),
              let folder = AppStore.shared.pinnedFolders.first(where: { $0.id == id }) else {
            return
        }

        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp {
            dismissActivePanel()
            showContextMenu(for: folder, statusItemButton: sender)
            return
        }

        if activeFolderID == id, activePanel != nil {
            dismissActivePanel()
            return
        }

        dismissActivePanel()
        openPanel(for: folder, from: sender)
    }

    private func openPanel(for folder: PinnedFolder, from button: NSStatusBarButton) {
        guard let buttonWindow = button.window else { return }
        let anchorRect = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))

        let panel = FolderMenuPanel(
            directoryURL: folder.url,
            pinnedFolder: folder,
            isRoot: true,
            menuDelegate: self
        )
        panel.position(below: anchorRect)
        panel.makeKeyAndOrderFront(nil)

        activePanel = panel
        activeFolderID = folder.id
        startClickMonitors()
    }

    private func showContextMenu(for folder: PinnedFolder, statusItemButton: NSStatusBarButton) {
        let menu = NSMenu()

        let openFinder = NSMenuItem(title: "Open \"\(folder.displayName)\" in Finder", action: #selector(contextOpenInFinder(_:)), keyEquivalent: "")
        openFinder.target = self
        openFinder.representedObject = folder.url
        menu.addItem(openFinder)

        let pinAnother = NSMenuItem(title: "Pin Another Folder…", action: #selector(contextPinFolder), keyEquivalent: "")
        pinAnother.target = self
        menu.addItem(pinAnother)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(contextOpenSettings(_:)), keyEquivalent: ",")
        settingsItem.target = self
        settingsItem.representedObject = folder.id
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit TopShelf", action: #selector(contextQuit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: statusItemButton.bounds.height + 4), in: statusItemButton)
    }

    @objc private func contextOpenInFinder(_ sender: NSMenuItem) {
        if let url = sender.representedObject as? URL {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func contextPinFolder() {
        AppStore.shared.pickAndAddFolder()
    }

    @objc private func contextOpenSettings(_ sender: NSMenuItem) {
        openSettings(selectedFolderID: sender.representedObject as? UUID)
    }

    @objc private func contextQuit() {
        NSApp.terminate(nil)
    }

    func dismissActivePanel() {
        stopClickMonitors()
        PreviewPanelController.shared.hide()
        activePanel?.closeHierarchy()
        activePanel = nil
        activeFolderID = nil
        isDragging = false
    }

    func openSettings(selectedFolderID: UUID?) {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController()
        }
        settingsWindowController?.show(selectedFolderID: selectedFolderID)
    }

    private func startClickMonitors() {
        stopClickMonitors()

        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, !self.isDragging else { return }
                self.dismissActivePanel()
            }
        }

        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, let panel = self.activePanel, !self.isDragging else {
                return event
            }
            let mouseLoc = NSEvent.mouseLocation
            if panel.containsScreenPoint(mouseLoc) {
                return event
            }
            // Allow status bar button click to toggle naturally
            for item in self.statusItems.values {
                if let btn = item.button, let win = btn.window {
                    let rect = win.convertToScreen(btn.convert(btn.bounds, to: nil))
                    if rect.contains(mouseLoc) {
                        return event
                    }
                }
            }
            self.dismissActivePanel()
            return event
        }
    }

    private func stopClickMonitors() {
        if let globalClickMonitor {
            NSEvent.removeMonitor(globalClickMonitor)
            self.globalClickMonitor = nil
        }
        if let localClickMonitor {
            NSEvent.removeMonitor(localClickMonitor)
            self.localClickMonitor = nil
        }
    }

    // MARK: - FolderMenuPanelDelegate

    func folderPanelDidRequestDismissAll() {
        dismissActivePanel()
    }

    func folderPanelDidRequestSettings(selectedFolderID: UUID?) {
        openSettings(selectedFolderID: selectedFolderID)
    }

    func folderPanelDidChangeDraggingState(_ isDragging: Bool) {
        self.isDragging = isDragging
        if !isDragging {
            // Dismiss smoothly after a drop completes outside the panel
            let loc = NSEvent.mouseLocation
            if let panel = activePanel, !panel.containsScreenPoint(loc) {
                dismissActivePanel()
            }
        }
    }
}
