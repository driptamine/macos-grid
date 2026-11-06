import Cocoa

private let iconSize: CGFloat = 64
private let cellW: CGFloat = 90
private let cellH: CGFloat = 110
private let cols: Int = 5
private let rows: Int = 5
private let itemsPerPage: Int = cols * rows
private let scrollThreshold: CGFloat = 20

private let cellDragType = NSPasteboard.PasteboardType("com.gridos.cell-index")

class SearchPanelController: NSObject {
    private let window: NSWindow
    private let searchField: NSSearchField
    private let scrollView: NSScrollView
    private let pageContainer: DragTrackView
    private let pageLabel: NSTextField
    private let searchManager = SearchManager()

    private var customOrder: [AppItem?] = []
    private var filteredApps: [AppItem?] = []
    private var pages: Int { max(1, customOrder.count / itemsPerPage) }
    private var totalPages: Int = 1
    private var hasLoaded = false
    private var searchText = ""

    private var isAnimating = false
    private var scrollAccum: CGFloat = 0
    private var turnedInGesture = false
    private var scrollMonitor: Any?
    private var lastDragPageScroll: Date?
    private var leftEdgeIndicator: NSView?
    private var rightEdgeIndicator: NSView?
    private var dragActiveCount = 0
    private var isLayouting = false

    override init() {
        let screen = NSScreen.main ?? NSScreen()
        let w: CGFloat = CGFloat(cols) * cellW + 80
        let h: CGFloat = CGFloat(rows) * cellH + 140
        let x = (screen.frame.width - w) / 2
        let y = (screen.frame.height - h) / 2

        window = NSWindow(
            contentRect: NSRect(x: x, y: y, width: w, height: h),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.level = .floating
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let searchH: CGFloat = 40
        let searchW: CGFloat = min(300, w - 80)
        let searchX = (w - searchW) / 2
        let searchY = h - searchH - 24

        searchField = NSSearchField(frame: NSRect(x: searchX, y: searchY, width: searchW, height: searchH))
        searchField.font = NSFont.systemFont(ofSize: 20, weight: .regular)
        searchField.placeholderString = "Search"
        searchField.focusRingType = .none
        searchField.bezelStyle = .roundedBezel
        searchField.isBordered = false
        searchField.wantsLayer = true
        searchField.layer?.cornerRadius = 10
        searchField.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.15).cgColor
        searchField.textColor = .white
        searchField.placeholderAttributedString = NSAttributedString(
            string: "Search", attributes: [.foregroundColor: NSColor.white.withAlphaComponent(0.5)]
        )

        let gridY: CGFloat = 52
        let clipH = h - gridY - 40
        let scrollFrame = NSRect(x: 0, y: gridY, width: w, height: clipH)

        pageContainer = DragTrackView(frame: NSRect(x: 0, y: 0, width: w, height: clipH))

        scrollView = NSScrollView(frame: scrollFrame)
        scrollView.drawsBackground = false
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.borderType = .noBorder
        scrollView.documentView = pageContainer
        scrollView.horizontalScrollElasticity = .none
        scrollView.verticalScrollElasticity = .none

        pageLabel = NSTextField(labelWithString: "")
        pageLabel.frame = NSRect(x: 0, y: 14, width: w, height: 16)
        pageLabel.alignment = .center
        pageLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        pageLabel.textColor = NSColor.white.withAlphaComponent(0.5)

        let blur = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: w, height: h))
        blur.appearance = NSAppearance(named: .vibrantDark)
        blur.material = NSVisualEffectView.Material.sidebar
        blur.state = NSVisualEffectView.State.active
        blur.blendingMode = NSVisualEffectView.BlendingMode.behindWindow

        let dimView = NSView(frame: NSRect(x: 0, y: 0, width: w, height: h))
        dimView.wantsLayer = true
        dimView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.25).cgColor

        let overlay = NSView(frame: NSRect(x: 0, y: 0, width: w, height: h))
        overlay.addSubview(blur)
        overlay.addSubview(dimView)
        overlay.addSubview(searchField)
        overlay.addSubview(scrollView)
        overlay.addSubview(pageLabel)

        window.contentView = overlay

        let edgeW: CGFloat = 40
        let edgeH = scrollFrame.height

        let leftEdge = NSView(frame: NSRect(x: scrollFrame.origin.x, y: scrollFrame.origin.y, width: edgeW, height: edgeH))
        leftEdge.wantsLayer = true
        leftEdge.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
        leftEdge.layer?.cornerRadius = 8
        leftEdge.alphaValue = 0
        let leftLabel = NSTextField(labelWithString: "❮")
        leftLabel.frame = NSRect(x: 8, y: (edgeH - 24) / 2, width: 24, height: 24)
        leftLabel.font = NSFont.systemFont(ofSize: 20)
        leftLabel.textColor = NSColor.white.withAlphaComponent(0.5)
        leftEdge.addSubview(leftLabel)
        overlay.addSubview(leftEdge)
        leftEdgeIndicator = leftEdge

        let rightEdge = NSView(frame: NSRect(x: scrollFrame.maxX - edgeW, y: scrollFrame.origin.y, width: edgeW, height: edgeH))
        rightEdge.wantsLayer = true
        rightEdge.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
        rightEdge.layer?.cornerRadius = 8
        rightEdge.alphaValue = 0
        let rightLabel = NSTextField(labelWithString: "❯")
        rightLabel.frame = NSRect(x: 8, y: (edgeH - 24) / 2, width: 24, height: 24)
        rightLabel.font = NSFont.systemFont(ofSize: 20)
        rightLabel.textColor = NSColor.white.withAlphaComponent(0.5)
        rightEdge.addSubview(rightLabel)
        overlay.addSubview(rightEdge)
        rightEdgeIndicator = rightEdge

        super.init()

        searchField.delegate = self

        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self = self, event.window == self.window else { return event }
            self.handlePageScroll(event)
            return nil
        }

        searchManager.onResults = { [weak self] apps in
            DispatchQueue.main.async {
                guard let s = self else { return }
                if !s.hasLoaded {
                    let totalSlots = ((apps.count + itemsPerPage - 1) / itemsPerPage) * itemsPerPage
                    var slots: [AppItem?] = Array(repeating: nil, count: max(totalSlots, itemsPerPage))
                    for (i, app) in apps.enumerated() {
                        slots[i] = app
                        app.order = i
                    }
                    s.customOrder = slots
                    s.hasLoaded = true
                }
                s.applySearch()
            }
        }
        searchManager.loadApps()
    }

    private func handlePageScroll(_ event: NSEvent) {
        guard totalPages > 1 else { return }

        let dx = event.scrollingDeltaX
        let dy = event.scrollingDeltaY
        let delta = abs(dx) > abs(dy) ? dx : dy

        if event.phase == .began {
            scrollAccum = 0
            turnedInGesture = false
        } else if event.phase == .ended || event.phase == .cancelled {
            scrollAccum = 0
            turnedInGesture = false
            return
        }

        guard !turnedInGesture else { return }

        scrollAccum += delta
        guard abs(scrollAccum) > scrollThreshold else { return }

        turnedInGesture = true
        let pageW = scrollView.bounds.width
        guard pageW > 0 else { return }
        let currentPage = Int(round(scrollView.contentView.bounds.origin.x / pageW))
        let dir = scrollAccum < 0 ? 1 : -1
        let nextPage = max(0, min(currentPage + dir, totalPages - 1))
        guard nextPage != currentPage else { scrollAccum = 0; return }

        scrollAccum = 0
        animateToPage(nextPage)
    }

    private func handleDragAutoScroll() {
        guard totalPages > 1, !isAnimating else { return }

        let now = Date()
        if let last = lastDragPageScroll, now.timeIntervalSince(last) < 0.6 { return }

        let mouseScreen = NSEvent.mouseLocation
        let wx = mouseScreen.x - window.frame.origin.x
        let wy = mouseScreen.y - window.frame.origin.y
        let scrollFrame = scrollView.frame
        guard wy >= scrollFrame.minY, wy <= scrollFrame.maxY else { return }

        let pageW = scrollView.bounds.width
        let gridW = CGFloat(cols) * cellW + CGFloat(cols - 1) * 12
        let gridX = (pageW - gridW) / 2
        let currentPage = Int(round(scrollView.contentView.bounds.origin.x / pageW))

        let nearLeft = wx < gridX
        let nearRight = wx > pageW - gridX

        leftEdgeIndicator?.layer?.backgroundColor = (nearLeft && currentPage > 0)
            ? NSColor.white.withAlphaComponent(0.2).cgColor
            : NSColor.white.withAlphaComponent(0.08).cgColor
        rightEdgeIndicator?.layer?.backgroundColor = (nearRight && currentPage < totalPages - 1)
            ? NSColor.white.withAlphaComponent(0.2).cgColor
            : NSColor.white.withAlphaComponent(0.08).cgColor

        if nearLeft, currentPage > 0 {
            lastDragPageScroll = now
            animateToPage(currentPage - 1)
        } else if nearRight, currentPage < totalPages - 1 {
            lastDragPageScroll = now
            animateToPage(currentPage + 1)
        }
    }

    private func showDragIndicators() {
        guard totalPages > 1 else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            leftEdgeIndicator?.animator().alphaValue = 1
            rightEdgeIndicator?.animator().alphaValue = 1
        }
    }

    private func hideDragIndicators() {
        guard dragActiveCount <= 0 else { return }
        leftEdgeIndicator?.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
        rightEdgeIndicator?.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            leftEdgeIndicator?.animator().alphaValue = 0
            rightEdgeIndicator?.animator().alphaValue = 0
        }
    }

    private func applySearch() {
        if searchText.isEmpty {
            filteredApps = customOrder
        } else {
            filteredApps = customOrder.map {
                guard let app = $0, app.name.localizedCaseInsensitiveContains(searchText) else { return nil }
                return app
            }
        }
        layoutApps()
    }

    private func animateToPage(_ page: Int) {
        isAnimating = true
        updatePageLabel(page: page)

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            ctx.completionHandler = { [weak self] in self?.isAnimating = false }
            scrollView.contentView.animator().setBoundsOrigin(NSPoint(x: CGFloat(page) * scrollView.bounds.width, y: 0))
        }
    }

    private func frameForApp(at index: Int, pageW: CGFloat, gridX: CGFloat) -> NSRect {
        let pageIdx = index / itemsPerPage
        let posInPage = index % itemsPerPage
        let col = posInPage % cols
        let row = posInPage / cols
        let x = CGFloat(pageIdx) * pageW + gridX + CGFloat(col) * (cellW + 12)
        let y = CGFloat(rows - 1 - row) * (cellH + 8)
        return NSRect(x: x, y: y, width: cellW, height: cellH)
    }

    private func layoutApps() {
        isLayouting = true
        pageContainer.subviews.forEach { $0.removeFromSuperview() }

        let pageW = scrollView.bounds.width
        totalPages = pages
        pageContainer.frame = NSRect(x: 0, y: 0, width: pageW * CGFloat(totalPages), height: pageContainer.bounds.height)

        let gridW = CGFloat(cols) * cellW + CGFloat(cols - 1) * 12
        let gridX = (pageW - gridW) / 2

        pageContainer.onDragUpdate = { [weak self] _ in self?.handleDragAutoScroll() }
        pageContainer.onDragEnter = { [weak self] in self?.dragActiveCount += 1; self?.showDragIndicators() }
        pageContainer.onDragExit = { [weak self] in
            guard let s = self else { return }
            s.dragActiveCount = max(0, s.dragActiveCount - 1)
            if s.dragActiveCount <= 0, !s.isLayouting { s.hideDragIndicators() }
        }

        for (idx, app) in filteredApps.enumerated() {
            if let app = app {
                let cell = AppIconCell(frame: frameForApp(at: idx, pageW: pageW, gridX: gridX))
                cell.index = idx
                cell.onReorder = { [weak self] src, dst in self?.swapApps(src, dst) }
                cell.onDragUpdate = { [weak self] _ in self?.handleDragAutoScroll() }
                cell.onDragEnter = { [weak self] in self?.dragActiveCount += 1; self?.showDragIndicators() }
                cell.onDragExit = { [weak self] in
                    guard let s = self else { return }
                    s.dragActiveCount = max(0, s.dragActiveCount - 1)
                    if s.dragActiveCount <= 0, !s.isLayouting { s.hideDragIndicators() }
                }
                cell.configure(with: app)
                pageContainer.addSubview(cell)
            } else {
                let placeholder = DropPlaceholder(frame: frameForApp(at: idx, pageW: pageW, gridX: gridX))
                placeholder.slotIndex = idx
                placeholder.onReorder = { [weak self] src, dst in self?.swapApps(src, dst) }
                placeholder.onDragUpdate = { [weak self] _ in self?.handleDragAutoScroll() }
                placeholder.onDragEnter = { [weak self] in self?.dragActiveCount += 1; self?.showDragIndicators() }
                placeholder.onDragExit = { [weak self] in
                    guard let s = self else { return }
                    s.dragActiveCount = max(0, s.dragActiveCount - 1)
                    if s.dragActiveCount <= 0, !s.isLayouting { s.hideDragIndicators() }
                }
                pageContainer.addSubview(placeholder)
            }
        }

        updatePageLabel(page: 0)
        scrollView.contentView.scroll(to: .zero)
        scrollView.reflectScrolledClipView(scrollView.contentView)
        isLayouting = false
    }

    private func swapApps(_ src: Int, _ dst: Int) {
        guard !searchText.isEmpty == false,
              src != dst,
              src >= 0, src < customOrder.count,
              dst >= 0, dst < customOrder.count,
              customOrder[src] != nil
        else { return }

        let movedApp = customOrder[src]!
        customOrder[src] = nil

        if src < dst {
            for i in (src + 1)...dst {
                customOrder[i - 1] = customOrder[i]
            }
        } else {
            for i in stride(from: src - 1, through: dst, by: -1) {
                customOrder[i + 1] = customOrder[i]
            }
        }

        customOrder[dst] = movedApp

        for i in 0..<customOrder.count {
            if let app = customOrder[i] { app.order = i }
        }

        if searchText.isEmpty {
            filteredApps = customOrder
        }

        let savedPage = min(
            Int(round(scrollView.contentView.bounds.origin.x / scrollView.bounds.width)),
            totalPages - 1
        )
        layoutApps()
        if savedPage != 0 {
            animateToPage(savedPage)
        }
    }

    private func updatePageLabel(page: Int) {
        pageLabel.stringValue = totalPages > 1 ? "\(page + 1) / \(totalPages)" : ""
    }

    func toggle() {
        if window.isVisible { hide() } else { show() }
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(searchField)
        NSApp.activate(ignoringOtherApps: true)
        searchField.stringValue = ""
        searchText = ""
        filteredApps = customOrder
        layoutApps()
    }

    private func hide() {
        window.orderOut(nil)
    }
}

extension SearchPanelController: NSSearchFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        searchText = searchField.stringValue
        applySearch()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            hide()
            return true
        }
        return false
    }
}

class AppIconCell: NSView, NSDraggingSource {
    private let iconView = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private(set) var appItem: AppItem?

    var index: Int = 0
    var onReorder: ((Int, Int) -> Void)?
    var onDragUpdate: ((NSPoint) -> Void)?
    var onDragEnter: (() -> Void)?
    var onDragExit: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        registerForDraggedTypes([cellDragType])

        iconView.frame = NSRect(x: (frame.width - iconSize) / 2, y: 38, width: iconSize, height: iconSize)
        iconView.imageScaling = .scaleProportionallyUpOrDown
        addSubview(iconView)

        nameLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        nameLabel.textColor = .white
        nameLabel.alignment = .center
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.maximumNumberOfLines = 2
        nameLabel.frame = NSRect(x: 2, y: 4, width: frame.width - 4, height: 30)
        addSubview(nameLabel)
    }

    required init?(coder: NSCoder) { nil }

    private var didDrag = false

    override func mouseDown(with event: NSEvent) {
        didDrag = false
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.2).cgColor
        layer?.cornerRadius = 12
    }

    override func mouseUp(with event: NSEvent) {
        if !didDrag {
            // app opening disabled
        }
        layer?.backgroundColor = nil
        layer?.cornerRadius = 0
    }

    override func mouseDragged(with event: NSEvent) {
        didDrag = true
        let pbItem = NSPasteboardItem()
        pbItem.setString("\(index)", forType: cellDragType)

        let dragImage = snapshot()
        let draggingItem = NSDraggingItem(pasteboardWriter: pbItem)
        draggingItem.setDraggingFrame(bounds, contents: dragImage)

        beginDraggingSession(with: [draggingItem], event: event, source: self)
    }

    private func snapshot() -> NSImage {
        let img = NSImage(size: bounds.size)
        img.lockFocusFlipped(false)
        guard let ctx = NSGraphicsContext.current?.cgContext else {
            img.unlockFocus()
            return img
        }
        ctx.setFillColor(NSColor.clear.cgColor)
        ctx.fill(bounds)
        layer?.render(in: ctx)
        img.unlockFocus()
        return img
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        onDragEnter?()
        layer?.borderWidth = 3
        layer?.borderColor = NSColor.white.withAlphaComponent(0.5).cgColor
        layer?.cornerRadius = 12
        return .move
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        if sender.draggingSource as? AppIconCell === self {
            layer?.borderWidth = 0
            layer?.borderColor = nil
        }
        onDragUpdate?(convert(sender.draggingLocation, to: nil))
        return .move
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onDragExit?()
        layer?.borderWidth = 0
        layer?.borderColor = nil
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        layer?.borderWidth = 0
        layer?.borderColor = nil
        guard let src = sourceIndex(from: sender), src != index else { return false }
        onReorder?(src, index)
        return true
    }

    private func sourceIndex(from sender: NSDraggingInfo) -> Int? {
        guard let item = sender.draggingPasteboard.pasteboardItems?.first,
              let str = item.string(forType: cellDragType)
        else { return nil }
        return Int(str)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        return .move
    }

    func configure(with app: AppItem) {
        appItem = app
        iconView.image = app.icon
        nameLabel.stringValue = app.name
    }
}

class DropPlaceholder: NSView {
    var slotIndex: Int = 0
    var onReorder: ((Int, Int) -> Void)?
    var onDragUpdate: ((NSPoint) -> Void)?
    var onDragEnter: (() -> Void)?
    var onDragExit: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        registerForDraggedTypes([cellDragType])
    }

    required init?(coder: NSCoder) { nil }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard sender.draggingSource is AppIconCell else { return [] }
        onDragEnter?()
        layer?.borderWidth = 3
        layer?.borderColor = NSColor.white.withAlphaComponent(0.5).cgColor
        layer?.cornerRadius = 12
        return .move
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        onDragUpdate?(convert(sender.draggingLocation, to: nil))
        return .move
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onDragExit?()
        layer?.borderWidth = 0
        layer?.borderColor = nil
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        layer?.borderWidth = 0
        layer?.borderColor = nil
        guard let item = sender.draggingPasteboard.pasteboardItems?.first,
              let str = item.string(forType: cellDragType),
              let src = Int(str),
              src != slotIndex
        else { return false }
        onReorder?(src, slotIndex)
        return true
    }
}

class DragTrackView: NSView {
    var onDragUpdate: ((NSPoint) -> Void)?
    var onDragEnter: (() -> Void)?
    var onDragExit: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([cellDragType])
    }

    required init?(coder: NSCoder) { nil }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard sender.draggingSource is AppIconCell else { return [] }
        onDragEnter?()
        return .move
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        onDragUpdate?(convert(sender.draggingLocation, to: nil))
        return .move
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onDragExit?()
    }
}
