import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Shared selection, menu and drop behaviour

enum FileSelection {
    static func apply(click file: FileItem, ordered: [FileItem], selection: inout Set<String>, anchor: inout String?) {
        let flags = NSEvent.modifierFlags
        if flags.contains(.command) {
            if selection.contains(file.path) { selection.remove(file.path) } else { selection.insert(file.path) }
            anchor = file.path
        } else if flags.contains(.shift), let anchorPath = anchor,
                  let a = ordered.firstIndex(where: { $0.path == anchorPath }),
                  let b = ordered.firstIndex(where: { $0.path == file.path }) {
            selection = Set(ordered[min(a, b)...max(a, b)].map(\.path))
        } else if selection == [file.path] {
            // Clicking the only selected item again deselects it.
            selection = []
            anchor = nil
        } else {
            selection = [file.path]
            anchor = file.path
        }
    }
}

struct FileContextMenu: View {
    let file: FileItem
    let files: [FileItem]
    let selectedFilePaths: Set<String>
    let actions: ZoneFileActions
    let beginRename: () -> Void

    private var targets: [FileItem] {
        selectedFilePaths.contains(file.path) ? files.filter { selectedFilePaths.contains($0.path) } : [file]
    }

    var body: some View {
        Button("Open") { targets.forEach(actions.open) }
        Button("Quick Look") { QuickLookManager.shared.preview(urls: targets.map(\.url)) }
        Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting(targets.map(\.url)) }
        Divider()
        Button("Rename…", action: beginRename).disabled(targets.count != 1)
        Button("Duplicate") { targets.forEach(actions.duplicate) }
        Button("Copy Path") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(targets.map(\.path).joined(separator: "\n"), forType: .string)
        }
        if !actions.otherZones.isEmpty {
            Menu("Move to Zone") {
                ForEach(actions.otherZones) { zone in
                    Button(zone.title) { actions.moveToZone(targets, zone) }
                }
            }
        }
        Divider()
        Button("Move to Trash…") { actions.trash(targets) }
    }
}

/// Dropping onto an item: reorders when the file already belongs to this zone, otherwise
/// behaves like dropping on the zone.
struct FileItemDropDelegate: DropDelegate {
    let target: FileItem
    let files: [FileItem]
    let folderPath: String
    let actions: ZoneFileActions
    @Binding var hoveredPath: String?

    func validateDrop(info: DropInfo) -> Bool { info.hasItemsConforming(to: [UTType.fileURL]) }
    func dropEntered(info: DropInfo) { hoveredPath = target.path }
    func dropExited(info: DropInfo) { if hoveredPath == target.path { hoveredPath = nil } }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        hoveredPath = nil
        let copy = NSEvent.modifierFlags.contains(.option)
        let providers = info.itemProviders(for: [UTType.fileURL])
        let folder = URL(fileURLWithPath: folderPath).standardizedFileURL.path
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                var url: URL?
                if let data = item as? Data { url = URL(dataRepresentation: data, relativeTo: nil) }
                else if let u = item as? URL { url = u }
                guard let dropped = url?.standardizedFileURL else { return }
                DispatchQueue.main.async {
                    if dropped.deletingLastPathComponent().path == folder && !copy {
                        var names = files.map(\.name)
                        guard let from = names.firstIndex(of: dropped.lastPathComponent),
                              let to = names.firstIndex(of: target.name), from != to else { return }
                        let moved = names.remove(at: from)
                        names.insert(moved, at: to)
                        actions.reorder(names)
                    } else {
                        actions.acceptDrop(dropped, copy)
                    }
                }
            }
        }
        return !providers.isEmpty
    }
}

// MARK: - Icon grid

public struct ZoneIconGridView: View {
    @Environment(\.zonePalette) private var palette
    let zone: ZoneModel
    let files: [FileItem]
    @Binding var selectedFilePaths: Set<String>
    let actions: ZoneFileActions

    @State private var renamingPath: String?
    @State private var renameText = ""
    @State private var anchorPath: String?
    @State private var dropHoverPath: String?
    @FocusState private var renameFocused: Bool

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: CGFloat(zone.iconSize + 24), maximum: CGFloat(zone.iconSize + 48)),
                  spacing: CGFloat(zone.iconSpacing))]
    }

    public var body: some View {
        GeometryReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                LazyVGrid(columns: columns, spacing: CGFloat(zone.iconSpacing)) {
                    ForEach(files) { file in
                        cell(file)
                    }
                }
                .padding(10)
                // Fill the visible area so clicks on empty space land here (inside the scroll
                // content) and clear the selection; a background behind the ScrollView never got them.
                .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .top)
                .contentShape(Rectangle())
                .onTapGesture { selectedFilePaths = [] }
            }
        }
    }

    private func cell(_ file: FileItem) -> some View {
        let isSelected = selectedFilePaths.contains(file.path)
        return VStack(spacing: 4) {
            FileThumbnailView(file: file, size: CGSize(width: zone.iconSize, height: zone.iconSize))
                .frame(width: CGFloat(zone.iconSize), height: CGFloat(zone.iconSize))

            if renamingPath == file.path {
                TextField("Name", text: $renameText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: CGFloat(zone.fontSize)))
                    .multilineTextAlignment(.center)
                    .focused($renameFocused)
                    .onSubmit { commitRename(file) }
                    .onExitCommand {
                        renamingPath = nil
                        WindowManager.shared.dropDesktopKeyFocus()
                    }
                    .onAppear { renameFocused = true }
            } else {
                Text(file.name)
                    .font(.system(size: CGFloat(zone.fontSize), weight: .medium))
                    .foregroundColor(palette.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .frame(maxWidth: CGFloat(zone.iconSize + 28))
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? palette.selectionFill : (dropHoverPath == file.path ? palette.controlFillStrong : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isSelected ? palette.accent.opacity(0.8) : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .help(file.name)
        .onTapGesture(count: 2) { actions.open(file) }
        .onTapGesture { FileSelection.apply(click: file, ordered: files, selection: &selectedFilePaths, anchor: &anchorPath) }
        .contextMenu {
            FileContextMenu(file: file, files: files, selectedFilePaths: selectedFilePaths, actions: actions) {
                renameText = file.name
                renamingPath = file.path
            }
        }
        .onDrag { NSItemProvider(object: file.url as NSURL) }
        .onDrop(of: [UTType.fileURL], delegate: FileItemDropDelegate(target: file, files: files, folderPath: zone.resolvedFolderPath,
                                                                     actions: actions, hoveredPath: $dropHoverPath))
    }

    private func commitRename(_ file: FileItem) {
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        renamingPath = nil
        if !trimmed.isEmpty && trimmed != file.name { actions.rename(file, trimmed) }
        WindowManager.shared.dropDesktopKeyFocus()
    }
}

// MARK: - Thumbnail

public struct FileThumbnailView: View {
    let file: FileItem
    let size: CGSize
    @State private var image: NSImage?

    public var body: some View {
        Group {
            if let img = image ?? ThumbnailService.shared.cachedThumbnail(for: file.url, size: size, modified: file.modificationDate) {
                Image(nsImage: img)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(nsImage: NSWorkspace.shared.icon(forFile: file.path))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            }
        }
        .onAppear(perform: load)
        .onChange(of: file.modificationDate) { _ in load() }
    }

    private func load() {
        ThumbnailService.shared.thumbnail(for: file.url, size: size, modified: file.modificationDate) { thumb in
            self.image = thumb
        }
    }
}
