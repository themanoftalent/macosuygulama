import SwiftUI
import AppKit

/// Moves its window with the mouse, using screen coordinates and a fixed start frame.
/// Earlier builds moved windows from SwiftUI DragGesture translations measured inside the very
/// view being moved, and never reset the start frame, so zones jumped between drags.
public struct WindowDragArea: NSViewRepresentable {
    public var isLocked: Bool = false
    public var snap: ((NSRect, Bool) -> NSRect)?
    public var onDragEnded: (NSRect) -> Void
    public var onDoubleClick: (() -> Void)?
    public var onClick: (() -> Void)?

    public init(isLocked: Bool = false, snap: ((NSRect, Bool) -> NSRect)? = nil, onDragEnded: @escaping (NSRect) -> Void,
                onDoubleClick: (() -> Void)? = nil, onClick: (() -> Void)? = nil) {
        self.isLocked = isLocked
        self.snap = snap
        self.onDragEnded = onDragEnded
        self.onDoubleClick = onDoubleClick
        self.onClick = onClick
    }

    public func makeNSView(context: Context) -> DragHandleView {
        let view = DragHandleView()
        update(view)
        return view
    }

    public func updateNSView(_ nsView: DragHandleView, context: Context) {
        update(nsView)
    }

    private func update(_ view: DragHandleView) {
        view.isLocked = isLocked
        view.snap = snap
        view.onDragEnded = onDragEnded
        view.onDoubleClick = onDoubleClick
        view.onClick = onClick
    }

    public final class DragHandleView: NSView {
        var isLocked: Bool = false
        var snap: ((NSRect, Bool) -> NSRect)?
        var onDragEnded: ((NSRect) -> Void)?
        var onDoubleClick: (() -> Void)?
        var onClick: (() -> Void)?

        public override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        public override var mouseDownCanMoveWindow: Bool { false }

        public override func mouseDown(with event: NSEvent) {
            guard let window = window else { return }
            if event.clickCount >= 2 {
                onDoubleClick?()
                return
            }
            if isLocked {
                onClick?()
                return
            }
            // No makeKey(): dragging must not steal keyboard focus from the frontmost app.
            let startMouse = NSEvent.mouseLocation
            let startFrame = window.frame
            var moved = false

            var unsnapped = startFrame
            while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
                if next.type == .leftMouseUp { break }
                let current = NSEvent.mouseLocation
                let dx = current.x - startMouse.x
                let dy = current.y - startMouse.y
                if !moved && hypot(dx, dy) < 3 { continue }
                moved = true
                unsnapped = startFrame.offsetBy(dx: dx, dy: dy)
                // Live: edge magnetism only. Grid stepping here made zones judder while dragging.
                let target = snap?(unsnapped, false) ?? unsnapped
                let origin = NSPoint(x: target.origin.x.rounded(), y: target.origin.y.rounded())
                if origin != window.frame.origin { window.setFrameOrigin(origin) }
            }
            if moved {
                if let snap = snap {
                    let settled = snap(unsnapped, true)
                    if settled.origin != window.frame.origin {
                        NSAnimationContext.runAnimationGroup { ctx in
                            ctx.duration = 0.12
                            window.animator().setFrameOrigin(settled.origin)
                        }
                    }
                    onDragEnded?(NSRect(origin: settled.origin, size: window.frame.size))
                } else {
                    onDragEnded?(window.frame)
                }
            } else {
                onClick?()
            }
        }
    }
}

/// Bottom-right resize grip. Keeps the top-left corner fixed and enforces a minimum size.
public struct WindowResizeGrip: NSViewRepresentable {
    public var minSize: NSSize
    public var onResizeEnded: (NSRect) -> Void

    public init(minSize: NSSize = NSSize(width: 220, height: 120), onResizeEnded: @escaping (NSRect) -> Void) {
        self.minSize = minSize
        self.onResizeEnded = onResizeEnded
    }

    public func makeNSView(context: Context) -> GripView {
        let view = GripView()
        view.minSize = minSize
        view.onResizeEnded = onResizeEnded
        return view
    }

    public func updateNSView(_ nsView: GripView, context: Context) {
        nsView.minSize = minSize
        nsView.onResizeEnded = onResizeEnded
    }

    public final class GripView: NSView {
        var minSize = NSSize(width: 220, height: 120)
        var onResizeEnded: ((NSRect) -> Void)?

        public override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        public override var mouseDownCanMoveWindow: Bool { false }

        public override func mouseDown(with event: NSEvent) {
            guard let window = window else { return }
            let startMouse = NSEvent.mouseLocation
            let startFrame = window.frame
            let top = startFrame.maxY
            var changed = false
            while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
                if next.type == .leftMouseUp { break }
                let current = NSEvent.mouseLocation
                let width = max(minSize.width, startFrame.width + (current.x - startMouse.x))
                let height = max(minSize.height, startFrame.height - (current.y - startMouse.y))
                let frame = NSRect(x: startFrame.minX, y: top - height, width: width, height: height)
                window.setFrame(frame, display: true)
                changed = true
            }
            if changed { onResizeEnded?(window.frame) }
        }
    }
}
