import XCTest
import AppKit
@testable import DesktopDuzen

final class PinnedItemTests: SandboxedTestCase {

    func testPinnedItemModelSerialization() throws {
        let item = PinnedDesktopItem(
            name: "Report.pdf",
            path: "/Users/test/Desktop/Report.pdf",
            position: CGPoint(x: 120.5, y: 340.0),
            displayID: 182736,
            screenBounds: CGRect(x: 0, y: 0, width: 2560, height: 1440),
            bookmarkData: nil,
            pinnedAt: Date()
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(item)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(PinnedDesktopItem.self, from: data)

        XCTAssertEqual(decoded.id, item.id)
        XCTAssertEqual(decoded.name, "Report.pdf")
        XCTAssertEqual(decoded.path, "/Users/test/Desktop/Report.pdf")
        XCTAssertEqual(decoded.position.x, 120.5)
        XCTAssertEqual(decoded.position.y, 340.0)
        XCTAssertEqual(decoded.displayID, 182736)
        XCTAssertEqual(decoded.screenBounds?.width, 2560)
        XCTAssertEqual(decoded.screenBounds?.height, 1440)
    }

    func testAppStatePersistenceOfPinnedItems() throws {
        let state1 = makeState(createStarter: false)
        let fileURL = try write("Document.docx", in: desktop)

        let pinned = PinnedDesktopItem(
            name: "Document.docx",
            path: fileURL.path,
            position: CGPoint(x: 500, y: 600),
            displayID: 1
        )
        state1.addPinnedItem(pinned)
        XCTAssertTrue(state1.isItemPinned(path: fileURL.path))
        XCTAssertTrue(state1.saveState())

        // Load new state from the same storage URL
        let state2 = makeState(createStarter: false)
        XCTAssertEqual(state2.pinnedItems.count, 1)
        let loaded = state2.pinnedItems.first
        XCTAssertEqual(loaded?.name, "Document.docx")
        XCTAssertEqual(loaded?.path, fileURL.path)
        XCTAssertEqual(loaded?.position.x, 500)
        XCTAssertEqual(loaded?.position.y, 600)
        XCTAssertTrue(state2.isItemPinned(path: fileURL.path))
    }

    func testAutoSortStrictlyExcludesPinnedItems() throws {
        let state = makeState()
        guard let targetZone = state.zones.first(where: { $0.type == .file }) else {
            XCTFail("Missing starter file zone")
            return
        }

        let rule = AutoSortRule(name: "PDFs", targetZoneTitle: targetZone.title, extensions: ["pdf"])
        _ = try write("Unpinned.pdf", in: desktop)
        let pinnedURL = try write("PinnedImportant.pdf", in: desktop)

        let pinnedItem = PinnedDesktopItem(
            name: "PinnedImportant.pdf",
            path: pinnedURL.path,
            position: CGPoint(x: 100, y: 200)
        )
        state.addPinnedItem(pinnedItem)

        let service = AutoSortService(fileService: fs)
        let plan = service.makePlan(
            rules: [rule],
            zones: state.zones,
            pinnedItemPaths: [pinnedURL.path]
        )

        // The unpinned PDF must be in the plan
        let plannedSources = plan.moves.map { $0.source.lastPathComponent }
        XCTAssertTrue(plannedSources.contains("Unpinned.pdf"), "Unpinned file should be scheduled for move")
        // The pinned PDF MUST NOT be in the plan
        XCTAssertFalse(plannedSources.contains("PinnedImportant.pdf"), "Pinned desktop item must never be moved by auto-sort")
    }

    func testPinAndUnpinLifecycle() throws {
        let state = makeState(createStarter: false)
        let file1 = try write("File1.txt", in: desktop)
        let file2 = try write("File2.txt", in: desktop)

        let p1 = PinnedDesktopItem(name: "File1.txt", path: file1.path, position: CGPoint(x: 50, y: 50))
        let p2 = PinnedDesktopItem(name: "File2.txt", path: file2.path, position: CGPoint(x: 150, y: 150))

        state.addPinnedItem(p1)
        state.addPinnedItem(p2)
        XCTAssertEqual(state.pinnedItems.count, 2)
        XCTAssertTrue(state.isItemPinned(path: file1.path))
        XCTAssertTrue(state.isItemPinned(path: file2.path))

        // Unpin file1
        state.removePinnedItem(id: p1.id)
        XCTAssertEqual(state.pinnedItems.count, 1)
        XCTAssertFalse(state.isItemPinned(path: file1.path))
        XCTAssertTrue(state.isItemPinned(path: file2.path))

        // Unpin all
        state.removeAllPinnedItems()
        XCTAssertEqual(state.pinnedItems.count, 0)
        XCTAssertFalse(state.isItemPinned(path: file2.path))
    }

    func testFinderPointToAppKitCoordinateConversion() {
        let finderPt = CGPoint(x: 2400, y: 150)
        let appKitPt = DesktopPinService.finderPointToAppKit(finderPt)
        let primaryH = NSScreen.screens.first?.frame.height ?? 900
        XCTAssertEqual(appKitPt.x, 2400)
        XCTAssertEqual(appKitPt.y, primaryH - 150)
    }

    func testAutoAlignPreservesPositionOfLockedZones() {
        let state = makeState(createStarter: false)
        let customFrame = CGRect(x: 777, y: 333, width: 340, height: 260)
        var lockedZone = ZoneModel(type: .file, title: "LockedZone", frame: customFrame)
        lockedZone.isPositionLocked = true
        state.zones.append(lockedZone)

        let unlockedZone = ZoneModel(type: .file, title: "UnlockedZone", frame: CGRect(x: 100, y: 100, width: 340, height: 260))
        state.zones.append(unlockedZone)

        state.autoAlignAllZones()

        let afterLocked = state.zones.first { $0.title == "LockedZone" }
        XCTAssertEqual(afterLocked?.frame.origin.x, 777, "Locked zone X position should remain untouched")
        XCTAssertEqual(afterLocked?.frame.origin.y, 333, "Locked zone Y position should remain untouched")
    }
}
