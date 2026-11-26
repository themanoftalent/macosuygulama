import AppKit

private final class FlippedStackView: NSView {
    override var isFlipped: Bool { true }
}

private final class FolderDropContainerView: NSVisualEffectView {
    var targetDirectoryURL: URL?
    var onFilesDropped: (() -> Void)?

    private var isDragHighlighted = false {
        didSet {
            guard oldValue != isDragHighlighted else { return }
            layer?.borderWidth = isDragHighlighted ? 2.0 : 0.5
            layer?.borderColor = isDragHighlighted
                ? NSColor.controlAccentColor.cgColor
                : NSColor.white.withAlphaComponent(0.16).cgColor
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard sender.draggingSource == nil else { return [] }
        isDragHighlighted = true
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        isDragHighlighted = false
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        isDragHighlighted = false
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        isDragHighlighted = false
        guard let destDir = targetDirectoryURL else { return false }
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true
        ]) as? [URL], !urls.isEmpty else {
            return false
        }

        let fm = FileManager.default
        var copiedAny = false
        for srcURL in urls {
            guard srcURL.deletingLastPathComponent().standardizedFileURL != destDir.standardizedFileURL else {
                continue
            }
            var destURL = destDir.appendingPathComponent(srcURL.lastPathComponent)
            var counter = 2
            while fm.fileExists(atPath: destURL.path) {
                let base = srcURL.deletingPathExtension().lastPathComponent
                let ext = srcURL.pathExtension
                let newName = ext.isEmpty ? "\(base) \(counter)" : "\(base) \(counter).\(ext)"
                destURL = destDir.appendingPathComponent(newName)
                counter += 1
            }
            if (try? fm.copyItem(at: srcURL, to: destURL)) != nil {
                copiedAny = true
            }
        }

        if copiedAny {
            onFilesDropped?()
        }
        return copiedAny
    }
}

@MainActor
protocol FolderMenuPanelDelegate: AnyObject {
    func folderPanelDidRequestDismissAll()
    func folderPanelDidRequestSettings(selectedFolderID: UUID?)
    func folderPanelDidChangeDraggingState(_ isDragging: Bool)
}

@MainActor
final class FolderMenuPanel: NSPanel, FolderRowViewDelegate {
    private let panelWidth: CGFloat = 264
    private let rowHeight: CGFloat = 28
    private let rowSpacing: CGFloat = 2
    private let verticalPadding: CGFloat = 6
    private let horizontalPadding: CGFloat = 6
    private let footerHeight: CGFloat = 34

    let directoryURL: URL
    private var pinnedFolder: PinnedFolder
    private let isRoot: Bool
    weak var menuDelegate: FolderMenuPanelDelegate?

    private let containerView = FolderDropContainerView()
    private let scrollView = NSScrollView()
    private let documentView = FlippedStackView()
    private var rowViews: [FolderRowView] = []
    private var highlightedRow: FolderRowView?

    private var childPanel: FolderMenuPanel?
    private var hoverWorkItem: DispatchWorkItem?
    private var previewWorkItem: DispatchWorkItem?

    init(
        directoryURL: URL,
        pinnedFolder: PinnedFolder,
        isRoot: Bool,
        menuDelegate: FolderMenuPanelDelegate?
    ) {
        self.directoryURL = directoryURL
        self.pinnedFolder = pinnedFolder
        self.isRoot = isRoot
        self.menuDelegate = menuDelegate

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 264, height: 200),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        isMovable = false
        acceptsMouseMovedEvents = true

        setupContainer()
        reloadContents()
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        menuDelegate?.folderPanelDidRequestDismissAll()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            menuDelegate?.folderPanelDidRequestDismissAll()
            return
        }
        super.keyDown(with: event)
    }

    private func setupContainer() {
        containerView.material = .menu
        containerView.blendingMode = .behindWindow
        containerView.state = .active
        containerView.wantsLayer = true
        containerView.layer?.cornerRadius = 12
        containerView.layer?.masksToBounds = true
        containerView.layer?.borderWidth = 0.5
        containerView.layer?.borderColor = NSColor.white.withAlphaComponent(0.16).cgColor
        containerView.targetDirectoryURL = directoryURL
        containerView.onFilesDropped = { [weak self] in
            self?.reloadContents()
        }

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.documentView = documentView

        containerView.addSubview(scrollView)

        if isRoot {
            let footer = makeFooterView()
            containerView.addSubview(footer)

            NSLayoutConstraint.activate([
                scrollView.topAnchor.constraint(equalTo: containerView.topAnchor),
                scrollView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
                scrollView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
                scrollView.bottomAnchor.constraint(equalTo: footer.topAnchor),

                footer.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
                footer.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
                footer.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
                footer.heightAnchor.constraint(equalToConstant: footerHeight)
            ])
        } else {
            NSLayoutConstraint.activate([
                scrollView.topAnchor.constraint(equalTo: containerView.topAnchor),
                scrollView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
                scrollView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
                scrollView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
            ])
        }

        contentView = containerView
    }

    private func makeFooterView() -> NSView {
        let footer = NSView()
        footer.translatesAutoresizingMaskIntoConstraints = false

        let divider = NSBox()
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false
        footer.addSubview(divider)

        let settingsBtn = makeFooterButton(symbol: "gearshape", tooltip: "Settings", action: #selector(openSettingsClicked))
        let sortBtn = makeFooterButton(symbol: "arrow.up.arrow.down", tooltip: "Sort Options", action: #selector(sortClicked(_:)))
        let finderBtn = makeFooterButton(symbol: "sidebar.right", tooltip: "Open in Finder", action: #selector(openInFinderClicked))

        footer.addSubview(settingsBtn)
        footer.addSubview(sortBtn)
        footer.addSubview(finderBtn)

        NSLayoutConstraint.activate([
            divider.topAnchor.constraint(equalTo: footer.topAnchor),
            divider.leadingAnchor.constraint(equalTo: footer.leadingAnchor, constant: 8),
            divider.trailingAnchor.constraint(equalTo: footer.trailingAnchor, constant: -8),

            settingsBtn.leadingAnchor.constraint(equalTo: footer.leadingAnchor, constant: 8),
            settingsBtn.centerYAnchor.constraint(equalTo: footer.centerYAnchor, constant: 1),
            settingsBtn.widthAnchor.constraint(equalToConstant: 24),
            settingsBtn.heightAnchor.constraint(equalToConstant: 24),

            finderBtn.trailingAnchor.constraint(equalTo: footer.trailingAnchor, constant: -8),
            finderBtn.centerYAnchor.constraint(equalTo: footer.centerYAnchor, constant: 1),
            finderBtn.widthAnchor.constraint(equalToConstant: 24),
            finderBtn.heightAnchor.constraint(equalToConstant: 24),

            sortBtn.trailingAnchor.constraint(equalTo: finderBtn.leadingAnchor, constant: -4),
            sortBtn.centerYAnchor.constraint(equalTo: footer.centerYAnchor, constant: 1),
            sortBtn.widthAnchor.constraint(equalToConstant: 24),
            sortBtn.heightAnchor.constraint(equalToConstant: 24)
        ])

        return footer
    }

    private func makeFooterButton(symbol: String, tooltip: String, action: Selector) -> NSButton {
        let btn = NSButton()
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.isBordered = false
        btn.bezelStyle = .regularSquare
        btn.toolTip = tooltip
        btn.target = self
        btn.action = action
        let cfg = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        btn.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)?
            .withSymbolConfiguration(cfg)
        btn.contentTintColor = .secondaryLabelColor
        return btn
    }

    func reloadContents() {
        // Refresh pinnedFolder config from store if still present
        if let latest = AppStore.shared.pinnedFolders.first(where: { $0.id == pinnedFolder.id }) {
            pinnedFolder = latest
        }

        let items = FolderLoader.loadItems(
            in: directoryURL,
            sortField: pinnedFolder.sortField,
            sortOrder: pinnedFolder.sortOrder,
            foldersFirst: pinnedFolder.foldersFirst,
            showHiddenFiles: pinnedFolder.showHiddenFiles,
            showFileExtensions: AppStore.shared.settings.showFileExtensions
        )

        rowViews.forEach { $0.removeFromSuperview() }
        rowViews.removeAll()
        highlightedRow = nil
        documentView.subviews.forEach { $0.removeFromSuperview() }

        let contentWidth = panelWidth - horizontalPadding * 2
        var y = verticalPadding

        if items.isEmpty {
            let emptyLabel = NSTextField(labelWithString: "Empty Folder")
            emptyLabel.font = .systemFont(ofSize: 12.5)
            emptyLabel.textColor = .tertiaryLabelColor
            emptyLabel.alignment = .center
            emptyLabel.frame = NSRect(x: horizontalPadding, y: y + 4, width: contentWidth, height: 22)
            documentView.addSubview(emptyLabel)
            y += 30 + verticalPadding
        } else {
            for item in items {
                let row = FolderRowView(item: item, width: contentWidth)
                row.delegate = self
                row.frame = NSRect(x: horizontalPadding, y: y, width: contentWidth, height: rowHeight)
                documentView.addSubview(row)
                rowViews.append(row)
                y += rowHeight + rowSpacing
            }
            y += verticalPadding - rowSpacing
        }

        documentView.frame = NSRect(x: 0, y: 0, width: panelWidth, height: y)

        let screenHeight = (screen ?? NSScreen.main)?.visibleFrame.height ?? 800
        let maxPanelHeight = floor(screenHeight * 0.72)
        let extraFooter = isRoot ? footerHeight : 0
        let desiredHeight = min(y + extraFooter, maxPanelHeight)

        let currentFrame = frame
        let newOriginY = currentFrame.maxY - desiredHeight
        setFrame(NSRect(x: currentFrame.origin.x, y: newOriginY, width: panelWidth, height: desiredHeight), display: true)
        documentView.scroll(.zero)
    }

    func position(below anchorRect: NSRect) {
        let screenFrame = NSScreen.screens.first(where: { $0.frame.intersects(anchorRect) })?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        var x = anchorRect.midX - panelWidth / 2
        x = max(screenFrame.minX + 8, min(x, screenFrame.maxX - panelWidth - 8))

        let y = max(screenFrame.minY + 8, anchorRect.minY - frame.height - 6)
        setFrameOrigin(NSPoint(x: x, y: y))
    }

    func position(adjacentTo parentFrame: NSRect, alignedWithRowScreenRect rowRect: NSRect) {
        let screenFrame = NSScreen.screens.first(where: { $0.frame.intersects(parentFrame) })?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        let gap: CGFloat = 4
        var x = parentFrame.maxX + gap
        if x + panelWidth > screenFrame.maxX - 8 {
            x = parentFrame.minX - panelWidth - gap
        }
        x = max(screenFrame.minX + 8, x)

        var y = rowRect.maxY - frame.height + verticalPadding
        y = max(screenFrame.minY + 8, min(y, screenFrame.maxY - frame.height - 8))
        setFrameOrigin(NSPoint(x: x, y: y))
    }

    func containsScreenPoint(_ point: NSPoint) -> Bool {
        if frame.contains(point) { return true }
        if let child = childPanel, child.containsScreenPoint(point) { return true }
        return false
    }

    func closeHierarchy() {
        hoverWorkItem?.cancel()
        hoverWorkItem = nil
        previewWorkItem?.cancel()
        previewWorkItem = nil
        childPanel?.closeHierarchy()
        childPanel = nil
        orderOut(nil)
    }

    // MARK: - Footer Actions

    @objc private func openSettingsClicked() {
        menuDelegate?.folderPanelDidRequestDismissAll()
        menuDelegate?.folderPanelDidRequestSettings(selectedFolderID: pinnedFolder.id)
    }

    @objc private func openInFinderClicked() {
        NSWorkspace.shared.open(directoryURL)
        menuDelegate?.folderPanelDidRequestDismissAll()
    }

    @objc private func sortClicked(_ sender: NSButton) {
        let menu = NSMenu()

        for field in SortField.allCases {
            let item = NSMenuItem(title: field.rawValue, action: #selector(selectSortField(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = field
            item.state = pinnedFolder.sortField == field ? .on : .off
            menu.addItem(item)
        }

        menu.addItem(.separator())

        let ascItem = NSMenuItem(title: "Ascending", action: #selector(selectSortOrder(_:)), keyEquivalent: "")
        ascItem.target = self
        ascItem.representedObject = SortOrder.ascending
        ascItem.state = pinnedFolder.sortOrder == .ascending ? .on : .off
        menu.addItem(ascItem)

        let descItem = NSMenuItem(title: "Descending", action: #selector(selectSortOrder(_:)), keyEquivalent: "")
        descItem.target = self
        descItem.representedObject = SortOrder.descending
        descItem.state = pinnedFolder.sortOrder == .descending ? .on : .off
        menu.addItem(descItem)

        menu.addItem(.separator())

        let foldersFirstItem = NSMenuItem(title: "Folders on Top", action: #selector(toggleFoldersFirst), keyEquivalent: "")
        foldersFirstItem.target = self
        foldersFirstItem.state = pinnedFolder.foldersFirst ? .on : .off
        menu.addItem(foldersFirstItem)

        let hiddenItem = NSMenuItem(title: "Show Hidden Files", action: #selector(toggleShowHidden), keyEquivalent: "")
        hiddenItem.target = self
        hiddenItem.state = pinnedFolder.showHiddenFiles ? .on : .off
        menu.addItem(hiddenItem)

        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 4), in: sender)
    }

    @objc private func selectSortField(_ sender: NSMenuItem) {
        guard let field = sender.representedObject as? SortField else { return }
        pinnedFolder.sortField = field
        AppStore.shared.updateFolder(pinnedFolder)
        reloadContents()
    }

    @objc private func selectSortOrder(_ sender: NSMenuItem) {
        guard let order = sender.representedObject as? SortOrder else { return }
        pinnedFolder.sortOrder = order
        AppStore.shared.updateFolder(pinnedFolder)
        reloadContents()
    }

    @objc private func toggleFoldersFirst() {
        pinnedFolder.foldersFirst.toggle()
        AppStore.shared.updateFolder(pinnedFolder)
        reloadContents()
    }

    @objc private func toggleShowHidden() {
        pinnedFolder.showHiddenFiles.toggle()
        AppStore.shared.updateFolder(pinnedFolder)
        reloadContents()
    }

    // MARK: - FolderRowViewDelegate

    func rowDidHover(_ row: FolderRowView) {
        if highlightedRow !== row {
            highlightedRow?.isHighlighted = false
            row.isHighlighted = true
            highlightedRow = row
        }

        hoverWorkItem?.cancel()
        previewWorkItem?.cancel()

        if row.item.isExpandableFolder {
            PreviewPanelController.shared.hide()

            if childPanel?.directoryURL == row.item.url {
                return
            }

            let work = DispatchWorkItem { [weak self, weak row] in
                guard let self, let row, self.highlightedRow === row else { return }
                self.openSubfolderPanel(for: row)
            }
            hoverWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.11, execute: work)
        } else {
            childPanel?.closeHierarchy()
            childPanel = nil

            let work = DispatchWorkItem { [weak self, weak row] in
                guard let self, let row, self.highlightedRow === row else { return }
                let rowInWindow = row.convert(row.bounds, to: nil)
                let rowInScreen = self.convertToScreen(rowInWindow)
                PreviewPanelController.shared.showPreview(
                    for: row.item,
                    anchorRowRectInScreen: rowInScreen,
                    parentPanelFrame: self.frame
                )
            }
            previewWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
        }
    }

    func rowDidClick(_ row: FolderRowView) {
        if row.item.isExpandableFolder {
            hoverWorkItem?.cancel()
            openSubfolderPanel(for: row)
        } else {
            NSWorkspace.shared.open(row.item.url)
            menuDelegate?.folderPanelDidRequestDismissAll()
        }
    }

    func rowDidDoubleClick(_ row: FolderRowView) {
        NSWorkspace.shared.open(row.item.url)
        menuDelegate?.folderPanelDidRequestDismissAll()
    }

    func rowDidStartDragging(_ row: FolderRowView) {
        PreviewPanelController.shared.hide()
        menuDelegate?.folderPanelDidChangeDraggingState(true)
    }

    func rowDidEndDragging(_ row: FolderRowView) {
        menuDelegate?.folderPanelDidChangeDraggingState(false)
    }

    func rowRequestDismissAll() {
        menuDelegate?.folderPanelDidRequestDismissAll()
    }

    func rowRequestRefresh() {
        reloadContents()
    }

    private func openSubfolderPanel(for row: FolderRowView) {
        if childPanel?.directoryURL == row.item.url {
            return
        }
        childPanel?.closeHierarchy()

        let sub = FolderMenuPanel(
            directoryURL: row.item.url,
            pinnedFolder: pinnedFolder,
            isRoot: false,
            menuDelegate: menuDelegate
        )
        let rowInWindow = row.convert(row.bounds, to: nil)
        let rowInScreen = convertToScreen(rowInWindow)
        sub.position(adjacentTo: frame, alignedWithRowScreenRect: rowInScreen)
        sub.orderFront(nil)
        childPanel = sub
    }
}
