import SwiftUI
import AppKit
import UniformTypeIdentifiers

public struct ZoneListView: View {
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

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()

    public var body: some View {
        GeometryReader { geo in
            let showKind = geo.size.width > 380
            let showDate = geo.size.width > 300
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    header("Name").frame(maxWidth: .infinity, alignment: .leading)
                    if showDate { header("Date Modified").frame(width: 96, alignment: .trailing) }
                    if showKind { header("Kind").frame(width: 70, alignment: .leading) }
                    header("Size").frame(width: 56, alignment: .trailing)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
                .background(palette.controlFill)

                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(spacing: 1) {
                        ForEach(files) { file in
                            row(file, showDate: showDate, showKind: showKind)
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, minHeight: max(0, geo.size.height - 24), alignment: .top)
                    .contentShape(Rectangle())
                    .onTapGesture { selectedFilePaths = [] }
                }
            }
        }
    }

    private func header(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(palette.secondary)
            .lineLimit(1)
    }

    private func row(_ file: FileItem, showDate: Bool, showKind: Bool) -> some View {
        let isSelected = selectedFilePaths.contains(file.path)
        return HStack(spacing: 8) {
            FileThumbnailView(file: file, size: CGSize(width: 18, height: 18))
                .frame(width: 18, height: 18)

            if renamingPath == file.path {
                TextField("Name", text: $renameText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: CGFloat(zone.fontSize)))
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
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if showDate {
                Text(file.modificationDate == .distantPast ? "--" : Self.dateFormatter.string(from: file.modificationDate))
                    .font(.system(size: 10))
                    .foregroundColor(palette.secondary)
                    .frame(width: 96, alignment: .trailing)
                    .lineLimit(1)
            }
            if showKind {
                Text(file.kindDescription)
                    .font(.system(size: 10))
                    .foregroundColor(palette.secondary)
                    .frame(width: 70, alignment: .leading)
                    .lineLimit(1)
            }
            Text(file.formattedSize)
                .font(.system(size: 10).monospacedDigit())
                .foregroundColor(palette.secondary)
                .frame(width: 56, alignment: .trailing)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(isSelected ? palette.selectionFill : (dropHoverPath == file.path ? palette.controlFillStrong : Color.clear))
        )
        .contentShape(Rectangle())
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
