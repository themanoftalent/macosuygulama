import Foundation
import AppKit
import ApplicationServices
import Combine

/// Manages locking desktop items (files, folders, icons) to persistent coordinates.
/// Enforces positions using Finder's scripting interface and AX accessibility inspection,
/// snapping items back if dragged or auto-arranged, and excluding them from auto-sort.
public final class DesktopPinService: ObservableObject {
    public static let shared = DesktopPinService()

    private let appState: AppState
    private var desktopMonitor: FolderMonitor?
    private var enforceTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var isEnforcing = false
    private let desktopURL: URL

    public init(appState: AppState = .shared) {
        self.appState = appState
        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Desktop", isDirectory: true)
        self.desktopURL = desktop.standardizedFileURL
    }

    public func start() {
        setupDesktopMonitoring()
        setupSystemObservers()
        enforcePositions()
    }

    public func stop() {
        desktopMonitor?.stop()
        desktopMonitor = nil
        enforceTimer?.invalidate()
        enforceTimer = nil
        cancellables.removeAll()
    }

    // MARK: - Monitoring & Enforcement

    private func setupDesktopMonitoring() {
        let monitor = FolderMonitor(url: desktopURL)
        monitor.debounce = .milliseconds(800)
        monitor.onChange = { [weak self] in
            DispatchQueue.main.async {
                self?.enforcePositions()
            }
        }
        monitor.start()
        desktopMonitor = monitor

        // Periodic low-overhead enforcement timer (runs every 4 seconds only if items are pinned)
        enforceTimer?.invalidate()
        enforceTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if !self.appState.pinnedItems.isEmpty {
                self.enforcePositions()
            }
        }
    }

    private func setupSystemObservers() {
        let center = NotificationCenter.default
        center.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.handleDisplayChange()
            }
            .store(in: &cancellables)

        let ws = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification,
                     NSWorkspace.sessionDidBecomeActiveNotification, NSWorkspace.activeSpaceDidChangeNotification] {
            ws.publisher(for: name)
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        self?.enforcePositions()
                    }
                }
                .store(in: &cancellables)
        }
    }

    /// Checks all pinned items and restores their desktop coordinates if they have been moved.
    public func enforcePositions() {
        guard !isEnforcing else { return }
        guard !appState.pinnedItems.isEmpty else { return }
        isEnforcing = true
        defer { isEnforcing = false }

        for item in appState.pinnedItems {
            // Verify that the file still exists on disk
            guard FileManager.default.fileExists(atPath: item.path) else { continue }

            let currentPos = getDesktopPosition(for: item.name)
            if let current = currentPos {
                let dx = abs(current.x - item.position.x)
                let dy = abs(current.y - item.position.y)
                // If the item has deviated from its pinned coordinates, restore it immediately
                if dx > 2 || dy > 2 {
                    _ = setDesktopPosition(for: item.name, to: item.position)
                }
            } else {
                // If Finder has unpositioned (-1, -1) coordinates, write the pinned coordinates
                _ = setDesktopPosition(for: item.name, to: item.position)
            }
        }
    }

    /// Handles screen resolution or display configuration changes.
    public func handleDisplayChange() {
        guard !appState.pinnedItems.isEmpty else { return }
        let currentScreens = NSScreen.screens
        for item in appState.pinnedItems {
            guard FileManager.default.fileExists(atPath: item.path) else { continue }
            // Check if the screen where it was pinned is available
            if let savedDisplayID = item.displayID {
                let matchingScreen = currentScreens.first { screen in
                    guard let num = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
                    return num.uint32Value == savedDisplayID
                }
                if matchingScreen != nil {
                    // Original display is connected, enforce coordinates
                    _ = setDesktopPosition(for: item.name, to: item.position)
                    continue
                }
            }
            // Otherwise, enforce on the primary desktop
            _ = setDesktopPosition(for: item.name, to: item.position)
        }
    }

    // MARK: - Pin / Unpin Actions

    /// Pins an item at the given URL to its current desktop coordinates.
    @discardableResult
    public func pinItem(at url: URL, customPosition: CGPoint? = nil) -> PinnedDesktopItem? {
        let stdURL = url.standardizedFileURL
        let name = stdURL.lastPathComponent
        guard FileManager.default.fileExists(atPath: stdURL.path) else { return nil }

        var pos: CGPoint
        if let custom = customPosition {
            pos = custom
        } else if let finderPos = getDesktopPosition(for: name), finderPos.x >= 0, finderPos.y >= 0 {
            pos = finderPos
        } else if let axInfo = getAXPosition(for: name) {
            pos = axInfo.pos
        } else {
            // Default placement on desktop grid
            pos = CGPoint(x: 200, y: 200)
        }

        var displayID: UInt32? = nil
        var screenBounds: CGRect? = nil
        if let screen = NSScreen.main ?? NSScreen.screens.first {
            if let num = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
                displayID = num.uint32Value
            }
            screenBounds = screen.frame
        }

        let bookmark = try? stdURL.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)

        let pinned = PinnedDesktopItem(
            name: name,
            path: stdURL.path,
            position: pos,
            displayID: displayID,
            screenBounds: screenBounds,
            bookmarkData: bookmark,
            pinnedAt: Date()
        )

        appState.addPinnedItem(pinned)
        _ = setDesktopPosition(for: name, to: pos)
        return pinned
    }

    /// Unpins an item by ID.
    public func unpinItem(id: UUID) {
        appState.removePinnedItem(id: id)
    }

    /// Unpins an item at the specified URL.
    public func unpinItem(at url: URL) {
        appState.removePinnedItem(path: url.standardizedFileURL.path)
    }

    /// Unpins all desktop items.
    public func unpinAll() {
        appState.removeAllPinnedItems()
    }

    // MARK: - Finder Scripting

    /// Queries Finder via AppleScript for the coordinates of a desktop item.
    public func getDesktopPosition(for itemName: String) -> CGPoint? {
        let escapedName = itemName.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let scriptSource = """
        tell application "Finder"
            try
                set p to position of item "\(escapedName)" of desktop
                return (item 1 of p as string) & "," & (item 2 of p as string)
            on error
                return ""
            end try
        end tell
        """
        guard let script = NSAppleScript(source: scriptSource) else { return nil }
        var error: NSDictionary?
        let descriptor = script.executeAndReturnError(&error)
        guard let str = descriptor.stringValue, !str.isEmpty else { return nil }
        let parts = str.components(separatedBy: ",")
        guard parts.count == 2,
              let x = Double(parts[0].trimmingCharacters(in: .whitespaces)),
              let y = Double(parts[1].trimmingCharacters(in: .whitespaces)) else { return nil }
        if x < 0 || y < 0 { return nil } // Finder unpositioned placeholder (-1, -1)
        return CGPoint(x: x, y: y)
    }

    /// Sets the desktop position of an item in Finder via AppleScript.
    @discardableResult
    public func setDesktopPosition(for itemName: String, to position: CGPoint) -> Bool {
        let escapedName = itemName.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let x = Int(round(position.x))
        let y = Int(round(position.y))
        let scriptSource = """
        tell application "Finder"
            try
                set position of item "\(escapedName)" of desktop to {\(x), \(y)}
                return "ok"
            on error
                return "err"
            end try
        end tell
        """
        guard let script = NSAppleScript(source: scriptSource) else { return false }
        var error: NSDictionary?
        let descriptor = script.executeAndReturnError(&error)
        return descriptor.stringValue == "ok"
    }

    // MARK: - Accessibility Fallback

    /// Retrieves visible position and size directly from Finder's desktop view via the Accessibility API.
    public func getAXPosition(for itemName: String) -> (pos: CGPoint, size: CGSize)? {
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder")
        guard let finder = apps.first else { return nil }
        let appElement = AXUIElementCreateApplication(finder.processIdentifier)
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else { return nil }

        for child in children {
            var roleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &roleRef)
            if (roleRef as? String) == "AXScrollArea" {
                var scrollChildrenRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(child, kAXChildrenAttribute as CFString, &scrollChildrenRef) == .success,
                   let scrollChildren = scrollChildrenRef as? [AXUIElement] {
                    for sc in scrollChildren {
                        var iconsRef: CFTypeRef?
                        if AXUIElementCopyAttributeValue(sc, kAXChildrenAttribute as CFString, &iconsRef) == .success,
                           let icons = iconsRef as? [AXUIElement] {
                            for icon in icons {
                                var iconTitleRef: CFTypeRef?
                                AXUIElementCopyAttributeValue(icon, kAXTitleAttribute as CFString, &iconTitleRef)
                                if let title = iconTitleRef as? String, title == itemName {
                                    var posVal: CFTypeRef?
                                    AXUIElementCopyAttributeValue(icon, kAXPositionAttribute as CFString, &posVal)
                                    var sizeVal: CFTypeRef?
                                    AXUIElementCopyAttributeValue(icon, kAXSizeAttribute as CFString, &sizeVal)
                                    var pt = CGPoint.zero
                                    var sz = CGSize(width: 48, height: 48)
                                    if let val = posVal { AXValueGetValue(val as! AXValue, .cgPoint, &pt) }
                                    if let val = sizeVal { AXValueGetValue(val as! AXValue, .cgSize, &sz) }
                                    return (pt, sz)
                                }
                            }
                        }
                    }
                }
            }
        }
        return nil
    }

    /// Converts Finder top-left coordinates to AppKit bottom-left screen coordinates.
    public static func finderPointToAppKit(_ finderPoint: CGPoint) -> CGPoint {
        let primaryH = NSScreen.screens.first?.frame.height ?? 900
        return CGPoint(x: finderPoint.x, y: primaryH - finderPoint.y)
    }
}
