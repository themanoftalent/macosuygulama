import SwiftUI
import AppKit

public struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab: SettingsTab = .general
    @State private var exportedJSON = ""
    @State private var isExportPresented = false
    @State private var isImportPresented = false
    @State private var importJSONText = ""
    @State private var importError = false
    @State private var loginItemMessage: String?
    @State private var loginItemEnabled = LaunchAtLoginService.shared.isEnabled

    enum SettingsTab: String, CaseIterable, Identifiable {
        case general = "General"
        case zones = "Zones"
        case autoSort = "Auto-Sort"
        case proLicense = "Pro & License"
        case about = "About"

        var id: String { rawValue }
        var iconName: String {
            switch self {
            case .general: return "gearshape"
            case .zones: return "square.grid.2x2"
            case .autoSort: return "tray.full"
            case .proLicense: return "crown"
            case .about: return "info.circle"
            }
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedTab) {
                ForEach(SettingsTab.allCases) { tab in
                    Label(tab.rawValue, systemImage: tab.iconName).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(12)

            Divider()

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 16) {
                    switch selectedTab {
                    case .general: generalTab
                    case .zones: zonesTab
                    case .autoSort: autoSortTab
                    case .proLicense: proTab
                    case .about: aboutTab
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
        }
        .frame(minWidth: 660, minHeight: 460)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text).font(.headline).foregroundColor(.primary)
    }

    private func caption(_ text: String) -> some View {
        Text(text).font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - General

    @ViewBuilder
    private var generalTab: some View {
        sectionTitle("Startup")
        Toggle("Launch DesktopDüzen at login", isOn: Binding(
            get: { loginItemEnabled },
            set: { value in
                loginItemMessage = LaunchAtLoginService.shared.setEnabled(value)
                loginItemEnabled = LaunchAtLoginService.shared.isEnabled
                appState.settings.launchAtLogin = loginItemEnabled
            }
        ))
        if let message = loginItemMessage {
            Label { Text(message).font(.caption).foregroundColor(.primary) } icon: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.red)
            }
        } else if loginItemEnabled {
            caption("Registered as: \(LaunchAtLoginService.shared.currentMethod.rawValue)")
        }
        Toggle("Show the Hub window when DesktopDüzen starts", isOn: $appState.settings.showHubOnLaunch)
        Toggle("Show DesktopDüzen in the Dock", isOn: $appState.settings.showDockIcon)
        caption("Off: DesktopDüzen runs from the menu bar only and stays out of the Dock and Cmd-Tab. Zones keep working either way.")

        Divider()
        sectionTitle("Windows & Spaces")
        Toggle("Show zones on all Spaces", isOn: $appState.settings.showZonesOnAllSpaces)
        Toggle("Hide zone title bars until the pointer is over a zone", isOn: $appState.settings.hideTitleBarsUntilHover)
        Toggle("Zones take keyboard focus when clicked", isOn: $appState.settings.zonesTakeKeyboardFocus)
        caption("Off: your keyboard shortcuts keep going to the app you are using, even after clicking a zone. On: Space (Quick Look), Esc, Cmd-A and Cmd-Delete work in a zone after you click it.")
        caption("When off, each zone stays on the Space where it was created. Zones never appear over full-screen apps.")

        Divider()
        sectionTitle("Alignment & Snapping")
        Toggle("Snap zones while dragging", isOn: $appState.settings.alignmentMode)
        Toggle("Snap to grid", isOn: $appState.settings.snapToGrid)
            .disabled(!appState.settings.alignmentMode)
        HStack {
            Text("Grid size")
                .frame(width: 110, alignment: .leading)
            Slider(value: $appState.settings.gridSize, in: 10...40, step: 5)
            Text("\(Int(appState.settings.gridSize)) px")
                .monospacedDigit()
                .foregroundColor(.secondary)
                .frame(width: 50, alignment: .trailing)
        }
        .disabled(!appState.settings.alignmentMode || !appState.settings.snapToGrid)
        Toggle("Snap to neighbouring zone edges", isOn: $appState.settings.snapToNeighbors)
            .disabled(!appState.settings.alignmentMode)

        Divider()
        sectionTitle("Desktop Icons")
        Toggle("Hide Finder icons on the Desktop", isOn: Binding(
            get: { appState.settings.hideLooseDesktopIcons },
            set: { ZoneActions.setDesktopIconsHidden($0) }
        ))
        caption("Only hides the icons Finder draws; no files are moved. Finder restarts briefly when this changes.")
    }

    // MARK: - Zones

    @ViewBuilder
    private var zonesTab: some View {
        HStack {
            sectionTitle("Zones (\(appState.zones.count))")
            Spacer()
            Button("Align to Grid") { appState.alignAllZonesToGrid() }
            Button("Auto-Align All") { appState.autoAlignAllZones() }
        }
        ForEach(appState.zones) { zone in
            HStack(spacing: 12) {
                Image(systemName: zone.type.iconName)
                    .foregroundColor(.accentColor)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(zone.title).font(.system(size: 12, weight: .semibold)).foregroundColor(.primary)
                    Text(zone.type == .app ? "\(zone.apps.count) app(s)" : zone.resolvedFolderPath)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Button("Style…") { WindowManager.shared.showStyleWindow(for: zone.id) }.controlSize(.small)
                Button("Show") { WindowManager.shared.focusZone(id: zone.id) }.controlSize(.small)
                Button("Rename…") { ZoneActions.renameZone(id: zone.id) }.controlSize(.small)
                Button { ZoneActions.confirmDelete(id: zone.id) } label: {
                    Image(systemName: "trash").foregroundColor(.red)
                }
                .buttonStyle(.borderless)
                .help("Remove zone…")
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
            transparencyRow(zone)
        }
        HStack(spacing: 10) {
            Button("New File Zone…") { ZoneActions.createFileZone() }.buttonStyle(.borderedProminent)
            Button("New Folder Zone…") { ZoneActions.createFolderZone() }
            Button("New App Zone…") { ZoneActions.createAppZone() }
        }
        .padding(.top, 4)
    }

    private func transparencyRow(_ zone: ZoneModel) -> some View {
        let opacity = zone.customBackgroundOpacity ?? ThemePresets.theme(for: zone.themeID).backgroundOpacity
        return HStack(spacing: 10) {
            Text("Background")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 70, alignment: .leading)
            Slider(value: Binding(
                get: { opacity },
                set: { v in appState.mutateZone(id: zone.id) { $0.customBackgroundOpacity = v } }
            ), in: 0...1, step: 0.05)
            Text(opacity <= 0.001 ? "Clear" : "\(Int((opacity * 100).rounded()))%")
                .font(.caption.monospacedDigit())
                .foregroundColor(.secondary)
                .frame(width: 40, alignment: .trailing)
            Toggle("Border", isOn: Binding(get: { zone.showBorder }, set: { v in appState.mutateZone(id: zone.id) { $0.showBorder = v } }))
                .toggleStyle(.checkbox).font(.caption)
            Toggle("Shadow", isOn: Binding(get: { zone.showShadow }, set: { v in appState.mutateZone(id: zone.id) { $0.showShadow = v } }))
                .toggleStyle(.checkbox).font(.caption)
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
    }

    // MARK: - Auto-Sort

    @ViewBuilder
    private var autoSortTab: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                sectionTitle("Auto-Sort Rules")
                caption("Moves loose files from ~/Desktop into a zone's folder by file extension. You see what will move before anything happens. Files are never overwritten.")
            }
            Spacer()
            Button("Run Sort Now…") { ZoneActions.runAutoSortInteractively() }
                .buttonStyle(.borderedProminent)
        }
        Toggle("Sort new Desktop files automatically", isOn: Binding(
            get: { appState.settings.autoSortEnabled },
            set: { ZoneActions.setContinuousAutoSort($0) }
        ))
        caption("Only moves files into zones that already exist, and waits until a file has finished saving.")

        Divider()

        ForEach($appState.autoSortRules) { $rule in
            RuleEditorRow(rule: $rule, zones: appState.zones.filter { $0.type != .app }) {
                appState.autoSortRules.removeAll { $0.id == rule.id }
            }
        }
        HStack {
            Button("Add Rule") {
                appState.autoSortRules.append(AutoSortRule(name: "New Rule", targetZoneTitle: appState.zones.first(where: { $0.type == .file })?.title ?? "", targetZoneID: appState.zones.first(where: { $0.type == .file })?.id, extensions: []))
            }
            Button("Restore Default Rules") { appState.autoSortRules = AutoSortRule.defaultRules }
        }
    }

    // MARK: - Pro

    @ViewBuilder
    private var proTab: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                sectionTitle("License")
                Text(appState.isPro ? "All features unlocked (\(appState.license.activePlan?.rawValue ?? "Lifetime"))" : "Free tier (up to 3 zones)")
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button(appState.isPro ? "Plans…" : "Upgrade…") { WindowManager.shared.showPaywall() }
                .buttonStyle(.borderedProminent)
        }
        Toggle("Pro features enabled (testing switch)", isOn: Binding(
            get: { appState.isPro },
            set: { value in
                appState.license.isPro = value
                appState.license.isMockProActive = value
                if !value { ZoneActions.setContinuousAutoSort(false) }
            }
        ))

        Divider()
        sectionTitle("Layout Backup")
        caption("Exports zone positions, themes, rules and settings as JSON. Files inside zones are not included.")
        HStack(spacing: 12) {
            Button("Export Layout…") {
                exportedJSON = appState.exportConfigurationJSON() ?? ""
                isExportPresented = true
            }
            Button("Import Layout…") {
                importJSONText = ""
                isImportPresented = true
            }
        }
        .sheet(isPresented: $isExportPresented) { exportSheet }
        .sheet(isPresented: $isImportPresented) { importSheet }
    }

    private var exportSheet: some View {
        VStack(spacing: 12) {
            Text("Exported Layout").font(.headline)
            TextEditor(text: .constant(exportedJSON))
                .font(.system(size: 11, design: .monospaced))
                .border(Color(nsColor: .separatorColor))
            HStack {
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(exportedJSON, forType: .string)
                }
                Button("Save As…") {
                    let panel = NSSavePanel()
                    panel.nameFieldStringValue = "DesktopDuzen-Layout.json"
                    panel.allowedContentTypes = [.json]
                    if panel.runModal() == .OK, let url = panel.url {
                        try? exportedJSON.write(to: url, atomically: true, encoding: .utf8)
                    }
                }
                Spacer()
                Button("Done") { isExportPresented = false }.keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 520, height: 380)
    }

    private var importSheet: some View {
        VStack(spacing: 12) {
            Text("Import Layout").font(.headline)
            Text("Paste exported JSON or open a file. This replaces the current layout; files on disk are not changed.")
                .font(.caption)
                .foregroundColor(.secondary)
            TextEditor(text: $importJSONText)
                .font(.system(size: 11, design: .monospaced))
                .border(Color(nsColor: .separatorColor))
            HStack {
                Button("Open File…") {
                    let panel = NSOpenPanel()
                    panel.allowedContentTypes = [.json]
                    if panel.runModal() == .OK, let url = panel.url, let text = try? String(contentsOf: url, encoding: .utf8) {
                        importJSONText = text
                    }
                }
                Spacer()
                Button("Cancel") { isImportPresented = false }.keyboardShortcut(.cancelAction)
                Button("Import") {
                    if appState.importConfigurationJSON(importJSONText) {
                        isImportPresented = false
                    } else {
                        importError = true
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 520, height: 380)
        .alert("This is not a DesktopDüzen layout.", isPresented: $importError) {
            Button("OK", role: .cancel) {}
        }
    }

    // MARK: - About

    @ViewBuilder
    private var aboutTab: some View {
        AboutView()
            .frame(maxWidth: .infinity)
        HStack {
            Spacer()
            Button("Show Layout File in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([appState.stateFileURL])
            }
            .controlSize(.small)
            Spacer()
        }
    }
}

/// One editable auto-sort rule.
struct RuleEditorRow: View {
    @Binding var rule: AutoSortRule
    let zones: [ZoneModel]
    let onDelete: () -> Void
    @State private var extensionsText = ""

    private var targetMissing: Bool { AutoSortService.shared.resolveTarget(for: rule, zones: zones) == nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Toggle("", isOn: $rule.isEnabled).labelsHidden()
                TextField("Rule name", text: $rule.name)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 170)
                Picker("Zone", selection: Binding<String>(
                    get: { AutoSortService.shared.resolveTarget(for: rule, zones: zones)?.id.uuidString ?? "missing" },
                    set: { value in
                        if let zone = zones.first(where: { $0.id.uuidString == value }) {
                            rule.targetZoneID = zone.id
                            rule.targetZoneTitle = zone.title
                        }
                    }
                )) {
                    if targetMissing {
                        Text("“\(rule.targetZoneTitle)” (no such zone)").tag("missing")
                    }
                    ForEach(zones) { zone in Text(zone.title).tag(zone.id.uuidString) }
                }
                .frame(maxWidth: 240)
                Spacer()
                Button(action: onDelete) { Image(systemName: "minus.circle") }
                    .buttonStyle(.borderless)
                    .help("Delete rule")
            }
            HStack {
                Text("Extensions").font(.caption).foregroundColor(.secondary).frame(width: 70, alignment: .leading)
                TextField("png, jpg, pdf", text: $extensionsText, onCommit: commitExtensions)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, design: .monospaced))
                    .onChange(of: extensionsText) { _ in commitExtensions() }
            }
            if targetMissing && rule.isEnabled {
                Label {
                    Text("No zone named “\(rule.targetZoneTitle)”. Pick a zone, or let Run Sort Now create it.")
                        .font(.caption)
                        .foregroundColor(.primary)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
        .onAppear { extensionsText = rule.extensions.joined(separator: ", ") }
    }

    private func commitExtensions() {
        let parsed = AutoSortRule.parseExtensions(extensionsText)
        if parsed != rule.extensions { rule.extensions = parsed }
    }
}
