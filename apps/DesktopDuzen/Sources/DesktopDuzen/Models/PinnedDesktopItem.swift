import Foundation
import CoreGraphics

/// Represents a desktop item (file, folder, or icon) locked to a specific desktop position.
public struct PinnedDesktopItem: Identifiable, Codable, Equatable {
    public var id: UUID
    public var name: String
    public var path: String
    public var position: CGPoint
    public var displayID: UInt32?
    public var screenBounds: CGRect?
    public var bookmarkData: Data?
    public var pinnedAt: Date

    public init(id: UUID = UUID(),
                name: String,
                path: String,
                position: CGPoint,
                displayID: UInt32? = nil,
                screenBounds: CGRect? = nil,
                bookmarkData: Data? = nil,
                pinnedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.path = path
        self.position = position
        self.displayID = displayID
        self.screenBounds = screenBounds
        self.bookmarkData = bookmarkData
        self.pinnedAt = pinnedAt
    }
}
