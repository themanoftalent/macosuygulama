import AppKit

@MainActor
protocol FolderRowViewDelegate: AnyObject {
    func rowDidHover(_ row: FolderRowView)
    func rowDidClick(_ row: FolderRowView)
    func rowDidDoubleClick(_ row: FolderRowView)
    func rowDidStartDragging(_ row: FolderRowView)
    func rowDidEndDragging(_ row: FolderRowView)
    func rowRequestDismissAll()
    func rowRequestRefresh()
}

final class FolderRowView: NSView, NSDraggingSource {
    let item: FileItem
    weak var delegate: FolderRowViewDelegate?

    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let chevronView = NSImageView()
    private var trackingArea: NSTrackingArea?

    private var mouseDownEvent: NSEvent?
    private var mouseDownPoint: NSPoint = .zero
    private var didDrag = false

    var isHighlighted: Bool = false {
        didSet {
            guard oldValue != isHighlighted else { return }
            updateAppearance()
        }
    }

    init(item: FileItem, width: CGFloat) {
        self.item = item
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 28))
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.masksToBounds = true
        setupSubviews()
        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupSubviews() {
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.image = item.icon(size: NSSize(width: 17, height: 17))
        iconView.imageScaling = .scaleProportionallyDown

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.stringValue = item.displayName
        titleLabel.font = .systemFont(ofSize: 13, weight: .regular)
        titleLabel.lineBreakMode = .byTruncatingMiddle
        titleLabel.maximumNumberOfLines = 1
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        addSubview(iconView)
        addSubview(titleLabel)

        var constraints: [NSLayoutConstraint] = [
            heightAnchor.constraint(equalToConstant: 28),
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 17),
            iconView.heightAnchor.constraint(equalToConstant: 17),

            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ]

        if item.isExpandableFolder {
            chevronView.translatesAutoresizingMaskIntoConstraints = false
            let cfg = NSImage.SymbolConfiguration(pointSize: 10, weight: .semibold)
            chevronView.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)?
                .withSymbolConfiguration(cfg)
            chevronView.contentTintColor = .tertiaryLabelColor
            addSubview(chevronView)

            constraints.append(contentsOf: [
                chevronView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
                chevronView.centerYAnchor.constraint(equalTo: centerYAnchor),
                chevronView.widthAnchor.constraint(equalToConstant: 10),
                titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: chevronView.leadingAnchor, constant: -6)
            ])
        } else {
            constraints.append(
                titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8)
            )
        }

        NSLayoutConstraint.activate(constraints)
    }

    private func updateAppearance() {
        if isHighlighted {
            layer?.backgroundColor = NSColor.controlAccentColor.cgColor
            titleLabel.textColor = .white
            chevronView.contentTintColor = NSColor.white.withAlphaComponent(0.9)
        } else {
            layer?.backgroundColor = NSColor.clear.cgColor
            titleLabel.textColor = item.isHidden ? .secondaryLabelColor : .labelColor
            chevronView.contentTintColor = .tertiaryLabelColor
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseEntered(with event: NSEvent) {
        delegate?.rowDidHover(self)
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownEvent = event
        mouseDownPoint = convert(event.locationInWindow, from: nil)
        didDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard !didDrag, let startEvent = mouseDownEvent else { return }
        let currentPoint = convert(event.locationInWindow, from: nil)
        let dist = hypot(currentPoint.x - mouseDownPoint.x, currentPoint.y - mouseDownPoint.y)
        if dist >= 4 {
            didDrag = true
            startFileDrag(with: startEvent)
        }
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            mouseDownEvent = nil
            didDrag = false
        }
        guard !didDrag else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard bounds.contains(point) else { return }

        if event.clickCount == 2 {
            delegate?.rowDidDoubleClick(self)
        } else {
            delegate?.rowDidClick(self)
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        let openItem = NSMenuItem(title: item.isExpandableFolder ? "Open in Finder" : "Open", action: #selector(contextOpen), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)

        if !item.isExpandableFolder {
            let revealItem = NSMenuItem(title: "Show in Finder", action: #selector(contextReveal), keyEquivalent: "")
            revealItem.target = self
            menu.addItem(revealItem)
        }

        let copyPathItem = NSMenuItem(title: "Copy Path", action: #selector(contextCopyPath), keyEquivalent: "")
        copyPathItem.target = self
        menu.addItem(copyPathItem)

        menu.addItem(.separator())

        let trashItem = NSMenuItem(title: "Move to Trash", action: #selector(contextTrash), keyEquivalent: "")
        trashItem.target = self
        menu.addItem(trashItem)

        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func contextOpen() {
        NSWorkspace.shared.open(item.url)
        delegate?.rowRequestDismissAll()
    }

    @objc private func contextReveal() {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
        delegate?.rowRequestDismissAll()
    }

    @objc private func contextCopyPath() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(item.url.path, forType: .string)
    }

    @objc private func contextTrash() {
        do {
            try FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
            delegate?.rowRequestRefresh()
        } catch {
            NSSound.beep()
        }
    }

    // MARK: - NSDraggingSource

    private func startFileDrag(with event: NSEvent) {
        let draggingItem = NSDraggingItem(pasteboardWriter: item.url as NSURL)
        let dragImage = item.icon(size: NSSize(width: 36, height: 36))
        let dragFrame = NSRect(
            x: mouseDownPoint.x - 18,
            y: mouseDownPoint.y - 18,
            width: 36,
            height: 36
        )
        draggingItem.setDraggingFrame(dragFrame, contents: dragImage)

        delegate?.rowDidStartDragging(self)
        beginDraggingSession(with: [draggingItem], event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        switch context {
        case .outsideApplication:
            return [.copy, .link, .generic]
        case .withinApplication:
            return [.copy, .move]
        @unknown default:
            return [.copy]
        }
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        delegate?.rowDidEndDragging(self)
    }
}
