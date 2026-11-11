import Foundation
import AppKit
import SwiftUI

// MARK: - Snapping (pure, testable)

public enum Snapping {
    /// - Parameter includeGrid: false while the pointer is moving (so the window follows the pointer
    ///   smoothly and only edge-snaps magnetically); true on release to settle onto the grid.
    public static func snap(_ targetRect: NSRect, otherFrames: [NSRect], settings: AppSettings, includeGrid: Bool = true) -> NSRect {
        guard settings.alignmentMode else { return targetRect }
        var snapped = targetRect
        let threshold = settings.snapThreshold
        let gap: CGFloat = 12
        var snappedX = false
        var snappedY = false

        if settings.snapToNeighbors {
            for other in otherFrames {
                if !snappedX {
                    if abs(snapped.minX - other.minX) < threshold { snapped.origin.x = other.minX; snappedX = true }
                    else if abs(snapped.minX - (other.maxX + gap)) < threshold { snapped.origin.x = other.maxX + gap; snappedX = true }
                    else if abs(snapped.maxX - other.maxX) < threshold { snapped.origin.x = other.maxX - snapped.width; snappedX = true }
                    else if abs(snapped.maxX - (other.minX - gap)) < threshold { snapped.origin.x = other.minX - gap - snapped.width; snappedX = true }
                }
                if !snappedY {
                    if abs(snapped.maxY - other.maxY) < threshold { snapped.origin.y = other.maxY - snapped.height; snappedY = true }
                    else if abs(snapped.minY - other.minY) < threshold { snapped.origin.y = other.minY; snappedY = true }
                    else if abs(snapped.maxY - (other.minY - gap)) < threshold { snapped.origin.y = other.minY - gap - snapped.height; snappedY = true }
                    else if abs(snapped.minY - (other.maxY + gap)) < threshold { snapped.origin.y = other.maxY + gap; snappedY = true }
                }
            }
        }
        if includeGrid && settings.snapToGrid && settings.gridSize >= 2 {
            let grid = settings.gridSize
            if !snappedX { snapped.origin.x = (snapped.origin.x / grid).rounded() * grid }
            if !snappedY { snapped.origin.y = (snapped.origin.y / grid).rounded() * grid }
        }
        return snapped
    }
}

// MARK: - Desktop panel base

/// Borderless panel that lives just above the Finder desktop icons, below ordinary app windows.
public class DesktopPanel: NSPanel, NSWindowDelegate {
    public static var desktopLevel: NSWindow.Level {
        NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
    }

    /// Called after the user finishes moving or resizing the panel with the window edges.
    public var onFrameCommitted: ((NSRect) -> Void)?
    public var minimumContentSize = NSSize(width: 140, height: 40)

    public init(contentRect: NSRect, resizable: Bool) {
        var style: NSWindow.StyleMask = [.borderless, .nonactivatingPanel]
        if resizable { style.insert(.resizable) }
        super.init(contentRect: contentRect, styleMask: style, backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = false
        isReleasedWhenClosed = false
        hidesOnDeactivate = false      // NSPanel hides on deactivate by default; zones must stay visible.
        isFloatingPanel = false
        // Only take keyboard focus for views that need it (text fields). Taking it on every
        // click sent the user's shortcuts (Cmd-Shift-E etc.) to DesktopDüzen instead of the
        // frontmost app, because these panels can be key without activating the app.
        becomesKeyOnlyIfNeeded = true
        worksWhenModal = true
        animationBehavior = .none
        level = DesktopPanel.desktopLevel
        delegate = self
    }

    public override var canBecomeKey: Bool { true }
    public override var canBecomeMain: Bool { false }

    public func applyKeyboardFocusPolicy(takesFocusOnClick: Bool) {
        let onlyIfNeeded = !takesFocusOnClick
        if becomesKeyOnlyIfNeeded != onlyIfNeeded { becomesKeyOnlyIfNeeded = onlyIfNeeded }
    }

    public func applyLevel(pinned: Bool) {
        // Zones always sit directly at the desktop level so they never cover other apps or browsers.
        let target: NSWindow.Level = DesktopPanel.desktopLevel
        if level != target { level = target }
    }

    public func applySpacesBehavior(allSpaces: Bool) {
        // .stationary and .managed are mutually exclusive, so each mode uses a complete set.
        let behavior: NSWindow.CollectionBehavior = allSpaces
            ? [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
            : [.managed, .ignoresCycle, .fullScreenNone]
        if collectionBehavior != behavior { collectionBehavior = behavior }
    }

    public func windowDidEndLiveResize(_ notification: Notification) {
        onFrameCommitted?(frame)
    }

    public func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        if let zp = sender as? ZonePanel, let zone = AppState.shared.zone(id: zp.zoneID), zone.isPositionLocked {
            return sender.frame.size
        }
        return NSSize(width: max(frameSize.width, minimumContentSize.width), height: max(frameSize.height, minimumContentSize.height))
    }

    public override func cancelOperation(_ sender: Any?) {
        makeFirstResponder(nil)
    }
}

// MARK: - Zone panel

public final class ZonePanel: DesktopPanel {
    public let zoneID: UUID
    private var trackingArea: NSTrackingArea?
    public var onHoverChanged: ((Bool) -> Void)?

    public init(zone: ZoneModel, contentRect: NSRect) {
        self.zoneID = zone.id
        super.init(contentRect: contentRect, resizable: true)
        minimumContentSize = NSSize(width: 220, height: zone.collapsedHeight)
        applyLevel(pinned: zone.isPinnedOnTop)
    }

    /// Must be called after `contentView` is assigned; earlier builds attached the tracking area to a
    /// view that was then replaced, so hover-expand never fired.
    public func installHoverTracking() {
        if let existing = trackingArea { contentView?.removeTrackingArea(existing) }
        guard let view = contentView else { return }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        view.addTrackingArea(area)
        trackingArea = area
    }

    public override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        onHoverChanged?(true)
    }

    public override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onHoverChanged?(false)
    }

    /// Kept for source compatibility with earlier tests.
    public func snapFrame(_ targetRect: NSRect, otherFrames: [NSRect]) -> NSRect {
        Snapping.snap(targetRect, otherFrames: otherFrames, settings: AppState.shared.settings)
    }
}

/// Borderless panel that accepts keyboard input (used for global search).
public final class KeyablePanel: NSPanel {
    public var onCancel: (() -> Void)?
    public override var canBecomeKey: Bool { true }
    public override var canBecomeMain: Bool { true }
    public override func cancelOperation(_ sender: Any?) {
        if let onCancel = onCancel { onCancel() } else { orderOut(nil) }
    }
}
