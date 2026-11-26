import AppKit
import Foundation
import SwiftUI

enum SortField: String, Codable, CaseIterable, Identifiable {
    case name = "Name"
    case dateModified = "Date Modified"
    case dateAdded = "Date Added"
    case size = "Size"
    case kind = "Kind"

    var id: String { rawValue }
}

enum SortOrder: String, Codable, CaseIterable, Identifiable {
    case ascending = "Ascending"
    case descending = "Descending"

    var id: String { rawValue }
}

enum IconColorOption: String, Codable, CaseIterable, Identifiable {
    case monochrome = "Monochrome"
    case blue = "Blue"
    case indigo = "Indigo"
    case purple = "Purple"
    case pink = "Pink"
    case red = "Red"
    case orange = "Orange"
    case yellow = "Yellow"
    case green = "Green"
    case teal = "Teal"

    var id: String { rawValue }

    var nsColor: NSColor? {
        switch self {
        case .monochrome: return nil
        case .blue: return .systemBlue
        case .indigo: return .systemIndigo
        case .purple: return .systemPurple
        case .pink: return .systemPink
        case .red: return .systemRed
        case .orange: return .systemOrange
        case .yellow: return .systemYellow
        case .green: return .systemGreen
        case .teal: return .systemTeal
        }
    }

    var swiftUIColor: Color {
        switch self {
        case .monochrome: return .primary
        case .blue: return .blue
        case .indigo: return .indigo
        case .purple: return .purple
        case .pink: return .pink
        case .red: return .red
        case .orange: return .orange
        case .yellow: return .yellow
        case .green: return .green
        case .teal: return .teal
        }
    }
}

struct PinnedFolder: Identifiable, Codable, Equatable {
    var id: UUID
    var path: String
    var customName: String?
    var symbolName: String
    var colorOption: IconColorOption
    var showTitleInMenuBar: Bool
    var sortField: SortField
    var sortOrder: SortOrder
    var foldersFirst: Bool
    var showHiddenFiles: Bool

    init(
        id: UUID = UUID(),
        path: String,
        customName: String? = nil,
        symbolName: String = "folder.fill",
        colorOption: IconColorOption = .monochrome,
        showTitleInMenuBar: Bool = false,
        sortField: SortField = .name,
        sortOrder: SortOrder = .ascending,
        foldersFirst: Bool = true,
        showHiddenFiles: Bool = false
    ) {
        self.id = id
        self.path = path
        self.customName = customName
        self.symbolName = symbolName
        self.colorOption = colorOption
        self.showTitleInMenuBar = showTitleInMenuBar
        self.sortField = sortField
        self.sortOrder = sortOrder
        self.foldersFirst = foldersFirst
        self.showHiddenFiles = showHiddenFiles
    }

    var url: URL {
        URL(fileURLWithPath: path)
    }

    var displayName: String {
        if let customName, !customName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return customName
        }
        return url.lastPathComponent.isEmpty ? path : url.lastPathComponent
    }

    var exists: Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }

    static let curatedSymbols: [String] = [
        "folder.fill",
        "folder",
        "folder.badge.gearshape",
        "folder.badge.person.crop",
        "tray.full.fill",
        "arrow.down.circle.fill",
        "desktopcomputer",
        "doc.fill",
        "doc.on.doc.fill",
        "photo.fill",
        "film.fill",
        "music.note",
        "briefcase.fill",
        "archivebox.fill",
        "star.fill",
        "bookmark.fill",
        "heart.fill",
        "hammer.fill",
        "terminal.fill",
        "chevron.left.forwardslash.chevron.right",
        "icloud.fill",
        "externaldrive.fill",
        "shippingbox.fill",
        "book.fill"
    ]
}

struct AppSettings: Codable, Equatable {
    var enableHoverPreview: Bool = true
    var showFileExtensions: Bool = true
    var launchAtLogin: Bool = false
}

struct FileItem: Identifiable, Hashable {
    let url: URL
    let name: String
    let displayName: String
    let isDirectory: Bool
    let isPackage: Bool
    let isHidden: Bool
    let fileSize: Int64
    let modificationDate: Date
    let addedDate: Date
    let typeDescription: String

    var id: String { url.path }

    var isExpandableFolder: Bool {
        isDirectory && !isPackage
    }

    func icon(size: NSSize = NSSize(width: 18, height: 18)) -> NSImage {
        let img = NSWorkspace.shared.icon(forFile: url.path)
        img.size = size
        return img
    }
}
