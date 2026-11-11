import AppKit

/// Shared, confirmation-guarded actions used by the Hub, Settings, menu bar and zone menus,
/// so every entry point behaves the same and nothing destructive happens without a prompt.
public enum ZoneActions {
    private static var state: AppState { AppState.shared }

    private static func textPrompt(title: String, message: String, defaultValue: String, button: String) -> String? {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: button)
        alert.addButton(withTitle: "Cancel")
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        input.stringValue = defaultValue
        alert.accessoryView = input
        alert.window.initialFirstResponder = input
        defer { DispatchQueue.main.async { WindowManager.shared.handFocusBackIfIdle() } }
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let value = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? defaultValue : value
    }

    public static func info(_ title: String, _ message: String, style: NSAlert.Style = .informational) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = style
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
        DispatchQueue.main.async { WindowManager.shared.handFocusBackIfIdle() }
    }

    private static func ensureCanAdd() -> Bool {
        if state.canAddZone() { return true }
        WindowManager.shared.showPaywall()
        return false
    }

    public static func createFileZone() {
        guard ensureCanAdd(), let name = textPrompt(title: "New File Zone",
              message: "Files you drop into this zone are kept in ~/Desktop/Zones/<name>.",
              defaultValue: "New Zone", button: "Create") else { return }
        if state.createDefaultFileZone(title: name) == nil {
            info("Could Not Create Zone", "DesktopDüzen could not create a folder in ~/Desktop/Zones. Check that the Desktop is writable and that DesktopDüzen has Desktop access in System Settings > Privacy & Security > Files and Folders.", style: .warning)
        }
    }

    public static func createFolderZone() {
        guard ensureCanAdd() else { return }
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose Folder"
        panel.message = "Choose an existing folder to show as a zone. The folder stays where it is."
        if panel.runModal() == .OK, let url = panel.url {
            state.createFolderZone(title: url.lastPathComponent, folderURL: url)
        }
        DispatchQueue.main.async { WindowManager.shared.handFocusBackIfIdle() }
    }

    public static func createAppZone() {
        guard ensureCanAdd(), let name = textPrompt(title: "New App Zone", message: "Enter a name for the app launcher:",
                                                    defaultValue: "App Launcher", button: "Create") else { return }
        state.createAppZone(title: name)
    }

    public static func renameZone(id: UUID) {
        guard let zone = state.zone(id: id),
              let name = textPrompt(title: "Rename Zone", message: zone.type == .file ? "The zone folder in ~/Desktop/Zones is renamed too." : "Enter a new name:",
                                    defaultValue: zone.title, button: "Rename") else { return }
        state.renameZone(id: id, newTitle: name)
    }

    /// Asks what to do with the zone's files. Default (Return) is the non-destructive choice.
    public static func confirmDelete(id: UUID) {
        guard let zone = state.zone(id: id) else { return }
        defer { DispatchQueue.main.async { WindowManager.shared.handFocusBackIfIdle() } }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Remove the zone “\(zone.title)”?"
        switch zone.type {
        case .file:
            alert.informativeText = "Its folder is \(zone.backingFolderPath). Choose what happens to the files inside."
            alert.addButton(withTitle: "Keep Files in Folder")        // first = default
            alert.addButton(withTitle: "Move Files to Desktop")
            alert.addButton(withTitle: "Move Folder to Trash")
            alert.addButton(withTitle: "Cancel")
            switch alert.runModal() {
            case .alertFirstButtonReturn:
                state.deleteZone(id: id, action: .unbindOnly)
            case .alertSecondButtonReturn:
                let result = state.deleteZone(id: id, action: .moveFilesToDesktop)
                if !result.failedNames.isEmpty {
                    info("Some Files Were Not Moved", "These items stayed in \(zone.backingFolderPath):\n" + result.failedNames.prefix(10).joined(separator: "\n"), style: .warning)
                }
            case .alertThirdButtonReturn:
                state.deleteZone(id: id, action: .moveToTrash)
            default:
                break
            }
        case .folder:
            alert.informativeText = "The folder \(zone.backingFolderPath) and its files are not changed."
            alert.addButton(withTitle: "Remove Zone")
            alert.addButton(withTitle: "Cancel")
            if alert.runModal() == .alertFirstButtonReturn { state.deleteZone(id: id, action: .unbindOnly) }
        case .app:
            alert.informativeText = "Only the shortcuts are removed. The applications are not changed."
            alert.addButton(withTitle: "Remove Zone")
            alert.addButton(withTitle: "Cancel")
            if alert.runModal() == .alertFirstButtonReturn { state.deleteZone(id: id, action: .unbindOnly) }
        }
    }

    /// Explicit, previewed auto-sort. Offers to create missing target zones, then asks before moving.
    public static func runAutoSortInteractively() {
        guard state.isPro else { WindowManager.shared.showPaywall(); return }
        defer { DispatchQueue.main.async { WindowManager.shared.handFocusBackIfIdle() } }
        let service = AutoSortService.shared
        var plan = service.makePlan(rules: state.autoSortRules, zones: state.zones)

        if !plan.missingTargets.isEmpty {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "Create Missing Zones?"
            alert.informativeText = "\(plan.filesWaitingForMissingZones) Desktop file(s) match rules whose zone does not exist yet:\n• "
                + plan.missingTargets.joined(separator: "\n• ")
                + "\n\nCreate these File Zones so the files can be sorted?"
            alert.addButton(withTitle: "Create Zones")
            alert.addButton(withTitle: "Skip")
            if alert.runModal() == .alertFirstButtonReturn {
                for title in plan.missingTargets { state.createDefaultFileZone(title: title) }
                plan = service.makePlan(rules: state.autoSortRules, zones: state.zones)
            }
        }

        guard !plan.isEmpty else {
            info("Nothing to Sort", "No loose Desktop files match an enabled rule with an existing zone. Files changed in the last few seconds are skipped until they finish saving.")
            return
        }

        var summary: [String: Int] = [:]
        for move in plan.moves { summary[move.zoneTitle, default: 0] += 1 }
        let lines = summary.sorted { $0.key < $1.key }.map { "• \($0.value) → \($0.key)" }.joined(separator: "\n")
        NSApp.activate(ignoringOtherApps: true)
        let confirm = NSAlert()
        confirm.messageText = "Move \(plan.moves.count) Desktop file(s) into zones?"
        confirm.informativeText = lines + "\n\nFiles are moved, never overwritten. Name clashes get a number."
        confirm.addButton(withTitle: "Move Files")
        confirm.addButton(withTitle: "Cancel")
        guard confirm.runModal() == .alertFirstButtonReturn else { return }

        let result = service.execute(plan)
        var message = "Moved \(result.moved) file(s)."
        if !result.failed.isEmpty {
            message += "\n\nNot moved:\n" + result.failed.prefix(10).joined(separator: "\n")
        }
        info("Auto-Sort Complete", message)
    }

    public static func setContinuousAutoSort(_ enabled: Bool) {
        if enabled && !state.isPro { WindowManager.shared.showPaywall(); return }
        state.settings.autoSortEnabled = enabled
        applyAutoSortMonitoring()
    }

    public static func applyAutoSortMonitoring() {
        if state.settings.autoSortEnabled && state.isPro {
            AutoSortService.shared.startMonitoring { (AppState.shared.autoSortRules, AppState.shared.zones) }
        } else {
            AutoSortService.shared.stopMonitoring()
        }
    }

    public static func setDesktopIconsHidden(_ hidden: Bool) {
        if hidden {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "Hide Desktop Icons?"
            alert.informativeText = "Finder stops drawing icons on the Desktop (files are not moved or changed). Finder restarts briefly. Your zones stay visible."
            alert.addButton(withTitle: "Hide Icons")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        DesktopIconManager.shared.setDesktopIconsHidden(hidden)
        state.settings.hideLooseDesktopIcons = hidden
    }

    public static func addWidget(_ type: WidgetType) {
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = type.defaultSize
        let offset = CGFloat(state.widgets.count % 6) * 24
        let widget = DesktopWidget(type: type, title: type.displayName,
                                   frame: CGRect(x: screen.minX + 80 + offset, y: screen.minY + 120 + offset,
                                                 width: size.width, height: size.height))
        let result = state.addWidget(widget)
        if !result.added {
            // Already on the desktop: show the existing one instead of adding a duplicate.
            WindowManager.shared.focusWidget(id: result.id)
        }
    }

    public static func addSticker() {
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let emojis = ["🚀", "☕️", "⭐️", "🔥", "📌", "🎉", "💡", "🪴", "🐱", "🎯"]
        state.stickers.append(DesktopSticker(content: emojis.randomElement() ?? "⭐️",
                                             frame: CGRect(x: screen.midX - 40, y: screen.midY - 40, width: 80, height: 80)))
    }

    // MARK: - Desktop Item Pinning Actions

    public static func pinDesktopItem() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Pin Here"
        panel.message = "Select desktop items to permanently lock at their current desktop positions:"
        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Desktop")
        panel.directoryURL = desktop

        defer { DispatchQueue.main.async { WindowManager.shared.handFocusBackIfIdle() } }

        if panel.runModal() == .OK {
            var pinnedCount = 0
            for url in panel.urls {
                if DesktopPinService.shared.pinItem(at: url) != nil {
                    pinnedCount += 1
                }
            }
            if pinnedCount > 0 {
                info("Desktop Items Pinned", "\(pinnedCount) item(s) permanently locked to their desktop position.")
            }
        }
    }

    public static func unpinDesktopItem(id: UUID) {
        DesktopPinService.shared.unpinItem(id: id)
    }

    public static func restorePinnedPositions() {
        DesktopPinService.shared.enforcePositions()
    }
}
