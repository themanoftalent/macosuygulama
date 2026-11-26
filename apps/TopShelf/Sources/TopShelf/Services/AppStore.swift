import AppKit
import Combine
import Foundation
import ServiceManagement

@MainActor
final class AppStore: ObservableObject {
    static let shared = AppStore()

    private let foldersKey = "topshelf.pinnedFolders.v1"
    private let settingsKey = "topshelf.settings.v1"

    @Published var pinnedFolders: [PinnedFolder] = [] {
        didSet { saveFolders() }
    }

    @Published var settings: AppSettings = AppSettings() {
        didSet { saveSettings() }
    }

    private init() {
        load()
    }

    private func load() {
        let defaults = UserDefaults.standard

        if let data = defaults.data(forKey: settingsKey),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = decoded
        }

        if let data = defaults.data(forKey: foldersKey),
           let decoded = try? JSONDecoder().decode([PinnedFolder].self, from: data) {
            pinnedFolders = decoded
        } else {
            // Seed with Desktop on first launch so the menu bar icon is immediately ready
            let home = FileManager.default.homeDirectoryForCurrentUser
            let desktop = home.appendingPathComponent("Desktop").path
            let downloads = home.appendingPathComponent("Downloads").path
            var initial: [PinnedFolder] = []
            if FileManager.default.fileExists(atPath: desktop) {
                initial.append(PinnedFolder(
                    path: desktop,
                    symbolName: "folder.fill",
                    colorOption: .monochrome
                ))
            } else if FileManager.default.fileExists(atPath: downloads) {
                initial.append(PinnedFolder(
                    path: downloads,
                    symbolName: "arrow.down.circle.fill",
                    colorOption: .monochrome
                ))
            }
            pinnedFolders = initial
        }
    }

    private func saveFolders() {
        if let data = try? JSONEncoder().encode(pinnedFolders) {
            UserDefaults.standard.set(data, forKey: foldersKey)
        }
    }

    private func saveSettings() {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: settingsKey)
        }
    }

    func addFolder(url: URL) {
        let path = url.standardizedFileURL.path
        if pinnedFolders.contains(where: { $0.path == path }) {
            return
        }
        let defaultSymbol = suggestedSymbol(for: url)
        let folder = PinnedFolder(path: path, symbolName: defaultSymbol)
        pinnedFolders.append(folder)
    }

    func removeFolder(id: UUID) {
        pinnedFolders.removeAll { $0.id == id }
    }

    func updateFolder(_ folder: PinnedFolder) {
        if let idx = pinnedFolders.firstIndex(where: { $0.id == folder.id }) {
            pinnedFolders[idx] = folder
        }
    }

    func moveFolders(from source: IndexSet, to destination: Int) {
        pinnedFolders.move(fromOffsets: source, toOffset: destination)
    }

    func updateLaunchAtLogin(_ enabled: Bool) {
        settings.launchAtLogin = enabled
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Gracefully ignore when running from swift run or unregistered bundle
        }
    }

    func pickAndAddFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Pin Folder"
        panel.message = "Choose one or more folders to pin to your menu bar."

        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK {
            for url in panel.urls {
                addFolder(url: url)
            }
        }
    }

    private func suggestedSymbol(for url: URL) -> String {
        let name = url.lastPathComponent.lowercased()
        switch name {
        case "downloads": return "arrow.down.circle.fill"
        case "desktop": return "desktopcomputer"
        case "documents": return "doc.fill"
        case "pictures", "photos": return "photo.fill"
        case "movies", "videos": return "film.fill"
        case "music": return "music.note"
        case "applications": return "shippingbox.fill"
        default: return "folder.fill"
        }
    }
}
