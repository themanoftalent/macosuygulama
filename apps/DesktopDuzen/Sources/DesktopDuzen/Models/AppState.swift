import Foundation
import SwiftUI
import AppKit
import Combine

public final class AppState: ObservableObject {
    public static let shared = AppState()

    @Published public var zones: [ZoneModel] = []
    @Published public var stickers: [DesktopSticker] = []
    @Published public var widgets: [DesktopWidget] = []
    @Published public var autoSortRules: [AutoSortRule] = []
    @Published public var pinnedItems: [PinnedDesktopItem] = []
    @Published public var settings: AppSettings = AppSettings()
    @Published public var license: LicenseStatus = LicenseStatus()

    @Published public var selectedZoneID: UUID?
    @Published public var isAlignmentModeActive: Bool = false
    @Published public var isGlobalSearchPresented: Bool = false
    @Published public var isPaywallPresented: Bool = false
    @Published public var isSettingsPresented: Bool = false
    @Published public var isOnboardingPresented: Bool = false
    @Published public var areAllZonesHidden: Bool = false

    /// Set when the state file could not be read and was preserved under this name.
    @Published public private(set) var recoveredCorruptStateFile: URL?

    public let fileService: FileManagerService
    public let appSupportURL: URL
    public let stateFileURL: URL
    private var cancellables = Set<AnyCancellable>()
    private var isLoading = false

    /// - Parameters:
    ///   - customStorageURL: where state.json lives (tests pass a temp folder).
    ///   - fileService: where zone folders are created (tests pass a temp Desktop).
    ///   - createStarterContent: whether a missing state file should create starter zones on disk.
    public init(customStorageURL: URL? = nil, fileService: FileManagerService = .shared, createStarterContent: Bool = true) {
        self.fileService = fileService
        if let custom = customStorageURL {
            self.appSupportURL = custom
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
            self.appSupportURL = appSupport.appendingPathComponent("DesktopDuzen", isDirectory: true)
        }
        self.stateFileURL = appSupportURL.appendingPathComponent("state.json")
        try? FileManager.default.createDirectory(at: appSupportURL, withIntermediateDirectories: true)

        loadState(createStarterContent: createStarterContent)

        // One debounced save for any persisted change.
        Publishers.MergeMany(
            $zones.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            $stickers.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            $widgets.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            $pinnedItems.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            $settings.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            $license.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            $autoSortRules.dropFirst().map { _ in () }.eraseToAnyPublisher()
        )
        .debounce(for: .milliseconds(400), scheduler: RunLoop.main)
        .sink { [weak self] in self?.saveState() }
        .store(in: &cancellables)
    }

    // MARK: - Pro entitlements

    public var isPro: Bool { license.isPro || license.isMockProActive }
    public func canAddZone() -> Bool { isPro || zones.count < 3 }
    public func canUseTabs() -> Bool { isPro }
    public func canAutoExpand() -> Bool { isPro }
    public func canPinOnTop() -> Bool { isPro }
    public func canUseTheme(_ theme: ZoneTheme) -> Bool { !theme.isPro || isPro }

    // MARK: - Placement

    private func nextZoneFrame(width: CGFloat = 340, height: CGFloat = 260) -> CGRect {
        let screen = NSScreen.main?.visibleFrame ?? NSScreen.screens.first?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let count = zones.count
        let columns = max(1, Int((screen.width - 120 + 24) / (width + 24)))
        let col = count % columns
        let row = (count / columns) % 3
        let x = screen.minX + 60 + CGFloat(col) * (width + 24)
        let y = max(screen.minY + 20, screen.maxY - height - 40 - CGFloat(row) * (height + 24))
        return CGRect(x: x, y: y, width: width, height: height)
    }

    // MARK: - Zone management

    @discardableResult
    public func createDefaultFileZone(title: String = "Work Files") -> ZoneModel? {
        guard let folder = fileService.createFolderForFileZone(title: title) else { return nil }
        let zone = ZoneModel(type: .file, title: title, frame: nextZoneFrame(),
                             backingFolderPath: folder.path, themeID: "glass_blur")
        zones.append(zone)
        return zone
    }

    @discardableResult
    public func createFolderZone(title: String, folderURL: URL) -> ZoneModel {
        let zone = ZoneModel(type: .folder, title: title, frame: nextZoneFrame(),
                             backingFolderPath: folderURL.path,
                             securityBookmarkData: fileService.createSecurityBookmark(for: folderURL),
                             themeID: "slate_titanium")
        zones.append(zone)
        return zone
    }

    @discardableResult
    public func createAppZone(title: String = "Favorite Apps", initialApps: [AppItem] = []) -> ZoneModel {
        var apps = initialApps
        if apps.isEmpty { apps = defaultApps() }
        let zone = ZoneModel(type: .app, title: title, frame: nextZoneFrame(height: 220),
                             expandedHeight: 220, apps: apps, themeID: "dark_frost")
        zones.append(zone)
        return zone
    }

    private func defaultApps() -> [AppItem] {
        ["/System/Library/CoreServices/Finder.app", "/System/Applications/Mail.app",
         "/Applications/Safari.app", "/System/Applications/Utilities/Terminal.app"]
            .compactMap { fileService.resolveAppInfo(at: $0) }
    }

    public func zone(id: UUID) -> ZoneModel? { zones.first { $0.id == id } }

    public func updateZone(_ zone: ZoneModel) {
        guard let idx = zones.firstIndex(where: { $0.id == zone.id }) else { return }
        if zones[idx] != zone { zones[idx] = zone }
    }

    public func mutateZone(id: UUID, _ change: (inout ZoneModel) -> Void) {
        guard let idx = zones.firstIndex(where: { $0.id == id }) else { return }
        var copy = zones[idx]
        change(&copy)
        if copy != zones[idx] { zones[idx] = copy }
    }

    public func updateZoneFrame(id: UUID, frame: CGRect) {
        mutateZone(id: id) { zone in
            zone.frame = frame.integral
            if !zone.isCollapsed { zone.expandedHeight = zone.frame.height }
            if let screen = NSScreen.screens.first(where: { $0.frame.contains(CGPoint(x: frame.midX, y: frame.midY)) }),
               let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
                zone.displayID = number.uint32Value
            }
        }
    }

    @discardableResult
    public func deleteZone(id: UUID, action: ZoneDeleteAction) -> ZoneDeleteResult {
        guard let zone = zones.first(where: { $0.id == id }) else { return ZoneDeleteResult() }
        var result = ZoneDeleteResult()
        // Folder Zones mirror user folders the app does not own: never touch them on disk.
        if zone.type == .file {
            result = fileService.deleteZone(folderPath: zone.backingFolderPath, action: action)
        }
        zones.removeAll { $0.id == id }
        return result
    }

    public func renameZone(id: UUID, newTitle: String) {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        mutateZone(id: id) { zone in
            zone.title = trimmed
            if zone.type == .file, let newPath = fileService.renameZoneFolder(oldPath: zone.backingFolderPath, newTitle: trimmed) {
                zone.backingFolderPath = newPath
            }
        }
    }

    // MARK: - Alignment

    /// Visible frames of the connected displays (injectable for tests).
    public var screenFramesProvider: () -> [CGRect] = {
        NSScreen.screens.map { $0.visibleFrame }
    }

    private func screenIndex(for rect: CGRect, in screens: [CGRect]) -> Int {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        if let i = screens.firstIndex(where: { $0.contains(center) }) { return i }
        // Off-screen zones go to the display they overlap most, else the first.
        var best = 0
        var bestArea: CGFloat = -1
        for (i, screen) in screens.enumerated() {
            let r = screen.intersection(rect)
            let area = r.isNull ? 0 : r.width * r.height
            if area > bestArea { best = i; bestArea = area }
        }
        return best
    }

    private var gridStep: CGFloat { max(5, settings.gridSize) }

    private func snap(_ value: CGFloat, origin: CGFloat) -> CGFloat {
        origin + ((value - origin) / gridStep).rounded() * gridStep
    }

    /// Arranges zones in rows, top-left first, separately on each display, on the grid.
    public func autoAlignAllZones() {
        let screens = screenFramesProvider()
        guard !screens.isEmpty else { return }
        let margin = max(gridStep, 20)
        let spacing = gridStep
        var updated = zones
        for (s, screen) in screens.enumerated() {
            let members = updated.indices.filter { screenIndex(for: updated[$0].frame, in: screens) == s }
                .sorted { a, b in
                    // Keep the user's rough reading order: top rows first, then left to right.
                    let fa = updated[a].frame, fb = updated[b].frame
                    if abs(fa.maxY - fb.maxY) > 60 { return fa.maxY > fb.maxY }
                    return fa.minX < fb.minX
                }
            var x = screen.minX + margin
            var top = screen.maxY - margin
            var rowHeight: CGFloat = 0
            for i in members {
                let w = min(updated[i].frame.width, screen.width - 2 * margin)
                let h = updated[i].isCollapsed ? updated[i].collapsedHeight : updated[i].expandedHeight
                if x + w > screen.maxX - margin && x > screen.minX + margin {
                    x = screen.minX + margin
                    top -= rowHeight + spacing
                    rowHeight = 0
                }
                let originX = snap(x, origin: screen.minX)
                let originY = max(screen.minY, snap(top - h, origin: screen.minY))
                updated[i].frame = CGRect(x: originX, y: originY, width: w, height: h).integral
                x = originX + w + spacing
                rowHeight = max(rowHeight, h)
            }
        }
        zones = updated
    }

    /// Snaps every zone's position and size to the desktop grid without rearranging the layout.
    public func alignAllZonesToGrid() {
        let screens = screenFramesProvider()
        guard !screens.isEmpty else { return }
        var updated = zones
        for i in updated.indices {
            let screen = screens[screenIndex(for: updated[i].frame, in: screens)]
            var f = updated[i].frame
            let width = max(220, (f.width / gridStep).rounded() * gridStep)
            let height = updated[i].isCollapsed ? updated[i].collapsedHeight : max(120, (f.height / gridStep).rounded() * gridStep)
            // Snap the top-left corner (what the user sees as the zone's position).
            let left = snap(f.minX, origin: screen.minX)
            let top = snap(f.maxY, origin: screen.minY)
            f = CGRect(x: left, y: top - height, width: width, height: height)
            // Keep the zone on its display.
            f.origin.x = min(max(f.minX, screen.minX), screen.maxX - f.width)
            f.origin.y = min(max(f.minY, screen.minY), screen.maxY - f.height)
            updated[i].frame = f.integral
            if !updated[i].isCollapsed { updated[i].expandedHeight = updated[i].frame.height }
        }
        zones = updated
    }

    // MARK: - Persistence

    struct PersistedState: Codable {
        var version: Int = 2
        var zones: [ZoneModel]
        var stickers: [DesktopSticker]
        var widgets: [DesktopWidget]
        var autoSortRules: [AutoSortRule]
        var pinnedItems: [PinnedDesktopItem] = []
        var settings: AppSettings
        var license: LicenseStatus

        init(zones: [ZoneModel], stickers: [DesktopSticker], widgets: [DesktopWidget],
             autoSortRules: [AutoSortRule], pinnedItems: [PinnedDesktopItem] = [],
             settings: AppSettings, license: LicenseStatus) {
            self.zones = zones
            self.stickers = stickers
            self.widgets = widgets
            self.autoSortRules = autoSortRules
            self.pinnedItems = pinnedItems
            self.settings = settings
            self.license = license
        }

        enum CodingKeys: String, CodingKey { case version, zones, stickers, widgets, autoSortRules, pinnedItems, settings, license }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            version = c.value(.version, default: 1)
            zones = c.lossyArray(.zones)
            stickers = c.lossyArray(.stickers)
            widgets = c.lossyArray(.widgets)
            autoSortRules = c.lossyArray(.autoSortRules)
            pinnedItems = c.lossyArray(.pinnedItems)
            settings = c.value(.settings, default: AppSettings(hasCompletedOnboarding: true))
            license = c.value(.license, default: LicenseStatus())
        }
    }

    private func snapshot() -> PersistedState {
        PersistedState(zones: zones, stickers: stickers, widgets: widgets,
                       autoSortRules: autoSortRules, pinnedItems: pinnedItems,
                       settings: settings, license: license)
    }

    @discardableResult
    public func saveState() -> Bool {
        guard !isLoading else { return false }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(snapshot())
            try FileManager.default.createDirectory(at: appSupportURL, withIntermediateDirectories: true)
            try data.write(to: stateFileURL, options: .atomic)
            return true
        } catch {
            NSLog("DesktopDuzen: failed to save state: \(error.localizedDescription)")
            return false
        }
    }

    public func loadState(createStarterContent: Bool = true) {
        isLoading = true
        defer { isLoading = false }

        guard FileManager.default.fileExists(atPath: stateFileURL.path) else {
            populateStarterData(createFolders: createStarterContent)
            isLoading = false
            saveState()
            return
        }
        guard let data = try? Data(contentsOf: stateFileURL),
              let state = try? JSONDecoder().decode(PersistedState.self, from: data) else {
            // Keep the unreadable file instead of silently overwriting the user's layout.
            let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            let backup = appSupportURL.appendingPathComponent("state.unreadable-\(stamp).json")
            try? FileManager.default.moveItem(at: stateFileURL, to: backup)
            recoveredCorruptStateFile = backup
            NSLog("DesktopDuzen: state.json unreadable, preserved as \(backup.lastPathComponent)")
            populateStarterData(createFolders: createStarterContent)
            isLoading = false
            saveState()
            return
        }
        apply(state)
    }

    private func apply(_ state: PersistedState) {
        var seen = Set<UUID>()
        var cleanZones: [ZoneModel] = []
        for var zone in state.zones where !seen.contains(zone.id) {
            seen.insert(zone.id)
            // Folder Zones follow their folder if it was renamed or moved in Finder.
            if zone.type == .folder, let data = zone.securityBookmarkData,
               let resolved = fileService.resolveBookmark(data: data),
               resolved.path != zone.backingFolderPath,
               fileService.folderExists(resolved.path) {
                zone.backingFolderPath = resolved.path
            }
            // Earlier builds stored a Finder path that does not exist.
            for i in zone.apps.indices where zone.apps[i].path == "/System/Applications/Finder.app" {
                zone.apps[i].path = "/System/Library/CoreServices/Finder.app"
                zone.apps[i].bundleID = "com.apple.finder"
            }
            cleanZones.append(zone)
        }
        zones = cleanZones
        stickers = dedupe(state.stickers)
        widgets = AppState.removingDuplicateSingletons(dedupe(state.widgets))
        autoSortRules = state.autoSortRules.isEmpty ? AutoSortRule.defaultRules : dedupe(state.autoSortRules)
        pinnedItems = dedupe(state.pinnedItems)
        settings = state.settings
        license = state.license
    }

    /// Keeps the first clock, calendar and monitor; sticky notes are never merged.
    public static func removingDuplicateSingletons(_ widgets: [DesktopWidget]) -> [DesktopWidget] {
        var seen = Set<WidgetType>()
        return widgets.filter { w in
            guard w.type.isSingleInstance else { return true }
            return seen.insert(w.type).inserted
        }
    }

    /// Adds a widget unless one of a single-instance type already exists.
    /// Returns the existing widget's id when nothing was added.
    @discardableResult
    public func addWidget(_ widget: DesktopWidget) -> (added: Bool, id: UUID) {
        if widget.type.isSingleInstance, let existing = widgets.first(where: { $0.type == widget.type }) {
            return (false, existing.id)
        }
        widgets.append(widget)
        return (true, widget.id)
    }

    private func dedupe<T: Identifiable>(_ items: [T]) -> [T] where T.ID == UUID {
        var seen = Set<UUID>()
        return items.filter { seen.insert($0.id).inserted }
    }

    /// First-run content. Folder creation reuses existing same-named folders, so running it again
    /// (e.g. after a reset) never produces "Active Projects 1", "Active Projects 2", ...
    public func populateStarterData(createFolders: Bool = true) {
        zones = []
        widgets = []
        stickers = []
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let width: CGFloat = 340
        let height: CGFloat = 260
        let topY = screen.maxY - height - 40

        if createFolders {
            if let folder = fileService.createFolderForFileZone(title: "Active Projects", reuseExisting: true) {
                zones.append(ZoneModel(type: .file, title: "Active Projects",
                                       frame: CGRect(x: screen.minX + 60, y: topY, width: width, height: height),
                                       backingFolderPath: folder.path, themeID: "glass_blur"))
                let welcome = folder.appendingPathComponent("Welcome to DesktopDüzen.txt")
                if !FileManager.default.fileExists(atPath: welcome.path) {
                    let text = """
                    Welcome to DesktopDüzen!

                    • Drag files from the Desktop or Finder into any zone (hold Option to copy).
                    • Double-click a file to open it; press Space for Quick Look.
                    • Drag a zone by its title bar; resize it from the bottom-right corner.
                    • Use the palette button to change theme, colour and transparency.
                    • Files in a zone live in ~/Desktop/Zones/<zone name> and stay visible in Finder.
                    """
                    try? text.write(to: welcome, atomically: true, encoding: .utf8)
                }
            }
            if let folder = fileService.createFolderForFileZone(title: "Downloads & Media", reuseExisting: true) {
                zones.append(ZoneModel(type: .file, title: "Downloads & Media",
                                       frame: CGRect(x: screen.minX + 60 + width + 24, y: topY, width: width, height: height),
                                       backingFolderPath: folder.path, themeID: "glass_blur"))
            }
        }
        zones.append(ZoneModel(type: .app, title: "Quick Launcher",
                               frame: CGRect(x: screen.minX + 60 + (width + 24) * 2, y: topY + 40, width: width, height: 220),
                               expandedHeight: 220, apps: defaultApps(), themeID: "dark_frost"))
        autoSortRules = AutoSortRule.defaultRules
        license = LicenseStatus(isPro: true, activePlan: .lifetime, isMockProActive: true)
        widgets.append(DesktopWidget(type: .clock, title: WidgetType.clock.displayName,
                                     frame: CGRect(x: screen.minX + 60, y: max(screen.minY + 40, topY - 150), width: 220, height: 120)))
    }

    public func exportConfigurationJSON() -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(snapshot()) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func importConfigurationJSON(_ json: String) -> Bool {
        guard let data = json.data(using: .utf8),
              let state = try? JSONDecoder().decode(PersistedState.self, from: data) else {
            return false
        }
        // Reject input that is valid JSON but not a DesktopDüzen layout.
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["zones"] != nil else { return false }
        apply(state)
        saveState()
        return true
    }

    // MARK: - Pinned Desktop Items

    public func isItemPinned(path: String) -> Bool {
        let stdPath = URL(fileURLWithPath: path).standardizedFileURL.path
        return pinnedItems.contains {
            URL(fileURLWithPath: $0.path).standardizedFileURL.path == stdPath
        }
    }

    public func pinnedItem(for path: String) -> PinnedDesktopItem? {
        let stdPath = URL(fileURLWithPath: path).standardizedFileURL.path
        return pinnedItems.first {
            URL(fileURLWithPath: $0.path).standardizedFileURL.path == stdPath
        }
    }

    public func addPinnedItem(_ item: PinnedDesktopItem) {
        pinnedItems.removeAll { $0.id == item.id || $0.path == item.path }
        pinnedItems.append(item)
    }

    public func removePinnedItem(id: UUID) {
        pinnedItems.removeAll { $0.id == id }
    }

    public func removePinnedItem(path: String) {
        let stdPath = URL(fileURLWithPath: path).standardizedFileURL.path
        pinnedItems.removeAll {
            URL(fileURLWithPath: $0.path).standardizedFileURL.path == stdPath
        }
    }

    public func removeAllPinnedItems() {
        pinnedItems.removeAll()
    }
}
