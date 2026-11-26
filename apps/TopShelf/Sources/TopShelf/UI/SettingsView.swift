import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {
    private let viewModel = SettingsViewModel()

    init() {
        let contentView = SettingsView(viewModel: viewModel)
        let hosting = NSHostingController(rootView: contentView)
        let window = NSWindow(contentViewController: hosting)
        window.title = "TopShelf Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(NSSize(width: 660, height: 470))
        window.center()
        window.isReleasedWhenClosed = false
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(selectedFolderID: UUID?) {
        if let selectedFolderID {
            viewModel.selectedFolderID = selectedFolderID
            viewModel.selectedTab = .folders
        } else if viewModel.selectedFolderID == nil {
            viewModel.selectedFolderID = AppStore.shared.pinnedFolders.first?.id
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

enum SettingsTab: String, CaseIterable, Identifiable {
    case folders = "Folders"
    case general = "General"
    case about = "About"

    var id: String { rawValue }
}

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var selectedTab: SettingsTab = .folders
    @Published var selectedFolderID: UUID?
}

struct SettingsView: View {
    @ObservedObject var store = AppStore.shared
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $viewModel.selectedTab) {
                ForEach(SettingsTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 280)
            .padding(.vertical, 12)

            Divider()

            Group {
                switch viewModel.selectedTab {
                case .folders:
                    foldersTab
                case .general:
                    generalTab
                case .about:
                    AboutView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 660, height: 470)
        .onAppear {
            if viewModel.selectedFolderID == nil {
                viewModel.selectedFolderID = store.pinnedFolders.first?.id
            }
        }
    }

    private var foldersTab: some View {
        HStack(spacing: 0) {
            // Left sidebar: pinned folders list
            VStack(spacing: 0) {
                List(selection: $viewModel.selectedFolderID) {
                    ForEach(store.pinnedFolders) { folder in
                        HStack(spacing: 8) {
                            Image(systemName: folder.symbolName)
                                .foregroundStyle(folder.colorOption.swiftUIColor)
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(folder.displayName)
                                    .font(.system(size: 13, weight: .medium))
                                    .lineLimit(1)
                                Text(folder.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                        .padding(.vertical, 2)
                        .tag(folder.id)
                    }
                    .onMove { source, destination in
                        store.moveFolders(from: source, to: destination)
                    }
                }
                .listStyle(.sidebar)

                Divider()

                HStack(spacing: 4) {
                    Button {
                        store.pickAndAddFolder()
                        viewModel.selectedFolderID = store.pinnedFolders.last?.id
                    } label: {
                        Label("Add Folder", systemImage: "plus")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.borderless)
                    .padding(.leading, 8)

                    Spacer()

                    Button {
                        if let id = viewModel.selectedFolderID {
                            store.removeFolder(id: id)
                            viewModel.selectedFolderID = store.pinnedFolders.first?.id
                        }
                    } label: {
                        Image(systemName: "minus")
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.borderless)
                    .disabled(viewModel.selectedFolderID == nil)
                    .padding(.trailing, 6)
                }
                .frame(height: 32)
            }
            .frame(width: 220)

            Divider()

            // Right inspector
            if let selectedID = viewModel.selectedFolderID,
               let index = store.pinnedFolders.firstIndex(where: { $0.id == selectedID }) {
                FolderInspectorView(folder: $store.pinnedFolders[index])
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)
                    Text("No Folder Selected")
                        .font(.headline)
                    Text("Pin a folder to browse files and drag them directly from your menu bar.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 260)
                    Button("Pin a Folder…") {
                        store.pickAndAddFolder()
                        viewModel.selectedFolderID = store.pinnedFolders.last?.id
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var generalTab: some View {
        Form {
            Section("Browsing & Previews") {
                Toggle("Show Quick Look preview on hover", isOn: $store.settings.enableHoverPreview)
                Toggle("Show file extensions", isOn: $store.settings.showFileExtensions)
            }

            Section("Startup") {
                Toggle(
                    "Launch TopShelf at login",
                    isOn: Binding(
                        get: { store.settings.launchAtLogin },
                        set: { store.updateLaunchAtLogin($0) }
                    )
                )
            }

            Section("About TopShelf") {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("TopShelf • Folders in Menu Bar")
                            .font(.headline)
                        Text("Pin folders to the macOS menu bar for one-click browsing, Quick Look hover previews, and drag-and-drop.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Quit TopShelf", role: .destructive) {
                        NSApp.terminate(nil)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct FolderInspectorView: View {
    @Binding var folder: PinnedFolder

    private let symbolColumns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 8)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header & path
                HStack(spacing: 10) {
                    Image(systemName: folder.symbolName)
                        .font(.system(size: 22))
                        .foregroundStyle(folder.colorOption.swiftUIColor)
                        .frame(width: 34, height: 34)
                        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(folder.displayName)
                            .font(.headline)
                        Text(folder.path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Spacer()

                    Button("Show in Finder") {
                        NSWorkspace.shared.open(folder.url)
                    }
                    .controlSize(.small)
                }

                Divider()

                // Menu bar appearance
                VStack(alignment: .leading, spacing: 10) {
                    Text("Menu Bar Icon")
                        .font(.subheadline.weight(.semibold))

                    HStack {
                        Text("Custom Label:")
                            .font(.system(size: 12.5))
                            .foregroundStyle(.secondary)
                        TextField(
                            folder.url.lastPathComponent,
                            text: Binding(
                                get: { folder.customName ?? "" },
                                set: { folder.customName = $0.isEmpty ? nil : $0 }
                            )
                        )
                        .textFieldStyle(.roundedBorder)
                    }

                    Toggle("Show folder name next to icon in menu bar", isOn: $folder.showTitleInMenuBar)
                        .font(.system(size: 12.5))

                    // Symbol grid
                    LazyVGrid(columns: symbolColumns, spacing: 6) {
                        ForEach(PinnedFolder.curatedSymbols, id: \.self) { symbol in
                            Button {
                                folder.symbolName = symbol
                            } label: {
                                Image(systemName: symbol)
                                    .font(.system(size: 14))
                                    .foregroundStyle(
                                        folder.symbolName == symbol
                                            ? Color.white
                                            : folder.colorOption.swiftUIColor
                                    )
                                    .frame(width: 34, height: 30)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(
                                                folder.symbolName == symbol
                                                    ? Color.accentColor
                                                    : Color.primary.opacity(0.05)
                                            )
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // Color row
                    HStack(spacing: 8) {
                        Text("Color:")
                            .font(.system(size: 12.5))
                            .foregroundStyle(.secondary)

                        ForEach(IconColorOption.allCases) { option in
                            Button {
                                folder.colorOption = option
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(option == .monochrome ? Color.primary.opacity(0.75) : option.swiftUIColor)
                                        .frame(width: 18, height: 18)
                                    if folder.colorOption == option {
                                        Circle()
                                            .strokeBorder(Color.white, lineWidth: 2)
                                            .frame(width: 16, height: 16)
                                        Circle()
                                            .strokeBorder(Color.accentColor, lineWidth: 1.5)
                                            .frame(width: 22, height: 22)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .help(option.rawValue)
                        }
                    }
                    .padding(.top, 2)
                }

                Divider()

                // Sorting & Display
                VStack(alignment: .leading, spacing: 10) {
                    Text("Sorting & Display")
                        .font(.subheadline.weight(.semibold))

                    HStack(spacing: 12) {
                        Picker("Sort by", selection: $folder.sortField) {
                            ForEach(SortField.allCases) { field in
                                Text(field.rawValue).tag(field)
                            }
                        }
                        .frame(maxWidth: 210)

                        Picker("Order", selection: $folder.sortOrder) {
                            ForEach(SortOrder.allCases) { order in
                                Text(order.rawValue).tag(order)
                            }
                        }
                        .frame(maxWidth: 170)
                    }

                    HStack(spacing: 20) {
                        Toggle("Folders on top", isOn: $folder.foldersFirst)
                        Toggle("Show hidden files", isOn: $folder.showHiddenFiles)
                    }
                    .font(.system(size: 12.5))
                }
            }
            .padding(16)
        }
    }
}
