import SwiftUI
import AppKit

public struct ZoneHeaderView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var controller: ZoneController
    @Environment(\.zonePalette) private var palette
    let zone: ZoneModel

    @State private var isEditingTitle = false
    @State private var editedTitle = ""
    @FocusState private var titleFieldFocused: Bool

    public init(zone: ZoneModel) {
        self.zone = zone
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: zone.type.iconName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(palette.accent)
                    .allowsHitTesting(false)

                if isEditingTitle {
                    TextField("Zone Name", text: $editedTitle)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(palette.primary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(palette.controlFillStrong)
                        .cornerRadius(4)
                        .focused($titleFieldFocused)
                        .onSubmit(commitRename)
                        .onExitCommand {
                            isEditingTitle = false
                            controller.panel.makeFirstResponder(nil)
                            WindowManager.shared.dropDesktopKeyFocus()
                        }
                        .onAppear { titleFieldFocused = true }
                } else {
                    // Full title when it fits, otherwise initials ("Quick Launcher" -> "QL"),
                    // otherwise a truncated title. Hovering shows the full name.
                    ViewThatFits(in: .horizontal) {
                        titleText(zone.title).fixedSize()
                        if let initials = ZoneTitle.initials(zone.title) {
                            titleText(initials).fixedSize()
                        }
                        titleText(zone.title).truncationMode(.tail)
                    }
                    .allowsHitTesting(false)
                    .accessibilityLabel(zone.title)
                }

                Spacer(minLength: 4)

                HStack(spacing: 4) {
                    headerButton(zone.isPinnedOnTop ? "pin.fill" : "pin",
                                 help: zone.isPinnedOnTop ? "Unpin (return to desktop level)" : "Keep above other windows",
                                 highlighted: zone.isPinnedOnTop, action: togglePinOnTop)

                    headerButton(zone.isCollapsed ? "chevron.down" : "chevron.up",
                                 help: zone.isCollapsed ? "Expand zone" : "Collapse to title bar", action: toggleCollapse)

                    Menu {
                        menuContent
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(palette.primary)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .padding(4)
                    .background(palette.controlFill)
                    .clipShape(Circle())
                    .help("More options")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(height: zone.collapsedHeight)
            .help(zone.title)
            .background(
                WindowDragArea(
                    snap: WindowManager.shared.snapFunction(for: zone.id),
                    onDragEnded: { frame in appState.updateZoneFrame(id: zone.id, frame: frame) },
                    onDoubleClick: beginRename
                )
            )

            if !zone.tabs.isEmpty && !zone.isCollapsed {
                tabStrip
            }
        }
    }

    private func titleText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .bold))
            .foregroundColor(palette.title)
            .lineLimit(1)
    }

    private func headerButton(_ symbol: String, help: String, highlighted: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(highlighted ? palette.accent : palette.primary)
                .frame(width: 20, height: 20)
                .background(highlighted ? palette.controlFillStrong : palette.controlFill)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    @ViewBuilder
    private var menuContent: some View {
        Button("Style & Theme…") {
            WindowManager.shared.showStyleWindow(for: zone.id)
        }
        Divider()
        if zone.type != .app {
            Picker("View", selection: Binding(get: { zone.viewMode }, set: { mode in appState.mutateZone(id: zone.id) { $0.viewMode = mode } })) {
                Label("Icons", systemImage: "square.grid.3x3").tag(ZoneViewMode.icon)
                Label("List", systemImage: "list.bullet").tag(ZoneViewMode.list)
            }
            Picker("Sort By", selection: Binding(get: { zone.sortMode }, set: { mode in appState.mutateZone(id: zone.id) { $0.sortMode = mode } })) {
                ForEach(ZoneSortMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            Menu("Text Size") {
                ForEach([8.0, 9.0, 10.0, 11.0, 11.5, 12.0, 13.0, 14.0], id: \.self) { size in
                    Button {
                        appState.mutateZone(id: zone.id) { $0.fontSize = size }
                    } label: {
                        let label = size == 11.5 ? "11.5 pt (default)" : "\(Int(size)) pt"
                        if abs(zone.fontSize - size) < 0.01 { Label(label, systemImage: "checkmark") } else { Text(label) }
                    }
                }
                Divider()
                Button("Use \(zone.fontSize == zone.fontSize.rounded() ? String(Int(zone.fontSize)) : String(zone.fontSize)) pt in All Zones") {
                    let size = zone.fontSize
                    var updated = appState.zones
                    for i in updated.indices { updated[i].fontSize = size }
                    appState.zones = updated
                }
            }
            Menu("Icon Size") {
                ForEach([32.0, 40.0, 48.0, 52.0, 64.0, 76.0], id: \.self) { size in
                    Button {
                        appState.mutateZone(id: zone.id) { $0.iconSize = size }
                    } label: {
                        let label = size == 52 ? "\(Int(size)) px (default)" : "\(Int(size)) px"
                        if abs(zone.iconSize - size) < 0.01 { Label(label, systemImage: "checkmark") } else { Text(label) }
                    }
                }
            }
            Divider()
            Button("Add Tab…", action: addNewTab)
            Button("Reveal in Finder", action: revealInFinder)
            Divider()
        }
        if (zone.customBackgroundOpacity ?? 1) < ZoneModel.clearModeThreshold {
            Button("Restore Background") {
                appState.mutateZone(id: zone.id) {
                    $0.customBackgroundOpacity = nil
                    $0.showBorder = true
                    $0.showShadow = true
                }
            }
        } else {
            Button("Make Fully Transparent") {
                appState.mutateZone(id: zone.id) {
                    $0.customBackgroundOpacity = 0
                    $0.showBorder = false
                    $0.showShadow = false
                }
            }
        }
        Divider()
        Button("Align All Zones to Grid") { appState.alignAllZonesToGrid() }
        Button("Auto-Align All Zones") { appState.autoAlignAllZones() }
        Divider()
        Button("Rename Zone…", action: beginRename)
        Button("Delete Zone…") { ZoneActions.confirmDelete(id: zone.id) }
    }

    private var tabStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(zone.tabs) { tab in
                    let isSelected = zone.activeTabID == tab.id
                    Button { selectTab(tab.id) } label: {
                        Text(tab.title)
                            .font(.system(size: 11, weight: isSelected ? .bold : .regular))
                            .foregroundColor(isSelected ? palette.primary : palette.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(isSelected ? palette.controlFillStrong : palette.controlFill)
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Rename Tab…") { renameTab(tab) }
                        Button("Remove Tab…") { deleteTab(tab) }
                    }
                }
                headerButton("plus", help: "Add tab", action: addNewTab)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 6)
        }
    }

    // MARK: - Handlers

    private func beginRename() {
        editedTitle = zone.title
        isEditingTitle = true
        controller.panel.makeKey()
    }

    private func commitRename() {
        let trimmed = editedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty && trimmed != zone.title {
            appState.renameZone(id: zone.id, newTitle: trimmed)
        }
        isEditingTitle = false
        controller.panel.makeFirstResponder(nil)
        WindowManager.shared.dropDesktopKeyFocus()
    }

    private func togglePinOnTop() {
        if !appState.canPinOnTop() && !zone.isPinnedOnTop {
            WindowManager.shared.showPaywall()
            return
        }
        appState.mutateZone(id: zone.id) { $0.isPinnedOnTop.toggle() }
    }

    private func toggleCollapse() {
        let panelFrame = controller.panel.frame
        let top = panelFrame.maxY
        controller.isHoverExpanded = false
        appState.mutateZone(id: zone.id) { z in
            if z.isCollapsed {
                let height = max(120, z.expandedHeight)
                z.isCollapsed = false
                z.frame = CGRect(x: panelFrame.minX, y: top - height, width: panelFrame.width, height: height).integral
            } else {
                z.expandedHeight = max(120, panelFrame.height)
                z.isCollapsed = true
                z.frame = CGRect(x: panelFrame.minX, y: top - z.collapsedHeight, width: panelFrame.width, height: z.collapsedHeight).integral
            }
        }
    }

    private func revealInFinder() {
        let path = zone.resolvedFolderPath
        if FileManager.default.fileExists(atPath: path) {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        }
    }

    private func addNewTab() {
        if !appState.canUseTabs() {
            WindowManager.shared.showPaywall()
            return
        }
        let alert = NSAlert()
        alert.messageText = "New Tab"
        alert.informativeText = "Each tab is a subfolder of \(zone.backingFolderPath)."
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        input.stringValue = zone.tabs.isEmpty ? "All Files" : "Tab \(zone.tabs.count + 1)"
        alert.accessoryView = input
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = appState.fileService.sanitizeFolderName(input.stringValue)
        let subfolder = URL(fileURLWithPath: zone.backingFolderPath).appendingPathComponent(name, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: subfolder, withIntermediateDirectories: true)
        } catch {
            ZoneActions.info("Could Not Add Tab", error.localizedDescription, style: .warning)
            return
        }
        let tab = ZoneTab(title: name, subfolderName: name, order: zone.tabs.count)
        appState.mutateZone(id: zone.id) { z in
            z.tabs.append(tab)
            z.activeTabID = tab.id
        }
    }

    private func selectTab(_ id: UUID) {
        appState.mutateZone(id: zone.id) { $0.activeTabID = id }
    }

    private func renameTab(_ tab: ZoneTab) {
        let alert = NSAlert()
        alert.messageText = "Rename Tab"
        alert.informativeText = "The tab's subfolder keeps its name on disk."
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        input.stringValue = tab.title
        alert.accessoryView = input
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let newName = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty else { return }
        appState.mutateZone(id: zone.id) { z in
            if let idx = z.tabs.firstIndex(where: { $0.id == tab.id }) { z.tabs[idx].title = newName }
        }
    }

    private func deleteTab(_ tab: ZoneTab) {
        let alert = NSAlert()
        alert.messageText = "Remove the tab “\(tab.title)”?"
        alert.informativeText = "The subfolder and its files stay on disk in \(zone.backingFolderPath)."
        alert.addButton(withTitle: "Remove Tab")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        appState.mutateZone(id: zone.id) { z in
            z.tabs.removeAll { $0.id == tab.id }
            if z.activeTabID == tab.id { z.activeTabID = z.tabs.first?.id }
        }
    }
}


/// Title helpers for narrow zones.
public enum ZoneTitle {
    /// Initials of a multi-word title, e.g. "Quick Launcher" -> "QL", "Downloads & Media" -> "DM",
    /// "my work 2026" -> "MW2". Returns nil for single words (initials would not be meaningful).
    public static func initials(_ title: String, maxLetters: Int = 4) -> String? {
        let words = title
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        guard words.count >= 2 else { return nil }
        let letters = words.prefix(maxLetters).compactMap { $0.first.map { String($0).uppercased(with: Locale(identifier: "tr_TR")) } }
        return letters.joined()
    }
}
