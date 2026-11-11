import SwiftUI
import AppKit

/// Uses only semantic system colours, so it follows Light, Dark and automatic appearance.
public struct HubView: View {
    @EnvironmentObject var appState: AppState

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 18) {
                    if let recovered = appState.recoveredCorruptStateFile {
                        recoveryNotice(recovered)
                    }
                    Text("Quick Actions")
                        .font(.headline)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 12) {
                        actionCard("New File Zone", icon: "folder.badge.plus", tint: .blue) { ZoneActions.createFileZone() }
                        actionCard("Folder Zone", icon: "arrow.up.right.square", tint: .purple) { ZoneActions.createFolderZone() }
                        actionCard("New App Zone", icon: "square.grid.2x2.fill", tint: .teal) { ZoneActions.createAppZone() }
                        actionCard("Pin Desktop Item", icon: "pin.fill", tint: .orange) { ZoneActions.pinDesktopItem() }
                        actionCard("Add Time", icon: "clock.fill", tint: .orange) { ZoneActions.addWidget(.clock) }
                        actionCard("Sticky Note", icon: "note.text", tint: .yellow) { ZoneActions.addWidget(.quickNote) }
                        actionCard("Auto-Align All", icon: "rectangle.3.group", tint: .green) { appState.autoAlignAllZones() }
                        actionCard("Run Auto-Sort", icon: "bolt.fill", tint: .indigo) { ZoneActions.runAutoSortInteractively() }
                        actionCard("Search Zones", icon: "magnifyingglass", tint: .pink) { WindowManager.shared.toggleGlobalSearch() }
                    }

                    Divider().padding(.vertical, 2)

                    // Pinned Desktop Items Section
                    HStack {
                        Label("Pinned Desktop Items (\(appState.pinnedItems.count))", systemImage: "pin.fill")
                            .font(.headline)
                            .foregroundColor(.primary)
                        Spacer()
                        Button("Pin Desktop Item…") { ZoneActions.pinDesktopItem() }
                            .controlSize(.small)
                        if !appState.pinnedItems.isEmpty {
                            Button("Restore Positions") { ZoneActions.restorePinnedPositions() }
                                .controlSize(.small)
                            Button("Unpin All") { DesktopPinService.shared.unpinAll() }
                                .controlSize(.small)
                        }
                    }

                    if appState.pinnedItems.isEmpty {
                        HStack(spacing: 10) {
                            Image(systemName: "pin.slash")
                                .font(.system(size: 20))
                                .foregroundColor(.secondary)
                            Text("No items pinned. Use “Pin Desktop Item…” to lock icons, files, or folders to their exact desktop coordinates.")
                                .font(.callout)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
                    } else {
                        VStack(spacing: 8) {
                            ForEach(appState.pinnedItems) { item in
                                pinnedItemRow(item)
                            }
                        }
                    }

                    Divider().padding(.vertical, 2)

                    HStack {
                        Text("Desktop Zones (\(appState.zones.count))")
                            .font(.headline)
                        Spacer()
                        Button(appState.areAllZonesHidden ? "Show All" : "Hide All") {
                            appState.areAllZonesHidden.toggle()
                        }
                        .controlSize(.small)
                        Button("Align to Grid") { appState.alignAllZonesToGrid() }
                            .controlSize(.small)
                            .help("Snap every zone's position and size to the desktop grid")
                        Button("Auto-Align") { appState.autoAlignAllZones() }
                            .controlSize(.small)
                            .help("Arrange zones in tidy rows on each display")
                    }

                    if appState.zones.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "tray")
                                .font(.system(size: 30))
                                .foregroundColor(.secondary)
                            Text("No zones yet. Use “New File Zone” above to create one.")
                                .font(.callout)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(24)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
                    } else {
                        VStack(spacing: 8) {
                            ForEach(appState.zones) { zone in
                                zoneRow(zone)
                            }
                        }
                    }
                }
                .padding(20)
            }
            Divider()
            footer
        }
        .frame(minWidth: 620, minHeight: 460)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "square.grid.2x2.fill")
                .font(.system(size: 28))
                .foregroundColor(.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text("DesktopDüzen Hub")
                        .font(.title2.weight(.bold))
                        .foregroundColor(.primary)
                    Text(appState.isPro ? "PRO" : "FREE")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        // Dark fills keep white badge text above 4.5:1 in both appearances.
                        .background(Capsule().fill(appState.isPro ? Color(red: 0.09, green: 0.47, blue: 0.20) : Color(red: 0.66, green: 0.33, blue: 0.0)))
                }
                Text("Manage your desktop zones, widgets and sorting rules")
                    .font(.callout)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button { WindowManager.shared.showSettings() } label: { Label("Settings", systemImage: "gearshape") }
        }
        .padding(18)
    }

    private var footer: some View {
        HStack {
            Text("DesktopDüzen keeps running from the menu bar. Right-click a file in a zone for more actions.")
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(2)
            Spacer()
            Button("Close Hub") { WindowManager.shared.closeHub() }
                .keyboardShortcut(.cancelAction)
                .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }

    private func recoveryNotice(_ url: URL) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text("Your previous layout file could not be read.")
                    .font(.callout.weight(.semibold))
                Text("It was kept as \(url.lastPathComponent) and a default layout was created. No files were changed.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                    .controlSize(.small)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.orange.opacity(0.12)))
    }

    private func actionCard(_ title: String, icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(tint)
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .padding(.horizontal, 8)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func zoneRow(_ zone: ZoneModel) -> some View {
        HStack(spacing: 12) {
            Image(systemName: zone.type.iconName)
                .font(.system(size: 18))
                .foregroundColor(.accentColor)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(zone.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                Text("\(zone.type.rawValue) • \(zone.viewMode.rawValue) view • \(zone.isPinnedOnTop ? "Pinned on top" : "Desktop level")")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            if zone.type != .app {
                Button("Reveal Folder") {
                    let url = URL(fileURLWithPath: zone.resolvedFolderPath)
                    if FileManager.default.fileExists(atPath: url.path) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                }
                .controlSize(.small)
            }
            Button("Style…") { WindowManager.shared.showStyleWindow(for: zone.id) }
                .controlSize(.small)
                .help("Theme, colour, transparency, text and icon size")
            Button("Show") { WindowManager.shared.focusZone(id: zone.id) }
                .controlSize(.small)
                .help("Bring this zone to the front for a few seconds")
            Button { ZoneActions.confirmDelete(id: zone.id) } label: {
                Image(systemName: "trash").foregroundColor(.red)
            }
            .buttonStyle(.borderless)
            .help("Remove zone…")
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
    }

    private func pinnedItemRow(_ item: PinnedDesktopItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "pin.fill")
                .font(.system(size: 16))
                .foregroundColor(.orange)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                Text("Locked at (\(Int(item.position.x)), \(Int(item.position.y))) • Excluded from auto-sort")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button("Show in Finder") {
                let url = URL(fileURLWithPath: item.path)
                if FileManager.default.fileExists(atPath: url.path) {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            }
            .controlSize(.small)
            Button("Unpin") {
                DesktopPinService.shared.unpinItem(id: item.id)
            }
            .controlSize(.small)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
    }
}
