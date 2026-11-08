import Foundation

public struct AppSettings: Codable, Equatable {
    public var launchAtLogin: Bool
    public var alignmentMode: Bool
    public var snapToGrid: Bool
    public var snapToNeighbors: Bool
    public var gridSize: CGFloat
    public var snapThreshold: CGFloat
    public var showZonesOnAllSpaces: Bool
    public var autoSortEnabled: Bool
    public var hideLooseDesktopIcons: Bool
    public var globalHotkeyEnabled: Bool
    public var hasCompletedOnboarding: Bool
    public var showHubOnLaunch: Bool
    /// Zone title bars stay invisible until the pointer is over the zone.
    public var hideTitleBarsUntilHover: Bool
    /// When false (default) clicking a zone leaves keyboard focus with the frontmost app, so
    /// macOS and app shortcuts keep working. Zones still take focus for text editing.
    public var zonesTakeKeyboardFocus: Bool
    /// Off by default: DesktopDüzen lives in the menu bar, not the Dock or Cmd-Tab.
    public var showDockIcon: Bool

    public init(
        launchAtLogin: Bool = false,
        alignmentMode: Bool = true,
        snapToGrid: Bool = true,
        snapToNeighbors: Bool = true,
        gridSize: CGFloat = 20.0,
        snapThreshold: CGFloat = 14.0,
        showZonesOnAllSpaces: Bool = true,
        autoSortEnabled: Bool = false,
        hideLooseDesktopIcons: Bool = false,
        globalHotkeyEnabled: Bool = true,
        hasCompletedOnboarding: Bool = false,
        showHubOnLaunch: Bool = true,
        hideTitleBarsUntilHover: Bool = true,
        zonesTakeKeyboardFocus: Bool = false,
        showDockIcon: Bool = false
    ) {
        self.launchAtLogin = launchAtLogin
        self.alignmentMode = alignmentMode
        self.snapToGrid = snapToGrid
        self.snapToNeighbors = snapToNeighbors
        self.gridSize = gridSize
        self.snapThreshold = snapThreshold
        self.showZonesOnAllSpaces = showZonesOnAllSpaces
        self.autoSortEnabled = autoSortEnabled
        self.hideLooseDesktopIcons = hideLooseDesktopIcons
        self.globalHotkeyEnabled = globalHotkeyEnabled
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.showHubOnLaunch = showHubOnLaunch
        self.hideTitleBarsUntilHover = hideTitleBarsUntilHover
        self.zonesTakeKeyboardFocus = zonesTakeKeyboardFocus
        self.showDockIcon = showDockIcon
    }

    enum CodingKeys: String, CodingKey {
        case launchAtLogin, alignmentMode, snapToGrid, snapToNeighbors, gridSize, snapThreshold
        case showZonesOnAllSpaces, autoSortEnabled, hideLooseDesktopIcons, globalHotkeyEnabled
        case hasCompletedOnboarding, showHubOnLaunch, hideTitleBarsUntilHover, zonesTakeKeyboardFocus, showDockIcon
    }

    public init(from decoder: Decoder) throws {
        let d = AppSettings()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        launchAtLogin = c.value(.launchAtLogin, default: d.launchAtLogin)
        alignmentMode = c.value(.alignmentMode, default: d.alignmentMode)
        snapToGrid = c.value(.snapToGrid, default: d.snapToGrid)
        snapToNeighbors = c.value(.snapToNeighbors, default: d.snapToNeighbors)
        gridSize = min(max(c.value(.gridSize, default: d.gridSize), 5), 60)
        snapThreshold = min(max(c.value(.snapThreshold, default: d.snapThreshold), 2), 40)
        showZonesOnAllSpaces = c.value(.showZonesOnAllSpaces, default: d.showZonesOnAllSpaces)
        autoSortEnabled = c.value(.autoSortEnabled, default: d.autoSortEnabled)
        hideLooseDesktopIcons = c.value(.hideLooseDesktopIcons, default: d.hideLooseDesktopIcons)
        globalHotkeyEnabled = c.value(.globalHotkeyEnabled, default: d.globalHotkeyEnabled)
        hasCompletedOnboarding = c.value(.hasCompletedOnboarding, default: d.hasCompletedOnboarding)
        showHubOnLaunch = c.value(.showHubOnLaunch, default: d.showHubOnLaunch)
        hideTitleBarsUntilHover = c.value(.hideTitleBarsUntilHover, default: d.hideTitleBarsUntilHover)
        zonesTakeKeyboardFocus = c.value(.zonesTakeKeyboardFocus, default: d.zonesTakeKeyboardFocus)
        showDockIcon = c.value(.showDockIcon, default: d.showDockIcon)
    }
}

public enum ProTierPlan: String, Codable, CaseIterable {
    case monthly = "Monthly"
    case annual = "Annual"
    case lifetime = "Lifetime"

    public var priceString: String {
        switch self {
        case .monthly: return "$1.99 / month"
        case .annual: return "$19.99 / year"
        case .lifetime: return "$24.99 one-time"
        }
    }

    public var savingsBadge: String? {
        switch self {
        case .monthly: return nil
        case .annual: return "Save 16%"
        case .lifetime: return "Best Value"
        }
    }
}

public struct LicenseStatus: Codable, Equatable {
    public var isPro: Bool
    public var activePlan: ProTierPlan?
    public var expirationDate: Date?
    public var isMockProActive: Bool

    public init(
        isPro: Bool = true, // All features enabled by default; toggle available in Settings.
        activePlan: ProTierPlan? = .lifetime,
        expirationDate: Date? = nil,
        isMockProActive: Bool = true
    ) {
        self.isPro = isPro
        self.activePlan = activePlan
        self.expirationDate = expirationDate
        self.isMockProActive = isMockProActive
    }

    enum CodingKeys: String, CodingKey { case isPro, activePlan, expirationDate, isMockProActive }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        isPro = c.value(.isPro, default: true)
        activePlan = c.optionalValue(.activePlan)
        expirationDate = c.optionalValue(.expirationDate)
        isMockProActive = c.value(.isMockProActive, default: isPro)
    }
}
