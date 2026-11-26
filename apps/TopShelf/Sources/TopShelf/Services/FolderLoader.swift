import AppKit
import Foundation

enum FolderLoader {
    private static let resourceKeys: [URLResourceKey] = [
        .nameKey,
        .localizedNameKey,
        .isDirectoryKey,
        .isPackageKey,
        .isHiddenKey,
        .fileSizeKey,
        .contentModificationDateKey,
        .addedToDirectoryDateKey,
        .localizedTypeDescriptionKey
    ]

    static func loadItems(
        in directoryURL: URL,
        sortField: SortField,
        sortOrder: SortOrder,
        foldersFirst: Bool,
        showHiddenFiles: Bool,
        showFileExtensions: Bool
    ) -> [FileItem] {
        let fm = FileManager.default
        let options: FileManager.DirectoryEnumerationOptions = showHiddenFiles ? [] : [.skipsHiddenFiles]

        guard let urls = try? fm.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: resourceKeys,
            options: options
        ) else {
            return []
        }

        var items: [FileItem] = []
        items.reserveCapacity(urls.count)

        for url in urls {
            let name = url.lastPathComponent
            if !showHiddenFiles && name.hasPrefix(".") {
                continue
            }
            if name == ".DS_Store" && !showHiddenFiles {
                continue
            }

            let values = try? url.resourceValues(forKeys: Set(resourceKeys))
            let isDir = values?.isDirectory ?? false
            let isPkg = values?.isPackage ?? false
            let isHidden = values?.isHidden ?? name.hasPrefix(".")
            let fileSize = Int64(values?.fileSize ?? 0)
            let modDate = values?.contentModificationDate ?? .distantPast
            let addDate = values?.addedToDirectoryDate ?? modDate
            let typeDesc = values?.localizedTypeDescription ?? ""

            let displayName: String
            if showFileExtensions || (isDir && !isPkg) {
                displayName = name
            } else {
                let withoutExt = url.deletingPathExtension().lastPathComponent
                displayName = withoutExt.isEmpty ? name : withoutExt
            }

            items.append(FileItem(
                url: url,
                name: name,
                displayName: displayName,
                isDirectory: isDir,
                isPackage: isPkg,
                isHidden: isHidden,
                fileSize: fileSize,
                modificationDate: modDate,
                addedDate: addDate,
                typeDescription: typeDesc
            ))
        }

        return sort(items: items, field: sortField, order: sortOrder, foldersFirst: foldersFirst)
    }

    static func sort(
        items: [FileItem],
        field: SortField,
        order: SortOrder,
        foldersFirst: Bool
    ) -> [FileItem] {
        items.sorted { lhs, rhs in
            if foldersFirst && lhs.isExpandableFolder != rhs.isExpandableFolder {
                return lhs.isExpandableFolder && !rhs.isExpandableFolder
            }

            let comparison: ComparisonResult
            switch field {
            case .name:
                comparison = lhs.name.localizedStandardCompare(rhs.name)
            case .dateModified:
                comparison = compareValues(lhs.modificationDate, rhs.modificationDate)
            case .dateAdded:
                comparison = compareValues(lhs.addedDate, rhs.addedDate)
            case .size:
                comparison = compareValues(lhs.fileSize, rhs.fileSize)
            case .kind:
                let kindCmp = lhs.typeDescription.localizedStandardCompare(rhs.typeDescription)
                comparison = kindCmp == .orderedSame
                    ? lhs.name.localizedStandardCompare(rhs.name)
                    : kindCmp
            }

            if comparison == .orderedSame {
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }

            return order == .ascending
                ? comparison == .orderedAscending
                : comparison == .orderedDescending
        }
    }

    private static func compareValues<T: Comparable>(_ a: T, _ b: T) -> ComparisonResult {
        if a < b { return .orderedAscending }
        if a > b { return .orderedDescending }
        return .orderedSame
    }
}
