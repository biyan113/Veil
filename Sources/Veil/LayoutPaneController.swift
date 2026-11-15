import AppKit

private extension NSPasteboard.PasteboardType {
    static let veilItem = NSPasteboard.PasteboardType("net.bytenote.veil.item")
}

/// 「布局」面板：上面是菜单栏上的全部图标（只是挑选器，菜单栏本身不会被改动），
/// 下面是点 Veil 时弹出的那一组。从上往下拖 = 收进 Veil，从下面拖走 = 移除。
@MainActor
final class LayoutPaneController: NSViewController {
    fileprivate enum Zone { case all, veil }

    private static let width: CGFloat = 520
    private static let contentWidth: CGFloat = width - 48
    private static let flowWidth: CGFloat = contentWidth - 20

    private let menuBar: MenuBarController
    private var items: [MenuBarItem] = []
    /// 下面那组按收藏顺序的全部条目，含没在运行的占位条目
    private var veilEntries: [MenuBarItem] = []
    private var trustTimer: Timer?

    private let spinner = NSProgressIndicator()
    private let statusLabel = NSTextField(labelWithString: "")
    private let onboarding = NSStackView()
    private lazy var accessibilityStep = OnboardingStep(
        number: 1, title: "辅助功能", tag: "必需",
        detail: "用来读取菜单栏上的图标，并在你从 Veil 里点按时替你打开它们。",
        action: { [weak self] in
            MenuBarItemScanner.requestTrust()
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
            self?.waitForTrust()
        })
    private let glyphStep = OnboardingStep(
        number: 2, title: "屏幕录制", tag: "可选",
        detail: "用来显示图标在菜单栏里的真实样子。不授予时用应用图标代替。截图只保存在这台 Mac 上，不会上传。授权后若没有变化，请重新打开 Veil。",
        action: { GlyphCache.requestPermission() })
    private let refreshButton = NSButton()
    private let allTitle = SectionTitle(symbol: "menubar.rectangle", title: "菜单栏上的全部图标")
    private let veilTitle = SectionTitle(symbol: "tray", title: "点 Veil 时显示")
    private lazy var allZone = DropZone(zone: .all, controller: self)
    private lazy var veilZone = DropZone(zone: .veil, controller: self)
    private let allFlow = ChipFlow()
    private let veilFlow = ChipFlow()
    private let veilEmpty = NSTextField(labelWithString: "从上面把想收进 Veil 的图标拖到这里（或直接点它）")
    private let content = NSStackView()

    init(menuBar: MenuBarController) {
        self.menuBar = menuBar
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let title = NSTextField(labelWithString: "Veil 里的图标")
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        let subtitle = NSTextField(wrappingLabelWithString: "菜单栏保持原样。把常用的图标拖到下面，点 Veil 就能随时打开它们——被刘海挡住的也一样。")
        subtitle.textColor = .secondaryLabelColor
        subtitle.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        subtitle.preferredMaxLayoutWidth = 420

        refreshButton.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "刷新")
        refreshButton.bezelStyle = .accessoryBarAction
        refreshButton.isBordered = false
        refreshButton.focusRingType = .none
        refreshButton.contentTintColor = .secondaryLabelColor
        refreshButton.toolTip = "刷新"
        refreshButton.onAction { [weak self] _ in self?.reload() }

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false

        let titleStack = NSStackView(views: [title, subtitle])
        titleStack.orientation = .vertical
        titleStack.alignment = .leading
        titleStack.spacing = 3
        let header = NSStackView(views: [titleStack, NSView(), spinner, refreshButton])
        header.alignment = .top

        buildOnboarding()
        buildZones()
        for name in [GlyphCache.didUpdate, VeilCollection.didChange] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                // 看不见时不用重建，下次打开会重新加载
                MainActor.assumeIsolated { if self?.view.window?.isVisible == true { self?.rebuildChips() } }
            }
        }

        statusLabel.textColor = .tertiaryLabelColor
        statusLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        statusLabel.lineBreakMode = .byTruncatingTail

        let root = NSStackView(views: [header, onboarding, content, statusLabel])
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 14
        root.edgeInsets = NSEdgeInsets(top: 20, left: 24, bottom: 16, right: 24)
        for v in [header, onboarding, content] {
            v.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -48).isActive = true
        }
        root.widthAnchor.constraint(equalToConstant: Self.width).isActive = true
        view = root

        // 屏幕录制授权后要真的截一次才能确认，从系统设置回来时重新检查即可，不必轮询
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.view.window?.isVisible == true, !self.onboarding.isHidden else { return }
                self.reload()
            }
        }
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        reload()
    }

    override func viewDidDisappear() {
        super.viewDidDisappear()
        trustTimer?.invalidate()
        trustTimer = nil
    }

    // MARK: - 构建界面

    /// 首次使用的两步引导：完成的打勾，全部完成后整块收起
    private func buildOnboarding() {
        let title = NSTextField(labelWithString: "开始使用前，请完成下面两步")
        title.font = .systemFont(ofSize: 12, weight: .semibold)
        onboarding.setViews([title, accessibilityStep, glyphStep], in: .leading)
        onboarding.orientation = .vertical
        onboarding.alignment = .leading
        onboarding.spacing = 10
        onboarding.edgeInsets = NSEdgeInsets(top: 12, left: 14, bottom: 12, right: 14)
        onboarding.wantsLayer = true
        onboarding.layer?.cornerRadius = 10
        onboarding.layer?.backgroundColor = NSColor.systemOrange.withAlphaComponent(0.08).cgColor
        for step in [accessibilityStep, glyphStep] {
            step.widthAnchor.constraint(equalTo: onboarding.widthAnchor, constant: -28).isActive = true
        }
    }

    private func updateOnboarding() {
        let trusted = MenuBarItemScanner.isTrusted, glyphs = GlyphCache.hasPermission
        accessibilityStep.isDone = trusted
        glyphStep.isDone = glyphs
        // 必需的那步没完成时，回车直接去授权
        accessibilityStep.isDefault = !trusted
        onboarding.isHidden = trusted && glyphs
        onboarding.layer?.backgroundColor = (trusted ? NSColor.systemBlue : NSColor.systemOrange).withAlphaComponent(0.08).cgColor
    }

    private func buildZones() {
        allZone.embed(allFlow)
        veilEmpty.textColor = .tertiaryLabelColor
        veilEmpty.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        veilEmpty.alignment = .center
        veilEmpty.widthAnchor.constraint(equalToConstant: Self.flowWidth).isActive = true
        let veilStack = NSStackView(views: [veilFlow, veilEmpty])
        veilStack.orientation = .vertical
        veilStack.spacing = 0
        veilZone.embed(veilStack)
        veilZone.heightAnchor.constraint(greaterThanOrEqualToConstant: 60).isActive = true

        let hint = NSTextField(labelWithString: "点上面的图标即可加入或移除 · 在下面拖动可调整顺序 · 拖回上面即移除")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .tertiaryLabelColor

        content.setViews([allTitle, allZone, veilTitle, veilZone, hint], in: .leading)
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 8
        content.setCustomSpacing(18, after: allZone)
        for v in [allZone, veilZone] {
            v.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        }
    }

    // MARK: - 数据

    private func reload() {
        let trusted = MenuBarItemScanner.isTrusted
        updateOnboarding()
        content.isHidden = !trusted
        refreshButton.isHidden = !trusted
        guard trusted else {
            items = []
            rebuildChips()
            statusLabel.stringValue = ""
            // 用户可能直接去系统设置里授权，不经过这里的按钮
            waitForTrust()
            return
        }
        spinner.startAnimation(nil)
        Task {
            // 菜单栏里从左到右的真实顺序；系统的「«」按钮不是图标，不列出来
            items = await MenuBarItemScanner.scan()
                .filter { !$0.isSystemOverflowButton }
                .sorted { $0.frame.minX < $1.frame.minX }
            let snapshot = items
            Task { await GlyphCache.shared.capture(snapshot) }
            spinner.stopAnimation(nil)
            rebuildChips()
        }
    }

    private func rebuildChips() {
        veilEntries = VeilCollection.entries(from: items)
        let inVeil = veilEntries.filter { !$0.isMissing }
        let veilKeys = Set(inVeil.map(\.key))

        var allViews: [NSView] = items.map { ItemChip(item: $0, zone: .all, checked: veilKeys.contains($0.key), controller: self) }
        if let x = menuBar.toggleFrame?.minX {
            allViews.insert(VeilChip(), at: items.firstIndex { $0.frame.minX > x } ?? items.count)
        }
        allFlow.setItems(allViews, maxWidth: Self.flowWidth)

        veilFlow.setItems(veilEntries.map { ItemChip(item: $0, zone: .veil, checked: false, controller: self) }, maxWidth: Self.flowWidth)
        veilFlow.isHidden = veilEntries.isEmpty
        veilEmpty.isHidden = !veilEntries.isEmpty

        allTitle.count = items.count
        veilTitle.count = veilEntries.count
        let missing = veilEntries.count - inVeil.count
        statusLabel.stringValue = items.isEmpty ? ""
            : missing == 0 ? String(format: "菜单栏共 %d 个图标，其中 %d 个收进了 Veil", items.count, inVeil.count)
            : String(format: "菜单栏共 %d 个图标，其中 %d 个收进了 Veil；另有 %d 个收进的图标当前不在菜单栏上", items.count, inVeil.count, missing)
        updateOnboarding()
        fitWindow()
    }

    private func fitWindow() {
        // 标签页控制器会把视图钉在旧尺寸上，这里按可见内容手动算高度
        guard let root = view as? NSStackView else { return }
        root.layoutSubtreeIfNeeded()
        let visible = root.arrangedSubviews.filter { !$0.isHidden }
        let height = root.edgeInsets.top + root.edgeInsets.bottom
            + visible.reduce(0) { $0 + $1.fittingSize.height }
            + root.spacing * CGFloat(max(visible.count - 1, 0))
        fitSettingsWindow(to: NSSize(width: Self.width, height: ceil(height)))
    }

    private func waitForTrust() {
        trustTimer?.invalidate()
        trustTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard MenuBarItemScanner.isTrusted else { return }
                timer.invalidate()
                self?.reload()
            }
        }
    }

    // MARK: - 操作

    fileprivate func item(forKey key: String) -> MenuBarItem? {
        items.first { $0.key == key } ?? veilEntries.first { $0.key == key }
    }

    fileprivate func toggle(_ item: MenuBarItem) {
        VeilCollection.contains(item) ? VeilCollection.remove(item) : VeilCollection.add(item)
    }

    /// 拖进某个区域：下面 = 收进 Veil（插到松手的位置），上面 = 移除
    fileprivate func drop(_ key: String, into zone: Zone, at point: NSPoint, in view: NSView) -> Bool {
        guard let item = item(forKey: key) else { return false }
        switch zone {
        case .all:
            guard VeilCollection.contains(item) else { return false }
            VeilCollection.remove(item)
        case .veil:
            let local = veilFlow.convert(point, from: view)
            let index = veilFlow.isHidden ? 0 : veilFlow.insertionIndex(at: local)
            // 插入位置是按当前显示的图标算的，换算成收藏列表里的位置
            let shown = veilEntries.map(\.key)
            let target = index < shown.count ? VeilCollection.keys.firstIndex(of: shown[index]) : nil
            VeilCollection.add(item, at: target)
        }
        return true
    }

    /// 旁白用：在 Veil 那组里前后挪一位
    fileprivate func move(_ item: MenuBarItem, by delta: Int) -> Bool {
        guard let index = VeilCollection.keys.firstIndex(of: item.key) else { return false }
        let target = index + delta
        guard target >= 0, target < VeilCollection.keys.count else { return false }
        VeilCollection.add(item, at: delta > 0 ? target + 1 : target)
        return true
    }
}

extension NSMenuItem {
    private static var handlerKey: UInt8 = 0
    func onAction(_ handler: @escaping (Any) -> Void) {
        let h = ActionHandler(handler)
        objc_setAssociatedObject(self, &Self.handlerKey, h, .OBJC_ASSOCIATION_RETAIN)
        target = h
        action = #selector(ActionHandler.fire(_:))
    }
}

// MARK: - 首次使用引导

/// 引导里的一步：序号（完成后变成勾）、名称、是否必需、说明、授权按钮
private final class OnboardingStep: NSStackView {
    private let badge = NSImageView()
    private let button: NSButton
    private let done = NSTextField(labelWithString: "已完成")
    private let number: Int

    var isDone = false { didSet { update() } }
    var isDefault = false { didSet { button.keyEquivalent = isDefault ? "\r" : "" } }

    init(number: Int, title: String, tag: String, detail: String, action: @escaping () -> Void) {
        self.number = number
        button = NSButton(title: "授予权限…", target: nil, action: nil)
        super.init(frame: .zero)
        badge.symbolConfiguration = .init(pointSize: 17, weight: .regular)

        let name = NSTextField(labelWithString: title)
        name.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        let tagLabel = NSTextField(labelWithString: tag)
        tagLabel.font = .systemFont(ofSize: 10.5, weight: .medium)
        tagLabel.textColor = .secondaryLabelColor
        let titleRow = NSStackView(views: [name, tagLabel])
        titleRow.spacing = 6
        titleRow.alignment = .firstBaseline
        let text = NSTextField(wrappingLabelWithString: detail)
        text.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        text.textColor = .secondaryLabelColor
        text.preferredMaxLayoutWidth = 300
        let texts = NSStackView(views: [titleRow, text])
        texts.orientation = .vertical
        texts.alignment = .leading
        texts.spacing = 2

        button.bezelStyle = .push
        button.onAction { _ in action() }
        done.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        done.textColor = .secondaryLabelColor

        setViews([badge, texts, NSView(), button, done], in: .leading)
        alignment = .top
        spacing = 10
        setAccessibilityElement(false)
        update()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func update() {
        badge.image = NSImage(systemSymbolName: isDone ? "checkmark.circle.fill" : "\(number).circle",
                              accessibilityDescription: isDone ? "已完成" : "未完成")
        badge.contentTintColor = isDone ? .systemGreen : .secondaryLabelColor
        button.isHidden = isDone
        done.isHidden = !isDone
    }
}

// MARK: - 分区标题

private final class SectionTitle: NSStackView {
    private let badge = NSTextField(labelWithString: "")
    var count = 0 { didSet { badge.stringValue = "\(count)" } }

    init(symbol: String, title: String) {
        super.init(frame: .zero)
        let icon = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil)!)
        icon.contentTintColor = .secondaryLabelColor
        icon.symbolConfiguration = .init(pointSize: 11, weight: .semibold)
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.textColor = .secondaryLabelColor
        badge.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        badge.textColor = .tertiaryLabelColor
        setViews([icon, label, badge], in: .leading)
        spacing = 6
        edgeInsets = NSEdgeInsets(top: 0, left: 2, bottom: 0, right: 0)
    }

    required init?(coder: NSCoder) { fatalError() }
}

// MARK: - 拖放区域

private final class DropZone: NSView {
    let zone: LayoutPaneController.Zone
    private weak var controller: LayoutPaneController?
    private var isTargeted = false { didSet { needsDisplay = true } }

    init(zone: LayoutPaneController.Zone, controller: LayoutPaneController) {
        self.zone = zone
        self.controller = controller
        super.init(frame: .zero)
        wantsLayer = true
        registerForDraggedTypes([.veilItem])
    }

    required init?(coder: NSCoder) { fatalError() }

    func embed(_ child: NSView) {
        child.translatesAutoresizingMaskIntoConstraints = false
        addSubview(child)
        NSLayoutConstraint.activate([
            child.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            child.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            child.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            child.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
        ])
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        guard let layer else { return }
        let isBar = zone == .all
        layer.cornerRadius = isBar ? 10 : 12
        layer.borderWidth = isTargeted ? 2 : 1
        if isTargeted {
            layer.borderColor = NSColor.controlAccentColor.cgColor
            layer.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.1).cgColor
        } else {
            layer.borderColor = NSColor.separatorColor.cgColor
            // 上面用稍深的底色模拟菜单栏，下面是 Veil 托盘的浅色卡片
            layer.backgroundColor = NSColor.labelColor.withAlphaComponent(isBar ? 0.07 : 0.03).cgColor
        }
    }

    private func key(_ info: NSDraggingInfo) -> String? { info.draggingPasteboard.string(forType: .veilItem) }

    private func accepts(_ info: NSDraggingInfo) -> Bool {
        guard let key = key(info), let item = controller?.item(forKey: key) else { return false }
        // 上面只接收从 Veil 拖回来的；下面什么都接收（包括在 Veil 内调整顺序）
        return zone == .veil || VeilCollection.contains(item)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        isTargeted = accepts(sender)
        return isTargeted ? .move : []
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        isTargeted ? .move : []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) { isTargeted = false }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        defer { isTargeted = false }
        guard accepts(sender), let key = key(sender), let controller else { return false }
        return controller.drop(key, into: zone, at: convert(sender.draggingLocation, from: nil), in: self)
    }
}

// MARK: - 图标

/// 自动折行排列
private final class ChipFlow: NSView {
    private let spacing: CGFloat = 4
    private var sizeConstraints: [NSLayoutConstraint] = []
    override var isFlipped: Bool { true }

    func setItems(_ views: [NSView], maxWidth: CGFloat) {
        subviews.forEach { $0.removeFromSuperview() }
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for v in views {
            let s = v.fittingSize
            if x > 0, x + s.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            v.frame = NSRect(origin: NSPoint(x: x, y: y), size: s)
            addSubview(v)
            x += s.width + spacing
            rowHeight = max(rowHeight, s.height)
        }
        NSLayoutConstraint.deactivate(sizeConstraints)
        sizeConstraints = [widthAnchor.constraint(equalToConstant: maxWidth),
                           heightAnchor.constraint(equalToConstant: y + rowHeight)]
        NSLayoutConstraint.activate(sizeConstraints)
    }

    /// 松手位置对应的插入序号（按行从左到右）
    func insertionIndex(at p: NSPoint) -> Int {
        for (i, v) in subviews.enumerated() {
            if p.y < v.frame.minY { return i }
            if p.y <= v.frame.maxY + spacing, p.x < v.frame.midX { return i }
        }
        return subviews.count
    }
}

/// 一个图标：真实外观优先，没有时用应用图标
private final class ItemChip: NSView, NSDraggingSource {
    private static let height: CGFloat = 28

    private let item: MenuBarItem
    private let zone: LayoutPaneController.Zone
    private weak var controller: LayoutPaneController?
    private let highlight = CALayer()
    private var downEvent: NSEvent?
    private var didDrag = false

    init(item: MenuBarItem, zone: LayoutPaneController.Zone, checked: Bool, controller: LayoutPaneController) {
        self.item = item
        self.zone = zone
        self.controller = controller
        let icon = NSImageView()
        var iconSize = NSSize(width: 18, height: 18)
        // 没在菜单栏上的条目用应用图标并置灰，一眼和能用的区分开
        if !item.isMissing, let glyph = GlyphCache.shared.image(for: item) {
            icon.image = glyph
            icon.imageScaling = .scaleNone
            icon.contentTintColor = .labelColor
            iconSize = NSSize(width: glyph.size.width, height: min(glyph.size.height, Self.height))
        } else {
            icon.image = item.appIcon
            icon.imageScaling = .scaleProportionallyUpOrDown
        }
        let width = max(Self.height, iconSize.width + 12)
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: Self.height))
        wantsLayer = true
        highlight.cornerRadius = 6
        layer?.addSublayer(highlight)

        icon.frame = NSRect(x: (width - iconSize.width) / 2, y: (Self.height - iconSize.height) / 2,
                            width: iconSize.width, height: iconSize.height)
        addSubview(icon)
        if item.isMissing { icon.alphaValue = 0.35 }

        // 上面已经收进 Veil 的图标：底色标出 + 右下角小勾
        if checked {
            highlight.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.16).cgColor
            let mark = NSImageView(image: NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: "已收进 Veil")!)
            mark.symbolConfiguration = .init(pointSize: 9, weight: .bold)
            mark.contentTintColor = .controlAccentColor
            mark.frame = NSRect(x: width - 11, y: 0, width: 11, height: 11)
            addSubview(mark)
        }
        highlight.opacity = checked ? 1 : 0

        let status: String? = item.isMissing ? (item.isOwnerRunning ? "当前不在菜单栏上" : "未运行") : nil
        toolTip = [item.displayName, item.detail, status].compactMap { $0 }.joined(separator: " · ")
            + (zone == .all ? (checked ? "\n已收进 Veil，点按移除" : "\n点按或拖到下面收进 Veil") : "\n拖动调整顺序，拖回上面移除")
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(item.displayName)
        setAccessibilityValue(status ?? (checked ? "已收进 Veil" : nil))
        setAccessibilityHelp(zone == .all ? (checked ? "从 Veil 移除" : "收进 Veil") : "从 Veil 移除")
        if zone == .veil {
            let move: (String, Int) -> NSAccessibilityCustomAction = { [weak self] name, delta in
                NSAccessibilityCustomAction(name: name) { self?.controller?.move(item, by: delta) ?? false }
            }
            setAccessibilityCustomActions([move("前移", -1), move("后移", 1)])
        }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    required init?(coder: NSCoder) { fatalError() }

    override var fittingSize: NSSize { frame.size }

    override func layout() {
        super.layout()
        highlight.frame = bounds
    }

    private var isChecked: Bool { zone == .all && VeilCollection.contains(item) }

    override func mouseEntered(with event: NSEvent) {
        guard !isChecked else { return }
        highlight.backgroundColor = NSColor.labelColor.withAlphaComponent(0.12).cgColor
        highlight.opacity = 1
    }

    override func mouseExited(with event: NSEvent) {
        guard !isChecked else { return }
        highlight.opacity = 0
    }

    override func mouseDown(with event: NSEvent) {
        downEvent = event
        didDrag = false
    }

    /// 旁白没法拖动，激活就是切换：上面 = 收进 / 移除，下面 = 移除（顺序用自定义操作调整）
    override func accessibilityPerformPress() -> Bool {
        controller?.toggle(item)
        return true
    }

    override func mouseUp(with event: NSEvent) {
        defer { downEvent = nil }
        guard !didDrag, zone == .all, bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        controller?.toggle(item)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let down = downEvent, !didDrag else { return }
        let a = down.locationInWindow, b = event.locationInWindow
        guard hypot(a.x - b.x, a.y - b.y) > 3 else { return }
        didDrag = true

        let pb = NSPasteboardItem()
        pb.setString(item.key, forType: .veilItem)
        let dragItem = NSDraggingItem(pasteboardWriter: pb)
        dragItem.setDraggingFrame(bounds, contents: snapshot())
        beginDraggingSession(with: [dragItem], event: down, source: self)
    }

    private func snapshot() -> NSImage {
        guard let rep = bitmapImageRepForCachingDisplay(in: bounds) else { return NSImage() }
        cacheDisplay(in: bounds, to: rep)
        let image = NSImage(size: bounds.size)
        image.addRepresentation(rep)
        return image
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .withinApplication ? .move : []
    }

    func draggingSession(_ session: NSDraggingSession, willBeginAt screenPoint: NSPoint) {
        alphaValue = 0.35
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        alphaValue = 1
        // 从 Veil 里拖出去、扔在窗口外面 = 移除
        if zone == .veil, operation == [], let window, !window.frame.contains(screenPoint) {
            VeilCollection.remove(item)
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        let inVeil = VeilCollection.contains(item)
        let mi = NSMenuItem(title: inVeil ? "从 Veil 移除" : "收进 Veil", action: nil, keyEquivalent: "")
        mi.image = NSImage(systemSymbolName: inVeil ? "minus.circle" : "plus.circle", accessibilityDescription: nil)
        let item = self.item
        mi.onAction { [weak self] _ in self?.controller?.toggle(item) }
        menu.addItem(mi)
        return menu
    }
}

/// Veil 自己在菜单栏里的位置，只做展示
private final class VeilChip: NSView {
    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 28, height: 28))
        let icon = NSImageView(image: Preferences.shared.iconStyle.image(expanded: false) ?? NSImage())
        icon.contentTintColor = .secondaryLabelColor
        icon.frame = NSRect(x: 5, y: 5, width: 18, height: 18)
        icon.imageScaling = .scaleProportionallyDown
        addSubview(icon)
        toolTip = "Veil"
    }

    required init?(coder: NSCoder) { fatalError() }

    override var fittingSize: NSSize { frame.size }
}
