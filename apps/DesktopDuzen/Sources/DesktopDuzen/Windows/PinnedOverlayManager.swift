import Foundation
import AppKit
import Combine

/// Displays subtle visual pin indicators (📌) directly over locked desktop items.
/// Uses an invisible pass-through panel so normal clicks and drags on the desktop
/// pass through unimpeded to Finder, while clicking a pin badge allows unpinning.
public final class PinnedOverlayManager: NSObject {
    public static let shared = PinnedOverlayManager()

    private var panels: [NSPanel] = []
    private var cancellables = Set<AnyCancellable>()
    private var started = false

    public override init() {
        super.init()
    }

    public func start() {
        guard !started else { return }
        started = true

        AppState.shared.$pinnedItems
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshPanels()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshPanels()
            }
            .store(in: &cancellables)

        refreshPanels()
    }

    public func refreshPanels() {
        for panel in panels {
            panel.close()
        }
        panels.removeAll()

        guard !AppState.shared.pinnedItems.isEmpty else { return }

        for screen in NSScreen.screens {
            let panel = NSPanel(
                contentRect: screen.frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.level = NSWindow.Level(Int(CGWindowLevelForKey(.desktopWindow)) + 1)
            panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            panel.ignoresMouseEvents = false

            let overlayView = PinnedOverlayView(frame: NSRect(origin: .zero, size: screen.frame.size), screen: screen)
            panel.contentView = overlayView
            panel.orderFront(nil)
            panels.append(panel)
        }
    }
}

/// Custom NSView that renders pin badges and allows all non-badge clicks to fall through.
final class PinnedOverlayView: NSView {
    private let screen: NSScreen
    private var badgeRects: [(item: PinnedDesktopItem, rect: NSRect)] = []

    init(frame frameRect: NSRect, screen: NSScreen) {
        self.screen = screen
        super.init(frame: frameRect)
        wantsLayer = true
        updateBadgeRects()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Only intercept mouse events if clicking directly on a pin badge
        for (_, rect) in badgeRects {
            if rect.contains(point) {
                return self
            }
        }
        // Let the click pass straight through to Finder
        return nil
    }

    private func updateBadgeRects() {
        badgeRects.removeAll()
        let primaryH = NSScreen.screens.first?.frame.height ?? 900
        let badgeSize = NSSize(width: 22, height: 22)

        for item in AppState.shared.pinnedItems {
            // First try Accessibility API to get live icon location and size
            if let ax = DesktopPinService.shared.getAXPosition(for: item.name) {
                // ax.pos is in top-left display coordinates
                let appKitY = primaryH - ax.pos.y
                let origin = NSPoint(
                    x: ax.pos.x + ax.size.width - 12 - screen.frame.origin.x,
                    y: appKitY - 8 - screen.frame.origin.y
                )
                let rect = NSRect(origin: origin, size: badgeSize)
                badgeRects.append((item, rect))
            } else {
                // Fallback to Finder AppleScript coordinates
                let appKitY = primaryH - item.position.y
                let origin = NSPoint(
                    x: item.position.x + 16 - screen.frame.origin.x,
                    y: appKitY + 8 - screen.frame.origin.y
                )
                let rect = NSRect(origin: origin, size: badgeSize)
                badgeRects.append((item, rect))
            }
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        updateBadgeRects()

        guard let context = NSGraphicsContext.current?.cgContext else { return }

        for (_, rect) in badgeRects {
            context.saveGState()

            // Outer subtle drop shadow
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.4)
            shadow.shadowOffset = NSSize(width: 0, height: -1.5)
            shadow.shadowBlurRadius = 3.0
            shadow.set()

            // Badge circular background
            let badgePath = NSBezierPath(ovalIn: rect)
            let fillColor = NSColor.systemOrange
            fillColor.setFill()
            badgePath.fill()

            // Badge border
            NSColor.white.withAlphaComponent(0.85).setStroke()
            badgePath.lineWidth = 1.2
            badgePath.stroke()

            context.restoreGState()

            // Pin icon (📌 or SF Symbol)
            if let symbol = NSImage(systemSymbolName: "pin.fill", accessibilityDescription: "Pinned") {
                let symbolRect = NSRect(
                    x: rect.origin.x + 4,
                    y: rect.origin.y + 4,
                    width: 14,
                    height: 14
                )
                let tinted = symbol.copy() as! NSImage
                tinted.lockFocus()
                NSColor.white.set()
                let imgRect = NSRect(origin: .zero, size: tinted.size)
                imgRect.fill(using: .sourceAtop)
                tinted.unlockFocus()
                tinted.draw(in: symbolRect)
            } else {
                // Fallback emoji
                let str = "📌" as NSString
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 12)
                ]
                str.draw(at: NSPoint(x: rect.origin.x + 3, y: rect.origin.y + 2), withAttributes: attrs)
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        for (item, rect) in badgeRects {
            if rect.contains(point) {
                showBadgeMenu(for: item, at: point)
                return
            }
        }
        super.mouseDown(with: event)
    }

    private func showBadgeMenu(for item: PinnedDesktopItem, at point: NSPoint) {
        let menu = NSMenu(title: "Pinned Item")

        let titleItem = NSMenuItem(title: "📌 \(item.name)", action: nil, keyEquivalent: "")
        titleItem.attributedTitle = NSAttributedString(
            string: "📌 \(item.name)",
            attributes: [.font: NSFont.boldSystemFont(ofSize: 13)]
        )
        menu.addItem(titleItem)

        let posItem = NSMenuItem(
            title: "Pinned at: (\(Int(item.position.x)), \(Int(item.position.y)))",
            action: nil,
            keyEquivalent: ""
        )
        posItem.isEnabled = false
        menu.addItem(posItem)

        menu.addItem(NSMenuItem.separator())

        let revealItem = NSMenuItem(title: "Show in Finder", action: #selector(revealInFinder(_:)), keyEquivalent: "")
        revealItem.representedObject = item.path
        revealItem.target = self
        revealItem.image = NSImage(systemSymbolName: "arrow.up.right.square", accessibilityDescription: nil)
        menu.addItem(revealItem)

        let unpinItem = NSMenuItem(title: "Unpin Item", action: #selector(unpinAction(_:)), keyEquivalent: "")
        unpinItem.representedObject = item.id
        unpinItem.target = self
        unpinItem.image = NSImage(systemSymbolName: "pin.slash", accessibilityDescription: nil)
        menu.addItem(unpinItem)

        menu.popUp(positioning: nil, at: point, in: self)
    }

    @objc private func revealInFinder(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        let url = URL(fileURLWithPath: path)
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    @objc private func unpinAction(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        DesktopPinService.shared.unpinItem(id: id)
    }
}
