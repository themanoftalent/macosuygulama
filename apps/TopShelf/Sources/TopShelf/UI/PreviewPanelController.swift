import AppKit
import QuickLookThumbnailing

@MainActor
final class PreviewPanelController {
    static let shared = PreviewPanelController()

    private var panel: NSPanel?
    private var imageView: NSImageView!
    private var titleLabel: NSTextField!
    private var metaLabel: NSTextField!
    private var currentURL: URL?
    private var pendingTask: Task<Void, Never>?

    private let panelSize = NSSize(width: 300, height: 324)

    private init() {}

    func showPreview(for item: FileItem, anchorRowRectInScreen: NSRect, parentPanelFrame: NSRect) {
        guard AppStore.shared.settings.enableHoverPreview, !item.isExpandableFolder else {
            hide()
            return
        }

        if currentURL == item.url, let panel, panel.isVisible {
            position(panel: panel, anchorRowRect: anchorRowRectInScreen, parentPanelFrame: parentPanelFrame)
            return
        }

        currentURL = item.url
        pendingTask?.cancel()

        let panel = ensurePanel()
        titleLabel.stringValue = item.displayName
        metaLabel.stringValue = Self.metadataText(for: item)
        imageView.image = item.icon(size: NSSize(width: 128, height: 128))

        position(panel: panel, anchorRowRect: anchorRowRectInScreen, parentPanelFrame: parentPanelFrame)
        panel.orderFront(nil)

        let targetURL = item.url
        let scale = panel.backingScaleFactor
        pendingTask = Task { [weak self] in
            let request = QLThumbnailGenerator.Request(
                fileAt: targetURL,
                size: CGSize(width: 280, height: 260),
                scale: scale,
                representationTypes: .all
            )
            do {
                let rep = try await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let self, self.currentURL == targetURL else { return }
                    self.imageView.image = rep.nsImage
                }
            } catch {
                // Keep file icon fallback on failure
            }
        }
    }

    func hide() {
        pendingTask?.cancel()
        pendingTask = nil
        currentURL = nil
        panel?.orderOut(nil)
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }

        let p = NSPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .popUpMenu
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        p.ignoresMouseEvents = true

        let container = NSVisualEffectView(frame: NSRect(origin: .zero, size: panelSize))
        container.material = .hudWindow
        container.blendingMode = .behindWindow
        container.state = .active
        container.wantsLayer = true
        container.layer?.cornerRadius = 12
        container.layer?.masksToBounds = true
        container.layer?.borderWidth = 0.5
        container.layer?.borderColor = NSColor.white.withAlphaComponent(0.16).cgColor

        let imgView = NSImageView()
        imgView.translatesAutoresizingMaskIntoConstraints = false
        imgView.imageScaling = .scaleProportionallyUpOrDown
        imgView.imageAlignment = .alignCenter
        imgView.wantsLayer = true
        imgView.layer?.cornerRadius = 8
        imgView.layer?.masksToBounds = true

        let title = NSTextField(labelWithString: "")
        title.translatesAutoresizingMaskIntoConstraints = false
        title.font = .systemFont(ofSize: 12, weight: .semibold)
        title.textColor = .labelColor
        title.lineBreakMode = .byTruncatingMiddle
        title.alignment = .center

        let meta = NSTextField(labelWithString: "")
        meta.translatesAutoresizingMaskIntoConstraints = false
        meta.font = .systemFont(ofSize: 11, weight: .regular)
        meta.textColor = .secondaryLabelColor
        meta.lineBreakMode = .byTruncatingTail
        meta.alignment = .center

        container.addSubview(imgView)
        container.addSubview(title)
        container.addSubview(meta)

        NSLayoutConstraint.activate([
            imgView.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            imgView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            imgView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            imgView.heightAnchor.constraint(equalToConstant: 256),

            title.topAnchor.constraint(equalTo: imgView.bottomAnchor, constant: 8),
            title.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            title.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),

            meta.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 2),
            meta.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            meta.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12)
        ])

        p.contentView = container
        self.imageView = imgView
        self.titleLabel = title
        self.metaLabel = meta
        self.panel = p
        return p
    }

    private func position(panel: NSPanel, anchorRowRect: NSRect, parentPanelFrame: NSRect) {
        let screenFrame = NSScreen.screens.first(where: { $0.frame.intersects(parentPanelFrame) })?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        let gap: CGFloat = 10
        var originX = parentPanelFrame.minX - panelSize.width - gap
        if originX < screenFrame.minX + 8 {
            originX = parentPanelFrame.maxX + gap
        }

        // Vertically center near the hovered row, clamped to the visible screen
        var originY = anchorRowRect.midY - panelSize.height / 2
        originY = max(screenFrame.minY + 10, min(originY, screenFrame.maxY - panelSize.height - 10))

        panel.setFrame(NSRect(x: originX, y: originY, width: panelSize.width, height: panelSize.height), display: true)
    }

    private static func metadataText(for item: FileItem) -> String {
        let sizeStr = ByteCountFormatter.string(fromByteCount: item.fileSize, countStyle: .file)
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        let dateStr = item.modificationDate == .distantPast ? "" : df.string(from: item.modificationDate)
        if !item.typeDescription.isEmpty && !dateStr.isEmpty {
            return "\(item.typeDescription) • \(sizeStr) • \(dateStr)"
        } else if !dateStr.isEmpty {
            return "\(sizeStr) • \(dateStr)"
        }
        return sizeStr
    }
}
