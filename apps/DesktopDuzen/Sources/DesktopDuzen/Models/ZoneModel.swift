import Foundation
import CoreGraphics

public struct ZoneModel: Identifiable, Codable, Equatable {
    public var id: UUID
    public var type: ZoneType
    public var title: String
    /// Frame in global AppKit screen coordinates (origin bottom-left of the primary display).
    public var frame: CGRect
    public var displayID: UInt32
    public var isCollapsed: Bool
    public var collapsedHeight: CGFloat
    public var expandedHeight: CGFloat
    public var autoExpandOnHover: Bool
    public var isPinnedOnTop: Bool
    public var isPositionLocked: Bool
    public var viewMode: ZoneViewMode
    public var sortMode: ZoneSortMode
    public var tabs: [ZoneTab]
    public var activeTabID: UUID?
    public var apps: [AppItem]
    public var backingFolderPath: String
    public var securityBookmarkData: Data?
    public var themeID: String
    /// Optional user-chosen tint that overrides the theme background.
    public var customBackgroundHex: String?
    /// Optional user-chosen background opacity (0 = fully transparent ... 1).
    public var customBackgroundOpacity: Double?
    /// Draw the outline around the zone.
    public var showBorder: Bool
    /// Draw the window drop shadow.
    public var showShadow: Bool
    public var iconSize: Double
    public var fontSize: Double
    public var iconSpacing: Double
    public var manualOrder: [String]
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        type: ZoneType = .file,
        title: String,
        frame: CGRect = CGRect(x: 100, y: 100, width: 340, height: 260),
        displayID: UInt32 = 0,
        isCollapsed: Bool = false,
        collapsedHeight: CGFloat = 42.0,
        expandedHeight: CGFloat = 260.0,
        autoExpandOnHover: Bool = false,
        isPinnedOnTop: Bool = false,
        isPositionLocked: Bool = false,
        viewMode: ZoneViewMode = .icon,
        sortMode: ZoneSortMode = .manual,
        tabs: [ZoneTab] = [],
        activeTabID: UUID? = nil,
        apps: [AppItem] = [],
        backingFolderPath: String = "",
        securityBookmarkData: Data? = nil,
        themeID: String = "glass_blur",
        customBackgroundHex: String? = nil,
        customBackgroundOpacity: Double? = nil,
        showBorder: Bool = true,
        showShadow: Bool = true,
        iconSize: Double = 52.0,
        fontSize: Double = 11.5,
        iconSpacing: Double = 12.0,
        manualOrder: [String] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.frame = frame
        self.displayID = displayID
        self.isCollapsed = isCollapsed
        self.collapsedHeight = collapsedHeight
        self.expandedHeight = expandedHeight
        self.autoExpandOnHover = autoExpandOnHover
        self.isPinnedOnTop = isPinnedOnTop
        self.isPositionLocked = isPositionLocked
        self.viewMode = viewMode
        self.sortMode = sortMode
        self.tabs = tabs
        self.activeTabID = activeTabID
        self.apps = apps
        self.backingFolderPath = backingFolderPath
        self.securityBookmarkData = securityBookmarkData
        self.themeID = themeID
        self.customBackgroundHex = customBackgroundHex
        self.customBackgroundOpacity = customBackgroundOpacity
        self.showBorder = showBorder
        self.showShadow = showShadow
        self.iconSize = iconSize
        self.fontSize = fontSize
        self.iconSpacing = iconSpacing
        self.manualOrder = manualOrder
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case id, type, title, frame, displayID, isCollapsed, collapsedHeight, expandedHeight
        case autoExpandOnHover, isPinnedOnTop, isPositionLocked, viewMode, sortMode, tabs, activeTabID, apps
        case backingFolderPath, securityBookmarkData, themeID, customBackgroundHex
        case customBackgroundOpacity, showBorder, showShadow, iconSize, fontSize, iconSpacing, manualOrder, createdAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // The id is the only field without which a zone cannot be tracked.
        self.id = try c.decode(UUID.self, forKey: .id)
        self.title = c.value(.title, default: "Zone")
        self.type = c.value(.type, default: .file)
        self.frame = c.value(.frame, default: CGRect(x: 100, y: 100, width: 340, height: 260))
        self.displayID = c.value(.displayID, default: 0)
        self.isCollapsed = c.value(.isCollapsed, default: false)
        self.collapsedHeight = c.value(.collapsedHeight, default: 42.0)
        self.expandedHeight = c.value(.expandedHeight, default: 260.0)
        self.autoExpandOnHover = c.value(.autoExpandOnHover, default: false)
        self.isPinnedOnTop = c.value(.isPinnedOnTop, default: false)
        self.isPositionLocked = c.value(.isPositionLocked, default: false)
        self.viewMode = c.value(.viewMode, default: .icon)
        self.sortMode = c.value(.sortMode, default: .manual)
        self.tabs = c.lossyArray(.tabs)
        self.activeTabID = c.optionalValue(.activeTabID)
        self.apps = c.lossyArray(.apps)
        self.backingFolderPath = c.value(.backingFolderPath, default: "")
        self.securityBookmarkData = c.optionalValue(.securityBookmarkData)
        self.themeID = c.value(.themeID, default: "glass_blur")
        self.customBackgroundHex = c.optionalValue(.customBackgroundHex)
        self.customBackgroundOpacity = c.optionalValue(.customBackgroundOpacity)
        self.showBorder = c.value(.showBorder, default: true)
        self.showShadow = c.value(.showShadow, default: true)
        self.iconSize = c.value(.iconSize, default: 52.0)
        self.fontSize = c.value(.fontSize, default: 11.5)
        self.iconSpacing = c.value(.iconSpacing, default: 12.0)
        self.manualOrder = c.value(.manualOrder, default: [])
        self.createdAt = c.value(.createdAt, default: Date())
        sanitize()
    }

    /// Repairs values that would produce an unusable window.
    public mutating func sanitize() {
        if !frame.origin.x.isFinite || !frame.origin.y.isFinite { frame.origin = CGPoint(x: 100, y: 100) }
        if !frame.width.isFinite || frame.width < 200 { frame.size.width = frame.width.isFinite ? max(200, frame.width) : 340 }
        if !frame.height.isFinite || frame.height < 30 { frame.size.height = 260 }
        if collapsedHeight < 30 || collapsedHeight > 80 { collapsedHeight = 42 }
        if !expandedHeight.isFinite || expandedHeight < 120 { expandedHeight = 260 }
        if isCollapsed {
            frame.size.height = collapsedHeight
        } else if frame.height < 120 {
            frame.size.height = expandedHeight
        }
        iconSize = min(max(iconSize, 24), 96)
        fontSize = min(max(fontSize, 8), 18)
        iconSpacing = min(max(iconSpacing, 4), 32)
        if let opacity = customBackgroundOpacity { customBackgroundOpacity = min(max(opacity, 0.0), 1.0) }
        if let active = activeTabID, !tabs.contains(where: { $0.id == active }) { activeTabID = tabs.first?.id }
    }

    /// Below this background opacity a zone is drawn in "clear" mode: no blur, no forced
    /// opacity, labels get a halo so they stay readable directly on the wallpaper.
    public static let clearModeThreshold = 0.35

    public var resolvedFolderPath: String {
        if type == .app { return "" }
        if !tabs.isEmpty, let activeID = activeTabID, let tab = tabs.first(where: { $0.id == activeID }) {
            return (backingFolderPath as NSString).appendingPathComponent(tab.subfolderName)
        }
        return backingFolderPath
    }
}
