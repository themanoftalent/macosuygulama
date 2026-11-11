import Foundation

public struct AutoSortMove: Equatable {
    public var source: URL
    public var zoneID: UUID
    public var zoneTitle: String
    public var destinationFolder: URL
}

public struct AutoSortPlan: Equatable {
    public var moves: [AutoSortMove] = []
    /// Rule target titles that matched at least one Desktop file but have no zone.
    public var missingTargets: [String] = []
    /// Number of Desktop files matched by a rule whose zone is missing.
    public var filesWaitingForMissingZones: Int = 0
    public var isEmpty: Bool { moves.isEmpty }
}

public struct AutoSortResult: Equatable {
    public var moved: Int = 0
    public var failed: [String] = []
}

/// Routes loose Desktop files into zone folders by extension.
/// Runs only on explicit request ("Run Sort Now") or when the user enables continuous sorting.
public final class AutoSortService {
    public static let shared = AutoSortService()

    private let fileService: FileManagerService
    private var desktopMonitor: FolderMonitor?
    private var retryWorkItem: DispatchWorkItem?
    private var stateProvider: (() -> (rules: [AutoSortRule], zones: [ZoneModel]))?

    /// Files modified more recently than this are assumed to still be written (downloads, screenshots).
    public var settleInterval: TimeInterval = 4

    private static let partialExtensions: Set<String> = ["download", "crdownload", "part", "partial", "tmp", "opdownload"]

    public init(fileService: FileManagerService = .shared) {
        self.fileService = fileService
    }

    public var isMonitoring: Bool { desktopMonitor != nil }

    // MARK: - Planning

    public func resolveTarget(for rule: AutoSortRule, zones: [ZoneModel]) -> ZoneModel? {
        let candidates = zones.filter { $0.type != .app }
        if let id = rule.targetZoneID, let zone = candidates.first(where: { $0.id == id }) { return zone }
        let title = rule.targetZoneTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return nil }
        return candidates.first { $0.title.localizedCaseInsensitiveCompare(title) == .orderedSame }
    }

    public func makePlan(rules: [AutoSortRule], zones: [ZoneModel], now: Date = Date(), pinnedItemPaths: Set<String>? = nil) -> AutoSortPlan {
        var plan = AutoSortPlan()
        let desktop = fileService.desktopURL.standardizedFileURL
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey, .contentModificationDateKey, .isAliasFileKey]
        guard let items = try? FileManager.default.contentsOfDirectory(at: desktop, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else {
            return plan
        }
        var missing: [String] = []

        let effectivePinned: Set<String>
        if let explicit = pinnedItemPaths {
            effectivePinned = explicit
        } else {
            effectivePinned = Set(AppState.shared.pinnedItems.map { URL(fileURLWithPath: $0.path).standardizedFileURL.path })
        }

        for item in items {
            let stdPath = item.standardizedFileURL.path
            let resolvedPath = item.resolvingSymlinksInPath().standardizedFileURL.path
            if effectivePinned.contains(stdPath) || effectivePinned.contains(resolvedPath) {
                continue // Pinned desktop items are strictly protected and never moved by auto-sort.
            }

            guard let values = try? item.resourceValues(forKeys: Set(keys)) else { continue }
            let isPackage = values.isPackage ?? false
            if (values.isDirectory ?? false) && !isPackage { continue }
            let ext = item.pathExtension.lowercased()
            guard !ext.isEmpty, !AutoSortService.partialExtensions.contains(ext) else { continue }
            if let modified = values.contentModificationDate, now.timeIntervalSince(modified) < settleInterval { continue }

            for rule in rules where rule.isEnabled && rule.matches(extension: ext) {
                if let zone = resolveTarget(for: rule, zones: zones) {
                    let dest = URL(fileURLWithPath: zone.resolvedFolderPath, isDirectory: true).standardizedFileURL
                    // Never "sort" into the Desktop itself (e.g. a Folder Zone mirroring ~/Desktop).
                    if dest.path == desktop.path { break }
                    plan.moves.append(AutoSortMove(source: item, zoneID: zone.id, zoneTitle: zone.title, destinationFolder: dest))
                } else {
                    let title = rule.targetZoneTitle.isEmpty ? rule.name : rule.targetZoneTitle
                    if !missing.contains(where: { $0.caseInsensitiveCompare(title) == .orderedSame }) { missing.append(title) }
                    plan.filesWaitingForMissingZones += 1
                }
                break // First matching enabled rule wins.
            }
        }
        plan.missingTargets = missing
        return plan
    }

    public func execute(_ plan: AutoSortPlan) -> AutoSortResult {
        var result = AutoSortResult()
        for move in plan.moves {
            if !fileService.folderExists(move.destinationFolder.path) {
                try? FileManager.default.createDirectory(at: move.destinationFolder, withIntermediateDirectories: true)
            }
            switch fileService.transfer(move.source, toDirectory: move.destinationFolder, mode: .move, collision: .keepBoth) {
            case .success: result.moved += 1
            case .failure: result.failed.append(move.source.lastPathComponent)
            }
        }
        return result
    }

    /// Kept for API compatibility: plans and executes in one step.
    @discardableResult
    public func runAutoSort(rules: [AutoSortRule], zones: [ZoneModel], isPro: Bool) -> Int {
        guard isPro else { return 0 }
        return execute(makePlan(rules: rules, zones: zones)).moved
    }

    // MARK: - Continuous monitoring

    /// The provider is read on every change so rule and zone edits apply immediately.
    public func startMonitoring(provider: @escaping () -> (rules: [AutoSortRule], zones: [ZoneModel])) {
        stopMonitoring()
        stateProvider = provider
        let monitor = FolderMonitor(url: fileService.desktopURL)
        monitor.debounce = .milliseconds(700)
        monitor.onChange = { [weak self] in self?.sortFromMonitor() }
        monitor.start()
        desktopMonitor = monitor
        sortFromMonitor()
    }

    public func stopMonitoring() {
        retryWorkItem?.cancel()
        retryWorkItem = nil
        desktopMonitor?.stop()
        desktopMonitor = nil
        stateProvider = nil
    }

    private func sortFromMonitor() {
        guard let provider = stateProvider else { return }
        let state = provider()
        let plan = makePlan(rules: state.rules, zones: state.zones)
        if !plan.isEmpty { _ = execute(plan) }
        // Re-check shortly for files that were skipped because they were still being written.
        retryWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self, let provider = self.stateProvider else { return }
            let s = provider()
            let retry = self.makePlan(rules: s.rules, zones: s.zones)
            if !retry.isEmpty { _ = self.execute(retry) }
        }
        retryWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + settleInterval + 1, execute: work)
    }
}
