import SwiftUI
import AppKit
import UniformTypeIdentifiers
import QuickLookUI

public struct ZoneContentView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var controller: ZoneController
    @EnvironmentObject var store: ZoneFileStore
    let zoneID: UUID

    @ObservedObject private var wallpaper = WallpaperSampler.shared
    @State private var selectedFilePaths: Set<String> = []
    @State private var isDropTargeted = false
    @State private var banner: String?

    public init(zoneID: UUID) {
        self.zoneID = zoneID
    }

    public var body: some View {
        if let zone = appState.zone(id: zoneID) {
            let palette = ZonePalette.forZone(zone)
            let showBody = !zone.isCollapsed || controller.isHoverExpanded

            ZStack(alignment: .bottomTrailing) {
                VStack(spacing: 0) {
                    let hideHeader = appState.settings.hideTitleBarsUntilHover && !zone.isCollapsed && !controller.isPointerInside
                    ZoneHeaderView(zone: zone)
                        .background(palette.isClear ? Color.clear : palette.controlFill.opacity(0.6))
                        // Hidden until hover; the space is kept so content never jumps.
                        .opacity(hideHeader ? 0 : 1)
                        .animation(.easeInOut(duration: 0.15), value: hideHeader)

                    if let message = banner ?? store.lastError {
                        bannerView(message, palette: palette)
                    }

                    if showBody {
                        zoneBody(zone, palette: palette)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }

                if showBody && !zone.isCollapsed {
                    // Invisible corner resize area (no icon); every edge also resizes.
                    WindowResizeGrip(minSize: NSSize(width: 220, height: 120)) { frame in
                        appState.updateZoneFrame(id: zoneID, frame: frame)
                    }
                    .frame(width: 16, height: 16)
                }
            }
            .background(ZoneBackgroundView(palette: palette))
            .clipShape(RoundedRectangle(cornerRadius: CGFloat(palette.cornerRadius), style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: CGFloat(palette.cornerRadius), style: .continuous)
                    .strokeBorder(isDropTargeted ? palette.accent : (palette.showBorder ? palette.border : Color.clear),
                                  lineWidth: isDropTargeted ? 2.5 : CGFloat(palette.borderWidth))
            )
            // Clear zones: halo every label and icon so they read on any wallpaper.
            .modifier(ClearModeHalo(active: palette.isClear, lightGlow: palette.clearOnLight))
            .environment(\.zonePalette, palette)
            .environment(\.colorScheme, palette.colorScheme)
            .onDrop(of: [UTType.fileURL], isTargeted: $isDropTargeted) { providers in
                handleDrop(providers: providers, zone: zone)
            }
            .background(KeyEventHandlerView { event in handleKey(event, zone: zone) })
            .onChange(of: zone.manualOrder) { order in store.updateManualOrder(order) }
            // Clicking the desktop, another zone or another app clears this zone's selection.
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification, object: controller.panel)) { _ in
                if !selectedFilePaths.isEmpty && !QuickLookIsShowing.value { selectedFilePaths = [] }
            }
        } else {
            Color.clear
        }
    }

    // MARK: - Body

    @ViewBuilder
    private func zoneBody(_ zone: ZoneModel, palette: ZonePalette) -> some View {
        if zone.type == .app {
            if zone.apps.isEmpty {
                emptyState("Drop applications here\nor use + to add shortcuts", icon: "square.grid.2x2", palette: palette)
            } else {
                AppZoneView(zone: zone)
            }
        } else if store.folderMissing {
            missingFolderState(zone, palette: palette)
        } else if store.files.isEmpty {
            emptyState(zone.type == .file ? "Drag files here to organize them" : "This folder is empty",
                       icon: "tray.and.arrow.down", palette: palette)
        } else {
            let sorted = ZoneSorting.sorted(store.files, mode: zone.sortMode)
            if zone.viewMode == .icon {
                ZoneIconGridView(zone: zone, files: sorted, selectedFilePaths: $selectedFilePaths,
                                 actions: fileActions(for: zone))
            } else {
                ZoneListView(zone: zone, files: sorted, selectedFilePaths: $selectedFilePaths,
                             actions: fileActions(for: zone))
            }
        }
    }

    private func emptyState(_ text: String, icon: String, palette: ZonePalette) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 26, weight: .light))
                .foregroundColor(palette.secondary)
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(palette.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { selectedFilePaths = [] }
    }

    private func missingFolderState(_ zone: ZoneModel, palette: ZonePalette) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "externaldrive.badge.exclamationmark")
                .font(.system(size: 24))
                .foregroundColor(palette.secondary)
            Text("Folder not available")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(palette.primary)
            Text(zone.resolvedFolderPath)
                .font(.system(size: 10))
                .foregroundColor(palette.secondary)
                .lineLimit(2)
                .truncationMode(.middle)
                .multilineTextAlignment(.center)
            Text("It may have been renamed, deleted, or be on a disconnected drive. The zone reconnects automatically when it returns.")
                .font(.system(size: 10))
                .foregroundColor(palette.secondary)
                .multilineTextAlignment(.center)
            if zone.type == .file {
                Button("Recreate Empty Folder") {
                    try? FileManager.default.createDirectory(atPath: zone.resolvedFolderPath, withIntermediateDirectories: true)
                    store.watch(path: "", manualOrder: zone.manualOrder)
                    store.watch(path: zone.resolvedFolderPath, manualOrder: zone.manualOrder)
                }
                .controlSize(.small)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func bannerView(_ message: String, palette: ZonePalette) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            Text(message)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(palette.primary)
                .lineLimit(3)
            Spacer(minLength: 4)
            Button {
                banner = nil
                store.reportError(nil)
            } label: {
                Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundColor(palette.secondary)
            }
            .buttonStyle(.plain)
            .help("Dismiss")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(palette.controlFillStrong)
    }

    // MARK: - File actions

    private func fileActions(for zone: ZoneModel) -> ZoneFileActions {
        ZoneFileActions(
            open: { file in
                if !NSWorkspace.shared.open(file.url) { banner = "Could not open “\(file.name)”." }
            },
            rename: { file, newName in
                if case .failure(let error) = appState.fileService.renameFile(at: file.url, to: newName) {
                    banner = error.localizedDescription
                }
                store.reload()
            },
            duplicate: { file in
                if case .failure(let error) = appState.fileService.duplicateFile(at: file.url) {
                    banner = error.localizedDescription
                }
                store.reload()
            },
            trash: { files in
                let names = files.map(\.name)
                let alert = NSAlert()
                alert.messageText = files.count == 1 ? "Move “\(names[0])” to the Trash?" : "Move \(files.count) items to the Trash?"
                alert.informativeText = "You can restore items from the Trash in Finder."
                alert.addButton(withTitle: "Move to Trash")
                alert.addButton(withTitle: "Cancel")
                guard alert.runModal() == .alertFirstButtonReturn else { return }
                let failed = files.filter { !appState.fileService.trashFile(url: $0.url) }
                if !failed.isEmpty { banner = "Could not move \(failed.count) item(s) to the Trash." }
                selectedFilePaths.subtract(files.map(\.path))
                store.reload()
            },
            moveToZone: { files, target in
                let dest = URL(fileURLWithPath: target.resolvedFolderPath, isDirectory: true)
                var failures = 0
                for file in files {
                    if case .failure = appState.fileService.transfer(file.url, toDirectory: dest, mode: .move) { failures += 1 }
                }
                if failures > 0 { banner = "\(failures) item(s) could not be moved to “\(target.title)”." }
                store.reload()
            },
            reorder: { orderedNames in
                appState.mutateZone(id: zoneID) { z in
                    z.manualOrder = orderedNames
                    z.sortMode = .manual
                }
            },
            acceptDrop: { url, copy in processDroppedURL(url, zone: zone, copy: copy) },
            otherZones: appState.zones.filter { $0.id != zone.id && $0.type != .app }
        )
    }

    private func handleKey(_ event: NSEvent, zone: ZoneModel) -> Bool {
        let selected = store.files.filter { selectedFilePaths.contains($0.path) }
        switch event.keyCode {
        case 53: // Esc clears the selection
            guard !selectedFilePaths.isEmpty else { return false }
            selectedFilePaths = []
            return true
        case 49: // Space
            guard !selected.isEmpty else { return false }
            QuickLookManager.shared.togglePreview(urls: selected.map(\.url))
            return true
        case 36, 76: // Return / Enter opens, like Finder's Cmd-O
            guard !selected.isEmpty, event.modifierFlags.contains(.command) else { return false }
            selected.forEach { NSWorkspace.shared.open($0.url) }
            return true
        case 51 where event.modifierFlags.contains(.command): // Cmd-Delete
            guard !selected.isEmpty else { return false }
            fileActions(for: zone).trash(selected)
            return true
        case 0 where event.modifierFlags.contains(.command): // Cmd-A
            selectedFilePaths = Set(store.files.map(\.path))
            return true
        default:
            return false
        }
    }

    // MARK: - Drop handling

    private func handleDrop(providers: [NSItemProvider], zone: ZoneModel) -> Bool {
        let copyRequested = NSEvent.modifierFlags.contains(.option)
        var accepted = false
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            accepted = true
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                var url: URL?
                if let data = item as? Data { url = URL(dataRepresentation: data, relativeTo: nil) }
                else if let u = item as? URL { url = u }
                guard let fileURL = url else { return }
                DispatchQueue.main.async { processDroppedURL(fileURL, zone: zone, copy: copyRequested) }
            }
        }
        return accepted
    }

    private func processDroppedURL(_ url: URL, zone: ZoneModel, copy: Bool) {
        let fs = appState.fileService
        if zone.type == .app {
            guard fs.isApplication(at: url), let item = fs.resolveAppInfo(at: url.path) else {
                banner = "App Zones hold applications only. Use a File Zone for documents."
                return
            }
            appState.mutateZone(id: zone.id) { z in
                if !z.apps.contains(where: { $0.path == item.path }) {
                    var app = item
                    app.order = z.apps.count
                    z.apps.append(app)
                }
            }
            return
        }
        let dest = URL(fileURLWithPath: zone.resolvedFolderPath, isDirectory: true)
        // Like Finder: move within a volume, copy across volumes, Option forces a copy.
        let mode: TransferMode = (copy || !fs.isSameVolume(url, dest)) ? .copy : .move
        switch fs.transfer(url, toDirectory: dest, mode: mode, collision: .keepBoth) {
        case .success:
            store.reload()
        case .failure(let error):
            banner = error.localizedDescription
        }
    }
}

// MARK: - Shared helpers

/// Quick Look takes key status from the zone; keep the selection while its panel is up.
enum QuickLookIsShowing {
    static var value: Bool { QLPreviewPanel.sharedPreviewPanelExists() && (QLPreviewPanel.shared()?.isVisible ?? false) }
}

/// Always the same view structure; only the shadow strength changes. Switching between two
/// different structures (if/else) replaced the whole zone subtree when the opacity slider
/// crossed the clear-mode threshold, which reset the header and closed the style popover.
struct ClearModeHalo: ViewModifier {
    let active: Bool
    /// Dark text on a light wallpaper gets a light glow; light text gets a dark shadow.
    var lightGlow: Bool = false
    func body(content: Content) -> some View {
        let halo = lightGlow ? Color.white : Color.black
        return content
            .shadow(color: halo.opacity(active ? 0.9 : 0), radius: active ? 1.0 : 0, x: 0, y: active ? 0.5 : 0)
            .shadow(color: halo.opacity(active ? 0.6 : 0), radius: active ? 3.0 : 0, x: 0, y: active ? 1 : 0)
    }
}

public struct ZoneFileActions {
    public var open: (FileItem) -> Void
    public var rename: (FileItem, String) -> Void
    public var duplicate: (FileItem) -> Void
    public var trash: ([FileItem]) -> Void
    public var moveToZone: ([FileItem], ZoneModel) -> Void
    public var reorder: ([String]) -> Void
    /// Handles a file dropped onto an item that does not come from this zone.
    public var acceptDrop: (URL, Bool) -> Void
    public var otherZones: [ZoneModel]
}

public enum ZoneSorting {
    public static func sorted(_ input: [FileItem], mode: ZoneSortMode) -> [FileItem] {
        let byName: (FileItem, FileItem) -> Bool = { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        switch mode {
        case .manual:
            return input.sorted { $0.manualOrder != $1.manualOrder ? $0.manualOrder < $1.manualOrder : byName($0, $1) }
        case .nameAsc: return input.sorted(by: byName)
        case .nameDesc: return input.sorted { byName($1, $0) }
        case .dateDesc: return input.sorted { $0.modificationDate != $1.modificationDate ? $0.modificationDate > $1.modificationDate : byName($0, $1) }
        case .dateAsc: return input.sorted { $0.modificationDate != $1.modificationDate ? $0.modificationDate < $1.modificationDate : byName($0, $1) }
        case .sizeDesc: return input.sorted { $0.size != $1.size ? $0.size > $1.size : byName($0, $1) }
        case .sizeAsc: return input.sorted { $0.size != $1.size ? $0.size < $1.size : byName($0, $1) }
        case .kind:
            return input.sorted {
                let c = $0.kindDescription.localizedCaseInsensitiveCompare($1.kindDescription)
                return c == .orderedSame ? byName($0, $1) : c == .orderedAscending
            }
        }
    }
}

// MARK: - NSVisualEffectView bridge

public struct VisualEffectBlur: NSViewRepresentable {
    public var material: NSVisualEffectView.Material
    public var appearance: NSAppearance?
    public var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    public init(material: NSVisualEffectView.Material, appearance: NSAppearance? = nil,
                blendingMode: NSVisualEffectView.BlendingMode = .behindWindow) {
        self.material = material
        self.appearance = appearance
        self.blendingMode = blendingMode
    }

    public func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.state = .active
        updateNSView(view, context: context)
        return view
    }

    public func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        if nsView.material != material { nsView.material = material }
        if nsView.blendingMode != blendingMode { nsView.blendingMode = blendingMode }
        // Forcing the appearance keeps the blur light or dark to match the tint, regardless of
        // the system appearance, so the computed text colour stays valid.
        if nsView.appearance?.name != appearance?.name { nsView.appearance = appearance }
    }
}

// MARK: - Key handling

public struct KeyEventHandlerView: NSViewRepresentable {
    public var onKeyDown: (NSEvent) -> Bool

    public func makeNSView(context: Context) -> KeyView {
        let view = KeyView()
        view.onKeyDown = onKeyDown
        return view
    }

    public func updateNSView(_ nsView: KeyView, context: Context) {
        nsView.onKeyDown = onKeyDown
    }

    public final class KeyView: NSView {
        public var onKeyDown: ((NSEvent) -> Bool)?
        private var monitor: Any?

        public override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor = monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
            guard window != nil else { return }
            // A local monitor scoped to this window: works whichever subview is first responder,
            // but never steals keys from text fields that are editing.
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self = self, let window = self.window, event.window === window else { return event }
                if window.firstResponder is NSText { return event }
                let handled = self.onKeyDown?(event) ?? false
                if handled { return nil }
                // If a zone panel held key status and receives an unhandled shortcut (e.g. Cmd-Shift-E),
                // surrender key focus back to the frontmost app and forward the keystroke.
                // Only while another app is frontmost: when DesktopDüzen itself is active, dropping focus
                // is a no-op, so a re-posted key would come straight back here in an endless loop, and
                // menu shortcuts (Cmd-Q, Cmd-,) must reach the menu. Posting also needs Accessibility
                // permission; without it the key would be silently lost, so leave it alone.
                if let panel = window as? DesktopPanel, panel.isKeyWindow, !NSApp.isActive, AXIsProcessTrusted(),
                   let cgEvent = event.cgEvent?.copy() {
                    WindowManager.shared.dropDesktopKeyFocus()
                    guard !panel.isKeyWindow else { return event }
                    cgEvent.post(tap: .cghidEventTap)
                    return nil
                }
                return event
            }
        }

        public override func removeFromSuperview() {
            if let monitor = monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
            super.removeFromSuperview()
        }

        deinit {
            if let monitor = monitor { NSEvent.removeMonitor(monitor) }
        }
    }
}
