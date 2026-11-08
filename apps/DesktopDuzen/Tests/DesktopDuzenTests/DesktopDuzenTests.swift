import XCTest
import AppKit
@testable import DesktopDuzen

/// Every test runs against a throw-away Desktop, Application Support folder and Trash.
/// Earlier tests created AppState instances that wrote starter folders into the real
/// ~/Desktop/Zones on every run ("Active Projects 1…8"); that cannot happen here.
class SandboxedTestCase: XCTestCase {
    var root: URL!
    var desktop: URL!
    var storage: URL!
    var trash: URL!
    var fs: FileManagerService!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("DDTests-\(UUID().uuidString)", isDirectory: true)
        desktop = root.appendingPathComponent("Desktop", isDirectory: true)
        storage = root.appendingPathComponent("Support", isDirectory: true)
        trash = root.appendingPathComponent("Trash", isDirectory: true)
        for dir in [desktop!, storage!, trash!] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        fs = FileManagerService(desktopURL: desktop)
        let trashDir = trash!
        fs.trashHandler = { url in
            let dest = trashDir.appendingPathComponent("\(UUID().uuidString)-\(url.lastPathComponent)")
            try FileManager.default.moveItem(at: url, to: dest)
        }
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func makeState(createStarter: Bool = true) -> AppState {
        AppState(customStorageURL: storage, fileService: fs, createStarterContent: createStarter)
    }

    @discardableResult
    func write(_ name: String, in dir: URL, contents: String = "x", age: TimeInterval = 60) throws -> URL {
        let url = dir.appendingPathComponent(name)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        let date = Date().addingTimeInterval(-age)
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
        return url
    }

    func names(in dir: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).filter { !$0.hasPrefix(".") }.sorted()
    }
}

// MARK: - Persistence

final class PersistenceTests: SandboxedTestCase {
    func testStarterDataIsIdempotentAndNeverDuplicatesFolders() throws {
        _ = makeState()
        // Simulate a lost/reset state file and several relaunches.
        for _ in 0..<5 {
            try FileManager.default.removeItem(at: storage.appendingPathComponent("state.json"))
            _ = makeState()
        }
        XCTAssertEqual(names(in: fs.zonesBaseURL), ["Active Projects", "Downloads & Media"])
        XCTAssertEqual(names(in: fs.zonesBaseURL.appendingPathComponent("Active Projects")), ["Welcome to DesktopDüzen.txt"])
    }

    func testExistingStateIsLoadedWithoutCreatingFolders() throws {
        let first = makeState()
        first.zones[0].title = "Renamed In Memory"
        XCTAssertTrue(first.saveState())
        let before = names(in: fs.zonesBaseURL)
        let second = makeState()
        XCTAssertEqual(second.zones.first?.title, "Renamed In Memory")
        XCTAssertEqual(names(in: fs.zonesBaseURL), before)
    }

    func testLegacyStateFileFromVersion1Decodes() throws {
        // Shape of the state.json written by build 371 (no version key, no custom colours, old Finder path).
        let legacy = """
        {"stickers":[],"license":{"activePlan":"Lifetime","isMockProActive":true,"isPro":true},
         "widgets":[{"title":"Desktop Clock","id":"23403662-1920-411F-9F39-EC6862779FF5","type":"Clock & Date","isDigitalClock":true,"noteColorHex":"#FFE066","frame":[[60,970],[220,110]],"noteContent":"n"}],
         "autoSortRules":[{"name":"Images & Screenshots","targetZoneTitle":"Media & Images","id":"580147F3-2FE2-4FF8-BC91-F37EAB81F40B","extensions":["png","JPG",".jpeg"],"isEnabled":true}],
         "settings":{"snapThreshold":14,"showZonesOnAllSpaces":true,"globalHotkeyEnabled":true,"gridSize":15,"snapToNeighbors":true,"autoSortEnabled":false,"launchAtLogin":false,"hideLooseDesktopIcons":false,"hasCompletedOnboarding":true,"alignmentMode":true,"snapToGrid":true},
         "zones":[
          {"viewMode":"Icon","isPinnedOnTop":false,"autoExpandOnHover":false,"collapsedHeight":42,"expandedHeight":260,"fontSize":11.5,"isCollapsed":false,"apps":[],"displayID":0,"type":"File Zone","tabs":[],"backingFolderPath":"/tmp/x","iconSpacing":12,"iconSize":52,"title":"Active Projects","sortMode":"Manual (Drag to Sort)","createdAt":815716880.448509,"id":"CF747EB0-A075-43A1-A2C0-24AD5B6C2F06","manualOrder":[],"themeID":"glass_blur","frame":[[60,1090],[340,260]]},
          {"viewMode":"Icon","type":"App Zone","apps":[{"name":"Finder","bundleID":"","path":"/System/Applications/Finder.app","id":"35D28460-F06C-411C-83B7-9FB06810CABE","order":0}],"title":"Quick Launcher","id":"7DA40913-8C1B-4ABA-86E5-6122E2A5B330","themeID":"light_frost","frame":[[390,825],[340,260]]},
          {"title":"Broken zone without id"},
          {"viewMode":"NotARealMode","title":"Bad enum","id":"E94DA6F1-C733-4403-AA37-713E9167C41F","frame":"garbage"}
         ]}
        """
        try legacy.write(to: storage.appendingPathComponent("state.json"), atomically: true, encoding: .utf8)
        let state = makeState()
        XCTAssertNil(state.recoveredCorruptStateFile)
        XCTAssertEqual(state.zones.map(\.title), ["Active Projects", "Quick Launcher", "Bad enum"])
        XCTAssertEqual(state.zones[2].viewMode, .icon, "invalid enum falls back to default")
        XCTAssertEqual(state.zones[2].frame.width, 340, "invalid frame falls back to default")
        XCTAssertEqual(state.zones[1].apps.first?.path, "/System/Library/CoreServices/Finder.app", "legacy Finder path migrated")
        XCTAssertEqual(state.settings.gridSize, 15)
        XCTAssertTrue(state.settings.showHubOnLaunch, "new setting gets its default")
        XCTAssertEqual(state.autoSortRules.first?.extensions, ["png", "jpg", "jpeg"], "extensions normalised")
        XCTAssertEqual(state.widgets.count, 1)
        XCTAssertTrue(names(in: desktop).isEmpty, "loading must not create folders")
    }

    func testCorruptStateIsPreservedNotOverwritten() throws {
        let garbage = "{ this is not json"
        try garbage.write(to: storage.appendingPathComponent("state.json"), atomically: true, encoding: .utf8)
        let state = makeState(createStarter: false)
        let backup = try XCTUnwrap(state.recoveredCorruptStateFile)
        XCTAssertEqual(try String(contentsOf: backup, encoding: .utf8), garbage)
        XCTAssertTrue(FileManager.default.fileExists(atPath: storage.appendingPathComponent("state.json").path))
    }

    func testDuplicateZoneIDsAreDroppedOnLoad() throws {
        let state = makeState(createStarter: false)
        let zone = ZoneModel(title: "Twice")
        state.zones = [zone, zone]
        state.saveState()
        XCTAssertEqual(makeState(createStarter: false).zones.count, 1)
    }

    func testExportImportRoundTripAndRejectsForeignJSON() throws {
        let a = makeState(createStarter: false)
        a.zones = [ZoneModel(title: "Alpha", customBackgroundHex: "#FFFFFF", customBackgroundOpacity: 0.8)]
        let json = try XCTUnwrap(a.exportConfigurationJSON())

        try FileManager.default.removeItem(at: storage.appendingPathComponent("state.json"))
        let b = makeState(createStarter: false)
        XCTAssertTrue(b.importConfigurationJSON(json))
        XCTAssertEqual(b.zones.map(\.title), ["Alpha"])
        XCTAssertEqual(b.zones.first?.customBackgroundHex, "#FFFFFF")
        XCTAssertFalse(b.importConfigurationJSON("{\"hello\": 1}"))
        XCTAssertFalse(b.importConfigurationJSON("not json"))
        XCTAssertEqual(b.zones.map(\.title), ["Alpha"], "failed import leaves layout untouched")
    }

    func testZoneSanitizeRepairsUnusableFrames() {
        var z = ZoneModel(title: "Bad", frame: CGRect(x: CGFloat.nan, y: 0, width: 10, height: 5), isCollapsed: false, expandedHeight: 20)
        z.sanitize()
        XCTAssertTrue(z.frame.origin.x.isFinite)
        XCTAssertGreaterThanOrEqual(z.frame.width, 200)
        XCTAssertGreaterThanOrEqual(z.frame.height, 120)
    }

    func testFrameUpdateAndCollapsedHeightPersist() throws {
        let state = makeState(createStarter: false)
        let zone = try XCTUnwrap(state.createDefaultFileZone(title: "Work"))
        state.updateZoneFrame(id: zone.id, frame: CGRect(x: 111.4, y: 222.6, width: 400, height: 300))
        state.saveState()
        let reloaded = makeState(createStarter: false)
        let z = try XCTUnwrap(reloaded.zone(id: zone.id))
        XCTAssertEqual(z.frame, CGRect(x: 111.4, y: 222.6, width: 400, height: 300).integral)
        XCTAssertEqual(z.expandedHeight, z.frame.height)
    }
}

// MARK: - File safety

final class FileSafetyTests: SandboxedTestCase {
    func testMoveKeepsBothOnCollision() throws {
        let dest = desktop.appendingPathComponent("Dest", isDirectory: true)
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        let src = try write("document.txt", in: desktop, contents: "new")
        try write("document.txt", in: dest, contents: "old")
        let moved = try fs.transfer(src, toDirectory: dest, mode: .move).get()
        XCTAssertEqual(moved.lastPathComponent, "document 1.txt")
        XCTAssertEqual(try String(contentsOf: dest.appendingPathComponent("document.txt"), encoding: .utf8), "old")
        XCTAssertEqual(try String(contentsOf: moved, encoding: .utf8), "new")
    }

    func testCopyModeLeavesSource() throws {
        let dest = desktop.appendingPathComponent("Dest", isDirectory: true)
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        let src = try write("a.txt", in: desktop)
        _ = try fs.transfer(src, toDirectory: dest, mode: .copy).get()
        XCTAssertTrue(FileManager.default.fileExists(atPath: src.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dest.appendingPathComponent("a.txt").path))
    }

    func testCannotMoveFolderIntoItself() throws {
        let folder = desktop.appendingPathComponent("F", isDirectory: true)
        let inner = folder.appendingPathComponent("Inner", isDirectory: true)
        try FileManager.default.createDirectory(at: inner, withIntermediateDirectories: true)
        guard case .failure(.intoItself) = fs.transfer(folder, toDirectory: inner, mode: .move) else {
            return XCTFail("expected intoItself")
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: inner.path))
    }

    func testMissingDestinationFailsWithoutLosingSource() throws {
        let src = try write("keep.txt", in: desktop)
        let result = fs.transfer(src, toDirectory: desktop.appendingPathComponent("Nope"), mode: .move)
        guard case .failure(.destinationMissing) = result else { return XCTFail("expected destinationMissing") }
        XCTAssertTrue(FileManager.default.fileExists(atPath: src.path))
    }

    func testDuplicateCopiesInsteadOfRenaming() throws {
        let src = try write("report.pdf", in: desktop, contents: "pdf")
        let copy = try fs.duplicateFile(at: src).get()
        let copy2 = try fs.duplicateFile(at: src).get()
        XCTAssertEqual(copy.lastPathComponent, "report copy.pdf")
        XCTAssertEqual(copy2.lastPathComponent, "report copy 2.pdf")
        XCTAssertTrue(FileManager.default.fileExists(atPath: src.path), "original must remain")
    }

    func testRenameRejectsClashesAndInvalidNames() throws {
        let a = try write("a.txt", in: desktop)
        try write("b.txt", in: desktop)
        guard case .failure(.nameExists) = fs.renameFile(at: a, to: "b.txt") else { return XCTFail() }
        guard case .failure(.invalidName) = fs.renameFile(at: a, to: "x/y") else { return XCTFail() }
        guard case .failure(.invalidName) = fs.renameFile(at: a, to: "   ") else { return XCTFail() }
        XCTAssertEqual(try fs.renameFile(at: a, to: "c.txt").get().lastPathComponent, "c.txt")
    }

    func testDeleteZoneMovesFilesBackAndTrashesOnlyEmptyFolder() throws {
        let state = makeState(createStarter: false)
        let zone = try XCTUnwrap(state.createDefaultFileZone(title: "Temp"))
        let folder = URL(fileURLWithPath: zone.backingFolderPath)
        try write("one.txt", in: folder)
        try write("clash.txt", in: folder, contents: "zone")
        try write("clash.txt", in: desktop, contents: "desktop")

        let result = state.deleteZone(id: zone.id, action: .moveFilesToDesktop)
        XCTAssertEqual(result.movedCount, 2)
        XCTAssertTrue(result.failedNames.isEmpty)
        XCTAssertTrue(result.folderRemoved)
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
        XCTAssertEqual(try String(contentsOf: desktop.appendingPathComponent("clash.txt"), encoding: .utf8), "desktop")
        XCTAssertTrue(FileManager.default.fileExists(atPath: desktop.appendingPathComponent("clash 1.txt").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: desktop.appendingPathComponent("one.txt").path))
        XCTAssertFalse(state.zones.contains { $0.id == zone.id })
    }

    func testDeleteZoneUnbindAndTrashAreRecoverable() throws {
        let state = makeState(createStarter: false)
        let keep = try XCTUnwrap(state.createDefaultFileZone(title: "Keep"))
        try write("k.txt", in: URL(fileURLWithPath: keep.backingFolderPath))
        state.deleteZone(id: keep.id, action: .unbindOnly)
        XCTAssertTrue(FileManager.default.fileExists(atPath: keep.backingFolderPath + "/k.txt"))

        let trashed = try XCTUnwrap(state.createDefaultFileZone(title: "Bin"))
        try write("t.txt", in: URL(fileURLWithPath: trashed.backingFolderPath))
        state.deleteZone(id: trashed.id, action: .moveToTrash)
        XCTAssertFalse(FileManager.default.fileExists(atPath: trashed.backingFolderPath))
        XCTAssertEqual(names(in: trash).count, 1, "folder went to (test) Trash, not deleted")
    }

    func testDeletingFolderZoneNeverTouchesTheFolder() throws {
        let state = makeState(createStarter: false)
        let external = root.appendingPathComponent("Projects", isDirectory: true)
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
        try write("important.txt", in: external)
        let zone = state.createFolderZone(title: "Projects", folderURL: external)
        state.deleteZone(id: zone.id, action: .moveToTrash)
        XCTAssertTrue(FileManager.default.fileExists(atPath: external.appendingPathComponent("important.txt").path))
    }

    func testRenameZoneRenamesFolderAndHandlesClash() throws {
        let state = makeState(createStarter: false)
        let a = try XCTUnwrap(state.createDefaultFileZone(title: "A"))
        _ = try XCTUnwrap(state.createDefaultFileZone(title: "B"))
        state.renameZone(id: a.id, newTitle: "B")
        XCTAssertEqual(URL(fileURLWithPath: try XCTUnwrap(state.zone(id: a.id)).backingFolderPath).lastPathComponent, "B 1")
        state.renameZone(id: a.id, newTitle: "b 1")
        XCTAssertEqual(URL(fileURLWithPath: try XCTUnwrap(state.zone(id: a.id)).backingFolderPath).lastPathComponent, "b 1", "case-only rename")
    }

    func testFolderNameSanitization() {
        XCTAssertEqual(fs.sanitizeFolderName("Test / Zone: 1?"), "Test - Zone- 1-")
        XCTAssertEqual(fs.sanitizeFolderName("   "), "Zone")
        XCTAssertEqual(fs.sanitizeFolderName("..hidden"), "hidden")
    }
}

// MARK: - Auto-sort

final class AutoSortTests: SandboxedTestCase {
    func testPlanSkipsFoldersPartialAndFreshFilesAndReportsMissingZones() throws {
        let state = makeState(createStarter: false)
        let media = try XCTUnwrap(state.createDefaultFileZone(title: "Media & Images"))
        try write("photo.PNG", in: desktop)
        try write("paper.pdf", in: desktop)
        try write("movie.mp4.crdownload", in: desktop)
        try write("just-saved.jpg", in: desktop, age: 0)
        try FileManager.default.createDirectory(at: desktop.appendingPathComponent("Folder.png"), withIntermediateDirectories: true)

        let service = AutoSortService(fileService: fs)
        let plan = service.makePlan(rules: AutoSortRule.defaultRules, zones: state.zones)
        XCTAssertEqual(plan.moves.map { $0.source.lastPathComponent }, ["photo.PNG"])
        XCTAssertEqual(plan.moves.first?.zoneID, media.id)
        XCTAssertEqual(plan.missingTargets, ["Documents"])
        XCTAssertEqual(plan.filesWaitingForMissingZones, 1)

        let result = service.execute(plan)
        XCTAssertEqual(result.moved, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: media.backingFolderPath + "/photo.PNG"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: desktop.appendingPathComponent("paper.pdf").path), "no zone, no move")
    }

    func testTargetByIDSurvivesZoneRenameAndNeverOverwrites() throws {
        let state = makeState(createStarter: false)
        let zone = try XCTUnwrap(state.createDefaultFileZone(title: "Docs"))
        try write("a.pdf", in: URL(fileURLWithPath: zone.backingFolderPath), contents: "existing")
        try write("a.pdf", in: desktop, contents: "incoming")
        state.renameZone(id: zone.id, newTitle: "Papers")
        let rule = AutoSortRule(name: "PDF", targetZoneTitle: "Docs", targetZoneID: zone.id, extensions: ["pdf"])
        let service = AutoSortService(fileService: fs)
        let result = service.execute(service.makePlan(rules: [rule], zones: state.zones))
        XCTAssertEqual(result.moved, 1)
        let folder = URL(fileURLWithPath: try XCTUnwrap(state.zone(id: zone.id)).backingFolderPath)
        XCTAssertEqual(names(in: folder), ["a 1.pdf", "a.pdf"])
        XCTAssertEqual(try String(contentsOf: folder.appendingPathComponent("a.pdf"), encoding: .utf8), "existing")
    }

    func testNeverSortsIntoTheDesktopItself() throws {
        let state = makeState(createStarter: false)
        let zone = state.createFolderZone(title: "Desk", folderURL: desktop)
        try write("x.png", in: desktop)
        let rule = AutoSortRule(name: "img", targetZoneTitle: "Desk", targetZoneID: zone.id, extensions: ["png"])
        XCTAssertTrue(AutoSortService(fileService: fs).makePlan(rules: [rule], zones: state.zones).isEmpty)
    }

    func testDisabledRulesAndAppZonesAreIgnored() throws {
        let state = makeState(createStarter: false)
        state.createAppZone(title: "Media & Images", initialApps: [AppItem(name: "X", path: "/Applications/X.app")])
        try write("x.png", in: desktop)
        var rules = AutoSortRule.defaultRules
        let service = AutoSortService(fileService: fs)
        XCTAssertTrue(service.makePlan(rules: rules, zones: state.zones).isEmpty, "app zones are not file targets")
        _ = try XCTUnwrap(state.createDefaultFileZone(title: "Media & Images"))
        rules[0].isEnabled = false
        XCTAssertTrue(service.makePlan(rules: rules, zones: state.zones).isEmpty)
    }

    func testExtensionParsing() {
        XCTAssertEqual(AutoSortRule.parseExtensions(" .PNG, jpg;;gif  png"), ["png", "jpg", "gif"])
    }
}

// MARK: - Contrast

final class ContrastTests: XCTestCase {
    func testEveryThemeMeetsWCAGAAForAllTextRoles() {
        for theme in ThemePresets.allThemes {
            let p = ZonePalette.make(theme: theme)
            XCTAssertGreaterThanOrEqual(p.primaryContrast, 4.5, "\(theme.name) primary")
            XCTAssertGreaterThanOrEqual(p.secondaryContrast, 4.5, "\(theme.name) secondary")
            XCTAssertGreaterThanOrEqual(p.titleContrast, 4.5, "\(theme.name) title")
        }
    }

    func testLightThemeUsesDarkTextAndDarkThemeUsesLightText() {
        XCTAssertFalse(ZonePalette.make(theme: ThemePresets.lightFrost).isDark)
        XCTAssertLessThan(ZonePalette.make(theme: ThemePresets.lightFrost).primaryRGB.relativeLuminance, 0.1)
        XCTAssertTrue(ZonePalette.make(theme: ThemePresets.darkFrost).isDark)
        XCTAssertEqual(ZonePalette.make(theme: ThemePresets.darkFrost).primaryRGB, .white)
        XCTAssertEqual(ZonePalette.make(theme: ThemePresets.lightFrost).colorScheme, .light)
    }

    func testArbitraryCustomBackgroundsStayReadable() {
        var generator = SystemRandomNumberGenerator()
        let pureColours = ["#FFFFFF", "#000000", "#808080", "#777777", "#FFFF00", "#00FFFF", "#FF0000", "#0000FF", "#00FF00", "#FF00FF"]
        var samples = pureColours.map { ($0, 0.35) } + pureColours.map { ($0, 1.0) }
        for _ in 0..<500 {
            let hex = String(format: "#%02X%02X%02X", Int.random(in: 0...255, using: &generator),
                             Int.random(in: 0...255, using: &generator), Int.random(in: 0...255, using: &generator))
            samples.append((hex, Double.random(in: 0.35...1.0, using: &generator)))
        }
        for (hex, opacity) in samples {
            let p = ZonePalette.make(theme: ThemePresets.minimalWireframe, customHex: hex, customOpacity: opacity)
            XCTAssertGreaterThanOrEqual(p.primaryContrast, 4.5, "\(hex) @ \(opacity)")
            XCTAssertGreaterThanOrEqual(p.secondaryContrast, 4.5, "\(hex) @ \(opacity) secondary")
            XCTAssertGreaterThanOrEqual(p.titleContrast, 4.5, "\(hex) @ \(opacity) title")
        }
    }

    func testHexParsing() {
        XCTAssertEqual(RGBAColor(hex: "#FFF"), .white)
        XCTAssertEqual(RGBAColor(hex: "000000"), .black)
        XCTAssertEqual(RGBAColor(hex: "#FFFFFF33").a, 0.2, accuracy: 0.001)
        XCTAssertEqual(RGBAColor(hex: "zz"), .black)
        XCTAssertEqual(RGBAColor(hex: "#12AB9F").hexString, "#12AB9F")
    }

    func testThemePresets() {
        XCTAssertGreaterThanOrEqual(ThemePresets.allThemes.count, 11)
        XCTAssertEqual(ThemePresets.theme(for: "non_existent").id, ThemePresets.glassBlur.id)
        XCTAssertEqual(Set(ThemePresets.allThemes.map(\.id)).count, ThemePresets.allThemes.count, "theme ids unique")
    }
}

// MARK: - Snapping and sorting

final class LayoutTests: XCTestCase {
    func testSnapToNeighbourEdges() {
        var settings = AppSettings()
        settings.snapToGrid = false
        let other = NSRect(x: 400, y: 100, width: 300, height: 200)
        let snapped = Snapping.snap(NSRect(x: 405, y: 105, width: 300, height: 200), otherFrames: [other], settings: settings)
        XCTAssertEqual(snapped.origin, CGPoint(x: 400, y: 100))
    }

    func testGridSnapAndDisabledAlignment() {
        var settings = AppSettings(gridSize: 20)
        settings.snapToNeighbors = false
        XCTAssertEqual(Snapping.snap(NSRect(x: 47, y: 31, width: 10, height: 10), otherFrames: [], settings: settings).origin, CGPoint(x: 40, y: 40))
        settings.alignmentMode = false
        XCTAssertEqual(Snapping.snap(NSRect(x: 47, y: 31, width: 10, height: 10), otherFrames: [], settings: settings).origin, CGPoint(x: 47, y: 31))
    }

    func testSortingIsStableAndManualOrderRespected() {
        let base = Date()
        let files = [
            FileItem(name: "b.txt", url: URL(fileURLWithPath: "/t/b.txt"), size: 2, modificationDate: base, manualOrder: 1),
            FileItem(name: "a10.txt", url: URL(fileURLWithPath: "/t/a10.txt"), size: 2, modificationDate: base, manualOrder: Int.max),
            FileItem(name: "a2.txt", url: URL(fileURLWithPath: "/t/a2.txt"), size: 1, modificationDate: base.addingTimeInterval(-5), manualOrder: 0)
        ]
        XCTAssertEqual(ZoneSorting.sorted(files, mode: .manual).map(\.name), ["a2.txt", "b.txt", "a10.txt"])
        XCTAssertEqual(ZoneSorting.sorted(files, mode: .nameAsc).map(\.name), ["a2.txt", "a10.txt", "b.txt"], "Finder-style numeric sort")
        XCTAssertEqual(ZoneSorting.sorted(files, mode: .sizeDesc).map(\.name), ["a10.txt", "b.txt", "a2.txt"])
    }

    func testZoneModelTabsAndPaths() {
        var zone = ZoneModel(type: .file, title: "Work", backingFolderPath: "/z/Work")
        XCTAssertEqual(zone.resolvedFolderPath, "/z/Work")
        let t1 = ZoneTab(title: "Active"), t2 = ZoneTab(title: "Archive")
        zone.tabs = [t1, t2]
        zone.activeTabID = t2.id
        XCTAssertEqual(zone.resolvedFolderPath, "/z/Work/Archive")
        zone.tabs = [t1]
        zone.sanitize()
        XCTAssertEqual(zone.activeTabID, t1.id, "dangling active tab repaired")
    }

    func testProEntitlements() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let fs = FileManagerService(desktopURL: dir.appendingPathComponent("Desktop"))
        let state = AppState(customStorageURL: dir, fileService: fs, createStarterContent: false)
        state.license = LicenseStatus(isPro: false, activePlan: nil, isMockProActive: false)
        state.zones = [ZoneModel(title: "1"), ZoneModel(title: "2"), ZoneModel(title: "3")]
        XCTAssertFalse(state.canAddZone())
        XCTAssertFalse(state.canUseTheme(ThemePresets.cyberpunkNeon))
        state.license.isPro = true
        XCTAssertTrue(state.canAddZone())
        XCTAssertTrue(state.canPinOnTop())
    }
}

// MARK: - Live folder updates

final class LiveUpdateTests: SandboxedTestCase {
    func testFolderMonitorReportsChanges() throws {
        let monitor = FolderMonitor(url: desktop)
        let changed = expectation(description: "change")
        changed.assertForOverFulfill = false
        monitor.onChange = { changed.fulfill() }
        XCTAssertTrue(monitor.start())
        try write("new.txt", in: desktop)
        wait(for: [changed], timeout: 3)
        monitor.stop()
    }

    func testFolderMonitorStartFailsGracefullyForMissingFolder() {
        XCTAssertFalse(FolderMonitor(url: desktop.appendingPathComponent("missing")).start())
    }

    func testZoneFileStoreTracksAddRenameDeleteAndMissingFolder() throws {
        let folder = desktop.appendingPathComponent("Zone", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let store = ZoneFileStore(fileService: fs)
        store.watch(path: folder.path, manualOrder: [])

        func waitUntil(_ timeout: TimeInterval = 6, _ condition: @escaping () -> Bool) {
            let deadline = Date().addingTimeInterval(timeout)
            while !condition() && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        }

        let file = try write("a.txt", in: folder)
        waitUntil { store.files.map(\.name) == ["a.txt"] }
        XCTAssertEqual(store.files.map(\.name), ["a.txt"])

        try FileManager.default.moveItem(at: file, to: folder.appendingPathComponent("b.txt"))
        waitUntil { store.files.map(\.name) == ["b.txt"] }
        XCTAssertEqual(store.files.map(\.name), ["b.txt"])

        try FileManager.default.removeItem(at: folder)
        waitUntil { store.folderMissing }
        XCTAssertTrue(store.folderMissing, "deleted/ejected folder detected")

        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try write("c.txt", in: folder)
        waitUntil(8) { !store.folderMissing && store.files.map(\.name) == ["c.txt"] }
        XCTAssertFalse(store.folderMissing, "reconnects when the folder returns")
        XCTAssertEqual(store.files.map(\.name), ["c.txt"])
        store.stop()
    }

    func testManyFilesListQuickly() throws {
        let folder = desktop.appendingPathComponent("Big", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for i in 0..<2000 { FileManager.default.createFile(atPath: folder.appendingPathComponent("f\(i).txt").path, contents: Data()) }
        let start = Date()
        let items = fs.contentsOfFolder(path: folder.path)
        XCTAssertEqual(items.count, 2000)
        XCTAssertLessThan(Date().timeIntervalSince(start), 2.0)
    }

    func testRepeatedZoneCreateDeleteIsStable() throws {
        let state = makeState(createStarter: false)
        for i in 0..<150 {
            let z = try XCTUnwrap(state.createDefaultFileZone(title: "Z\(i % 5)"))
            state.deleteZone(id: z.id, action: .moveFilesToDesktop)
        }
        XCTAssertTrue(state.zones.allSatisfy { $0.type == .app }, "only the starter app zone remains")
        XCTAssertEqual(names(in: fs.zonesBaseURL), [], "empty zone folders cleaned up via (test) Trash")
    }
}

final class DragSmoothnessTests: XCTestCase {
    /// Regression: live drag positions must follow the pointer 1:1 (no grid stepping),
    /// so moving 1 px at a time never jumps by a grid cell.
    func testLiveDragDoesNotGridStep() {
        let settings = AppSettings(gridSize: 15)
        var previous = Snapping.snap(NSRect(x: 100, y: 100, width: 300, height: 200), otherFrames: [], settings: settings, includeGrid: false)
        for step in 1...40 {
            let r = Snapping.snap(NSRect(x: 100 + CGFloat(step), y: 100, width: 300, height: 200), otherFrames: [], settings: settings, includeGrid: false)
            XCTAssertEqual(r.origin.x - previous.origin.x, 1, accuracy: 0.001)
            previous = r
        }
        let settled = Snapping.snap(NSRect(x: 107, y: 100, width: 300, height: 200), otherFrames: [], settings: settings, includeGrid: true)
        XCTAssertEqual(settled.origin.x, 105, "grid applied on release")
    }
}

final class ThemeLibraryTests: XCTestCase {
    func testLibraryHasLiquidGlassAndValidCategories() {
        XCTAssertGreaterThanOrEqual(ThemePresets.allThemes.count, 27)
        XCTAssertGreaterThanOrEqual(ThemePresets.allThemes.filter { $0.category == "Liquid Glass" }.count, 7)
        for theme in ThemePresets.allThemes {
            XCTAssertTrue(ThemePresets.categoryOrder.contains(theme.category), "\(theme.name) category shown in picker")
        }
    }

    func testGradientAndSheenAreCheckedOnEveryStop() {
        for theme in ThemePresets.allThemes where theme.gradientHexes.count >= 2 || theme.sheen > 0 {
            let p = ZonePalette.make(theme: theme)
            let expected = theme.tintStops.count + (theme.sheen > 0 ? 1 : 0)
            XCTAssertEqual(p.backgrounds.count, expected, theme.name)
            XCTAssertGreaterThanOrEqual(p.primaryContrast, 4.5, "\(theme.name) worst stop")
            XCTAssertGreaterThanOrEqual(p.accentContrast, 3.0, "\(theme.name) accent")
        }
    }

    func testLiquidClearUsesDarkTextOnLightGlass() {
        let p = ZonePalette.make(theme: ThemePresets.liquidClear)
        XCTAssertEqual(p.primaryRGB, .black)
        XCTAssertTrue(p.glassHighlight)
    }

    func testCustomColourDisablesSheenAndGradient() {
        let p = ZonePalette.make(theme: ThemePresets.liquidAqua, customHex: "#FFFFFF", customOpacity: 0.5)
        XCTAssertEqual(p.stops.count, 1)
        XCTAssertEqual(p.sheen, 0)
        XCTAssertFalse(p.glassHighlight)
    }
}

final class ThemeSafetyNetTests: XCTestCase {
    /// A deliberately hostile theme (mid-tone gradient + strong sheen) must still end up legible.
    func testUnreadableGradientIsCorrectedAutomatically() {
        let hostile = ZoneTheme(id: "x", name: "Hostile", backgroundHex: "#777777", backgroundOpacity: 0.3,
                                gradientHexes: ["#3A8FD0", "#777777", "#B04070"], sheen: 0.35, glassHighlight: true)
        let p = ZonePalette.make(theme: hostile)
        XCTAssertGreaterThanOrEqual(p.primaryContrast, 4.5)
        XCTAssertGreaterThanOrEqual(p.secondaryContrast, 4.5)
        XCTAssertGreaterThanOrEqual(p.titleContrast, 4.5)
    }
}

final class ClearModeTests: XCTestCase {
    func testZeroOpacityIsAllowedAndUsesClearMode() {
        var zone = ZoneModel(title: "Clear", customBackgroundOpacity: 0, showBorder: false, showShadow: false)
        zone.sanitize()
        XCTAssertEqual(zone.customBackgroundOpacity, 0, "0 % must survive sanitize (it was clamped to 35 % before)")
        let p = ZonePalette.forZone(zone)
        XCTAssertTrue(p.isClear)
        XCTAssertEqual(p.tintOpacity, 0)
        XCTAssertEqual(p.primaryRGB, .white)
        XCTAssertFalse(p.showBorder)
        XCTAssertFalse(p.glassHighlight)
    }

    func testAboveThresholdStaysContrastManaged() {
        let p = ZonePalette.forZone(ZoneModel(title: "Solid", themeID: "liquid_clear", customBackgroundOpacity: 0.6))
        XCTAssertFalse(p.isClear)
        XCTAssertGreaterThanOrEqual(p.primaryContrast, 4.5)
    }

    func testOlderLayoutsDefaultToBorderAndShadow() throws {
        let json = #"{"id":"CF747EB0-A075-43A1-A2C0-24AD5B6C2F06","title":"Old"}"#
        let zone = try JSONDecoder().decode(ZoneModel.self, from: Data(json.utf8))
        XCTAssertTrue(zone.showBorder)
        XCTAssertTrue(zone.showShadow)
    }
}

final class ZoneTitleTests: XCTestCase {
    func testInitials() {
        XCTAssertEqual(ZoneTitle.initials("Quick Launcher"), "QL")
        XCTAssertEqual(ZoneTitle.initials("Downloads & Media"), "DM")
        XCTAssertEqual(ZoneTitle.initials("  active   projects "), "AP")
        XCTAssertEqual(ZoneTitle.initials("Makale Çalışmaları"), "MÇ")
        XCTAssertEqual(ZoneTitle.initials("ışık işler"), "Iİ", "Turkish casing: ı -> I, i -> İ")
        XCTAssertEqual(ZoneTitle.initials("One Two Three Four Five"), "OTTF")
        XCTAssertNil(ZoneTitle.initials("Documents"))
        XCTAssertNil(ZoneTitle.initials(""))
    }
}

final class WidgetThemeTests: XCTestCase {
    func testOldWidgetsKeepOriginalLookAndNewOnesAreReadable() throws {
        let json = #"{"id":"23403662-1920-411F-9F39-EC6862779FF5","type":"Clock & Date","title":"Desktop Clock","frame":[[60,970],[220,110]]}"#
        let old = try JSONDecoder().decode(DesktopWidget.self, from: Data(json.utf8))
        XCTAssertEqual(old.themeID, "dark_frost")
        XCTAssertNil(old.backgroundOpacity)
        XCTAssertTrue(old.showBorder)
        for theme in ThemePresets.allThemes {
            let p = ZonePalette.forWidget(DesktopWidget(type: .clock, themeID: theme.id))
            XCTAssertGreaterThanOrEqual(p.titleContrast, 4.5, theme.name)
            XCTAssertGreaterThanOrEqual(p.secondaryContrast, 4.5, theme.name)
        }
        XCTAssertTrue(ZonePalette.forWidget(DesktopWidget(type: .clock, backgroundOpacity: 0)).isClear)
    }

    func testWidgetStyleRoundTrips() throws {
        let w = DesktopWidget(type: .calendar, themeID: "liquid_aqua", backgroundOpacity: 0.5, showBorder: false)
        let back = try JSONDecoder().decode(DesktopWidget.self, from: JSONEncoder().encode(w))
        XCTAssertEqual(back.themeID, "liquid_aqua")
        XCTAssertEqual(back.backgroundOpacity, 0.5)
        XCTAssertFalse(back.showBorder)
    }
}

final class WidgetSingletonTests: SandboxedTestCase {
    func testClockCannotBeAddedTwiceButNotesCan() {
        let state = makeState(createStarter: false)
        state.widgets = []
        let first = state.addWidget(DesktopWidget(type: .clock))
        XCTAssertTrue(first.added)
        for _ in 0..<10 {
            let again = state.addWidget(DesktopWidget(type: .clock))
            XCTAssertFalse(again.added)
            XCTAssertEqual(again.id, first.id, "returns the existing clock")
        }
        XCTAssertTrue(state.addWidget(DesktopWidget(type: .calendar)).added)
        XCTAssertFalse(state.addWidget(DesktopWidget(type: .calendar)).added)
        XCTAssertTrue(state.addWidget(DesktopWidget(type: .quickNote)).added)
        XCTAssertTrue(state.addWidget(DesktopWidget(type: .quickNote)).added, "multiple sticky notes allowed")
        XCTAssertEqual(state.widgets.filter { $0.type == .clock }.count, 1)
        XCTAssertEqual(state.widgets.count, 4)
    }

    func testDuplicateClocksInSavedLayoutAreMergedOnLoad() {
        let state = makeState(createStarter: false)
        state.widgets = [DesktopWidget(type: .clock, title: "A"), DesktopWidget(type: .clock, title: "B"),
                         DesktopWidget(type: .quickNote), DesktopWidget(type: .quickNote), DesktopWidget(type: .clock, title: "C")]
        state.saveState()
        let reloaded = makeState(createStarter: false)
        XCTAssertEqual(reloaded.widgets.filter { $0.type == .clock }.map(\.title), ["A"], "keeps the first clock")
        XCTAssertEqual(reloaded.widgets.filter { $0.type == .quickNote }.count, 2)
    }
}

final class SelectionTests: XCTestCase {
    func testClickingTheSelectedItemAgainDeselectsIt() {
        let a = FileItem(name: "a", url: URL(fileURLWithPath: "/t/a"))
        let b = FileItem(name: "b", url: URL(fileURLWithPath: "/t/b"))
        var selection = Set<String>()
        var anchor: String?
        FileSelection.apply(click: a, ordered: [a, b], selection: &selection, anchor: &anchor)
        XCTAssertEqual(selection, [a.path])
        FileSelection.apply(click: b, ordered: [a, b], selection: &selection, anchor: &anchor)
        XCTAssertEqual(selection, [b.path], "plain click moves the selection")
        FileSelection.apply(click: b, ordered: [a, b], selection: &selection, anchor: &anchor)
        XCTAssertTrue(selection.isEmpty, "second click on the same item clears it")
    }

    func testEightPointTextIsAllowed() {
        var z = ZoneModel(title: "Z", fontSize: 8)
        z.sanitize()
        XCTAssertEqual(z.fontSize, 8)
    }
}

final class AlignmentTests: SandboxedTestCase {
    private func state(with frames: [CGRect], screens: [CGRect]) -> AppState {
        let s = makeState(createStarter: false)
        s.settings.gridSize = 20
        s.screenFramesProvider = { screens }
        s.zones = frames.enumerated().map { ZoneModel(title: "Z\($0.offset)", frame: $0.element, expandedHeight: $0.element.height) }
        return s
    }

    func testAlignToGridSnapsWithoutRearranging() {
        let screen = CGRect(x: 0, y: 0, width: 1600, height: 1000)
        let s = state(with: [CGRect(x: 103, y: 607, width: 347, height: 261), CGRect(x: 812, y: 211, width: 300, height: 300)], screens: [screen])
        s.alignAllZonesToGrid()
        for z in s.zones {
            XCTAssertEqual(z.frame.minX.truncatingRemainder(dividingBy: 20), 0, "\(z.title) x on grid")
            XCTAssertEqual(z.frame.maxY.truncatingRemainder(dividingBy: 20), 0, "\(z.title) top on grid")
            XCTAssertEqual(z.frame.width.truncatingRemainder(dividingBy: 20), 0)
            XCTAssertEqual(z.frame.height.truncatingRemainder(dividingBy: 20), 0)
        }
        XCTAssertEqual(s.zones[0].frame.minX, 100, "stays near where it was")
        XCTAssertLessThan(s.zones[0].frame.minX, s.zones[1].frame.minX, "order preserved")
    }

    func testAutoAlignKeepsZonesOnTheirOwnDisplay() {
        let main = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let second = CGRect(x: 1440, y: 0, width: 1920, height: 1080)
        let s = state(with: [CGRect(x: 300, y: 300, width: 340, height: 260),
                             CGRect(x: 2000, y: 400, width: 340, height: 260),
                             CGRect(x: 2600, y: 200, width: 340, height: 260)], screens: [main, second])
        s.autoAlignAllZones()
        XCTAssertTrue(main.contains(s.zones[0].frame), "zone stays on main display")
        XCTAssertTrue(second.contains(s.zones[1].frame), "zone stays on second display")
        XCTAssertTrue(second.contains(s.zones[2].frame))
        XCTAssertFalse(s.zones[1].frame.intersects(s.zones[2].frame), "no overlap")
        for z in s.zones { XCTAssertEqual(z.frame.minX.truncatingRemainder(dividingBy: 20), 0) }
    }
}

final class WallpaperContrastTests: XCTestCase {
    func testClearZoneTextFollowsWallpaperBrightness() {
        let onWhite = ZonePalette.clear(theme: ThemePresets.glassBlur, customHex: nil, opacity: 0, behindLuminance: 1.0)
        XCTAssertTrue(onWhite.clearOnLight)
        XCTAssertEqual(onWhite.primaryRGB, .black, "white wallpaper -> black text")
        XCTAssertEqual(onWhite.titleRGB, .black)

        let onBlack = ZonePalette.clear(theme: ThemePresets.glassBlur, customHex: nil, opacity: 0, behindLuminance: 0.02)
        XCTAssertFalse(onBlack.clearOnLight)
        XCTAssertEqual(onBlack.primaryRGB, .white, "dark wallpaper -> white text")

        let unknown = ZonePalette.clear(theme: ThemePresets.glassBlur, customHex: nil, opacity: 0, behindLuminance: nil)
        XCTAssertEqual(unknown.primaryRGB, .white, "until the wallpaper is known, white text with a shadow")
    }

    func testChosenTextColourAlwaysHasTheHigherContrast() {
        for i in 0...100 {
            let l = Double(i) / 100
            let p = ZonePalette.clear(theme: ThemePresets.glassBlur, customHex: nil, opacity: 0, behindLuminance: l)
            let bg = RGBAColor(r: 0, g: 0, b: 0) // contrast only depends on luminance; build a grey with luminance l
            _ = bg
            let chosen = (p.primaryRGB.relativeLuminance + 0.05)
            let blackContrast = (l + 0.05) / 0.05
            let whiteContrast = 1.05 / (l + 0.05)
            let best = max(blackContrast, whiteContrast)
            let actual = p.primaryRGB == .black ? blackContrast : whiteContrast
            XCTAssertEqual(actual, best, accuracy: 0.0001, "luminance \(l)")
            XCTAssertGreaterThanOrEqual(actual, 4.58, "luminance \(l) chosen \(chosen)")
        }
    }

    func testRegionAveragingUsesTopDownRows() {
        // 2x2 grid: top row black, bottom row white. Screen 0...100 x 0...100 (AppKit, y up).
        let grid = [0.0, 0.0, 1.0, 1.0]
        let screen = CGRect(x: 0, y: 0, width: 100, height: 100)
        let top = WallpaperSampler.average(grid, width: 2, height: 2, screenFrame: screen, rect: CGRect(x: 0, y: 60, width: 100, height: 40))
        let bottom = WallpaperSampler.average(grid, width: 2, height: 2, screenFrame: screen, rect: CGRect(x: 0, y: 0, width: 100, height: 40))
        XCTAssertEqual(top, 0.0, "upper half of the screen is the first grid row")
        XCTAssertEqual(bottom, 1.0)
        XCTAssertNil(WallpaperSampler.average(grid, width: 2, height: 2, screenFrame: screen, rect: CGRect(x: 500, y: 500, width: 10, height: 10)))
    }
}

final class WallpaperStoreTests: XCTestCase {
    private func store(provider: String, config: [String: Any]? = nil, files: [Any] = [], uuid: String = "D1") -> [String: Any] {
        var choice: [String: Any] = ["Provider": provider, "Files": files]
        if let config = config {
            choice["Configuration"] = try! PropertyListSerialization.data(fromPropertyList: config, format: .binary, options: 0)
        }
        return ["Displays": [uuid: ["Linked": ["Content": ["Choices": [choice]]]]]]
    }

    func testSolidSystemColours() {
        let black = store(provider: "com.apple.wallpaper.choice.color", config: ["type": "systemColor", "systemColor": ["black": [String: Any]()]])
        XCTAssertEqual(WallpaperSampler.source(inStore: black, displayUUID: "D1"), .solid(0))
        let white = store(provider: "com.apple.wallpaper.choice.color", config: ["type": "systemColor", "systemColor": ["white": [String: Any]()]])
        XCTAssertEqual(WallpaperSampler.source(inStore: white, displayUUID: "D1"), .solid(1))
    }

    func testCustomColourComponents() {
        let s = store(provider: "com.apple.wallpaper.choice.color", config: ["type": "rgb", "color": ["red": 1.0, "green": 1.0, "blue": 0.9]])
        guard case .solid(let l)? = WallpaperSampler.source(inStore: s, displayUUID: "D1") else { return XCTFail() }
        XCTAssertTrue(ZonePalette.prefersDarkText(onLuminance: l), "pale yellow wallpaper -> black text")
    }

    func testImageAndFallbacks() {
        let img = store(provider: "com.apple.wallpaper.choice.image", files: [["relative": "file:///Users/x/Pictures/beach.jpg"]])
        XCTAssertEqual(WallpaperSampler.source(inStore: img, displayUUID: "D1"), .image(URL(fileURLWithPath: "/Users/x/Pictures/beach.jpg")))
        XCTAssertNil(WallpaperSampler.source(inStore: store(provider: "com.apple.wallpaper.choice.aerials"), displayUUID: "D1"), "aerials: unknown")
        // Unknown display falls back to SystemDefault.
        var withDefault = store(provider: "com.apple.wallpaper.choice.color", config: ["type": "systemColor", "systemColor": ["white": [String: Any]()]], uuid: "OTHER")
        withDefault["SystemDefault"] = ["Linked": ["Content": ["Choices": [["Provider": "com.apple.wallpaper.choice.color",
            "Configuration": try! PropertyListSerialization.data(fromPropertyList: ["type": "systemColor", "systemColor": ["black": [String: Any]()]], format: .binary, options: 0)]]]]]
        XCTAssertEqual(WallpaperSampler.source(inStore: withDefault, displayUUID: "D1"), .solid(0))
    }
}

final class HoverTitleTests: XCTestCase {
    func testHoverTitlesDefaultOnAndPersist() throws {
        XCTAssertTrue(AppSettings().hideTitleBarsUntilHover)
        let old = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"gridSize":15}"#.utf8))
        XCTAssertTrue(old.hideTitleBarsUntilHover, "existing users get the new behaviour")
        var s = AppSettings(); s.hideTitleBarsUntilHover = false
        XCTAssertFalse(try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(s)).hideTitleBarsUntilHover)
    }
}

final class WidgetNameTests: XCTestCase {
    func testClockIsCalledTimeAndOldLayoutsStillLoad() throws {
        XCTAssertEqual(WidgetType.clock.displayName, "Time")
        XCTAssertEqual(WidgetType.clock.rawValue, "Clock & Date", "stored identifier unchanged")
        for oldTitle in ["Clock & Date", "Desktop Clock"] {
            let json = #"{"id":"23403662-1920-411F-9F39-EC6862779FF5","type":"Clock & Date","title":"\#(oldTitle)"}"#
            let w = try JSONDecoder().decode(DesktopWidget.self, from: Data(json.utf8))
            XCTAssertEqual(w.type, .clock)
            XCTAssertEqual(w.title, "Time")
        }
        let custom = #"{"id":"23403662-1920-411F-9F39-EC6862779FF5","type":"Clock & Date","title":"Istanbul"}"#
        XCTAssertEqual(try JSONDecoder().decode(DesktopWidget.self, from: Data(custom.utf8)).title, "Istanbul", "custom titles kept")
    }
}

final class KeyboardFocusTests: XCTestCase {
    func testZonesDoNotStealKeyboardFocusByDefault() throws {
        XCTAssertFalse(AppSettings().zonesTakeKeyboardFocus)
        XCTAssertFalse(try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8)).zonesTakeKeyboardFocus)
        XCTAssertFalse(AppSettings().showDockIcon)
        XCTAssertFalse(try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8)).showDockIcon)
        var s = AppSettings(); s.showDockIcon = true
        XCTAssertTrue(try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(s)).showDockIcon)
        let panel = ZonePanel(zone: ZoneModel(title: "Z"), contentRect: NSRect(x: 0, y: 0, width: 300, height: 200))
        XCTAssertTrue(panel.becomesKeyOnlyIfNeeded, "clicks must not make the zone key")
        panel.applyKeyboardFocusPolicy(takesFocusOnClick: true)
        XCTAssertFalse(panel.becomesKeyOnlyIfNeeded)
        XCTAssertTrue(panel.canBecomeKey, "text fields (rename) can still get focus")
    }

    func testDropDesktopKeyFocusSafelyExecutes() {
        WindowManager.shared.dropDesktopKeyFocus()
        // Must succeed without crashing even when no panels are key
    }
}
