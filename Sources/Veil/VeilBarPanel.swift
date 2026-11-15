import AppKit

/// 右上角落下的玻璃托盘：收藏的图标以真实外观排开，太多时自动折行。
/// 点按 = 打开它的菜单；⌥ 点按 = 直接点按菜单栏里的原图标；拖出托盘 = 从 Veil 移除；右键 = 更多操作。
/// 键盘：方向键移动焦点，回车 / 空格打开，直接输入名称跳到匹配项，Esc 收起。
@MainActor
final class VeilBarPanel: NSPanel {
    var onSelect: ((MenuBarItem, NSRect) -> Void)?
    /// 不做镜像，直接对原图标执行点按：镜像菜单显示不全时的退路
    var onPressOriginal: ((MenuBarItem) -> Void)?
    var onRemove: ((MenuBarItem) -> Void)?
    var onOpenSettings: (() -> Void)?
    var onDismiss: (() -> Void)?

    fileprivate let flow = FlowView()
    private let caption = NSTextField(labelWithString: "点按打开 · 拖出托盘即可移除")
    private let hintRow = NSStackView()
    private var monitors: [Any] = []
    fileprivate var isDraggingItem = false
    /// Veil 图标真实所在的位置：点它交给它自己的开关，本地点击监听要排除
    private var toggleFrame = NSRect.zero
    private var trayItems: [TrayItemView] = []
    /// 键盘焦点；用鼠标打开时为 nil，按下方向键后才出现
    private var focusIndex: Int?
    private var typeahead = ""
    private var lastTypeahead = Date.distantPast
    /// 淡出动画期间窗口还在屏幕上，「是否打开」要以这个状态为准
    private(set) var isPresented = false

    static let maxContentWidth: CGFloat = 380

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovable = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        animationBehavior = .none

        caption.font = .systemFont(ofSize: 10.5)
        caption.textColor = .tertiaryLabelColor
        caption.setContentHuggingPriority(.required, for: .horizontal)

        let close = NSButton()
        close.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "不再显示")?
            .withSymbolConfiguration(.init(pointSize: 8, weight: .bold))
        close.image?.isTemplate = true
        close.contentTintColor = .tertiaryLabelColor
        close.isBordered = false
        close.bezelStyle = .inline
        close.setButtonType(.momentaryChange)
        close.toolTip = "不再显示"
        close.setAccessibilityLabel("不再显示")
        close.setContentHuggingPriority(.required, for: .horizontal)
        close.setContentCompressionResistancePriority(.required, for: .horizontal)
        close.onAction { [weak self] _ in self?.dismissHint() }

        hintRow.orientation = .horizontal
        hintRow.alignment = .centerY
        hintRow.spacing = 3
        hintRow.addArrangedSubview(caption)
        hintRow.addArrangedSubview(close)

        let stack = NSStackView(views: [flow, hintRow])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 7, right: 8)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let background: NSView
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = 16
            glass.contentView = stack
            background = glass
        } else {
            let effect = NSVisualEffectView()
            effect.material = .popover
            effect.state = .active
            effect.wantsLayer = true
            effect.layer?.cornerRadius = 14
            effect.layer?.masksToBounds = true
            effect.addSubview(stack)
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
                stack.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
                stack.topAnchor.constraint(equalTo: effect.topAnchor),
                stack.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
            ])
            background = effect
        }
        contentView = background
    }

    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { dismiss() }

    /// anchor：托盘右边缘要对齐的位置（Cocoa 坐标），通常就是 Veil 开关；
    /// toggleFrame：Veil 开关真实的位置。focusFirst：用键盘打开时直接聚焦第一个图标
    func show(items: [MenuBarItem], below anchor: NSRect, on screen: NSScreen, toggleFrame: NSRect, focusFirst: Bool = false) {
        self.toggleFrame = toggleFrame
        let wasPresented = isPresented
        let previousFocus = focusIndex
        hintRow.isHidden = items.isEmpty || !Preferences.shared.showTrayHint
        trayItems = items.map { TrayItemView(item: $0, panel: self) }
        var trayViews: [NSView] = trayItems
        if items.isEmpty {
            // 收藏不为空却一个都没取到：多半是应用没在运行，和「还没收」要说清楚
            let message = VeilCollection.keys.isEmpty ? "还没有收进 Veil 的图标"
                : VeilCollection.hasRunningOwner ? "收进 Veil 的图标暂时都不在菜单栏上"
                : "收进 Veil 的图标所属应用都没有运行"
            let label = NSTextField(labelWithString: message)
            label.textColor = .secondaryLabelColor
            label.font = .systemFont(ofSize: 12)
            let button = NSButton(title: VeilCollection.keys.isEmpty ? "去挑选…" : "去整理…", target: nil, action: nil)
            button.bezelStyle = .push
            button.controlSize = .small
            button.onAction { [weak self] _ in
                self?.dismiss(animated: false)
                self?.onOpenSettings?()
            }
            let empty = NSStackView(views: [label, button])
            empty.spacing = 8
            empty.edgeInsets = NSEdgeInsets(top: 4, left: 6, bottom: 4, right: 4)
            empty.frame.size = empty.fittingSize
            trayViews = [empty]
        }
        flow.setItems(trayViews, maxWidth: Self.maxContentWidth)
        // 托盘开着时刷新（例如移除了一个图标）沿用原来的焦点
        let focus = wasPresented ? previousFocus : (focusFirst ? 0 : nil)
        setFocus(focus.map { min($0, trayItems.count - 1) }.flatMap { $0 >= 0 ? $0 : nil })

        contentView?.layoutSubtreeIfNeeded()
        let stack = flow.superview as! NSStackView
        let hintWidth = hintRow.isHidden ? 0 : hintRow.fittingSize.width
        let width = max(flow.intrinsicContentSize.width, hintWidth) + 16
        let content = NSSize(width: width, height: stack.fittingSize.height)

        let barHeight = max(screen.frame.maxY - screen.visibleFrame.maxY, NSStatusBar.system.thickness)
        let visible = screen.frame.insetBy(dx: 8, dy: 0)
        // 右边缘对齐 Veil 图标，贴着右上角落下
        let x = min(max(anchor.maxX - content.width + 6, visible.minX), visible.maxX - content.width)
        let final = NSRect(x: x, y: screen.frame.maxY - barHeight - 6 - content.height, width: content.width, height: content.height)

        isPresented = true
        setFrame(wasPresented ? final : final.offsetBy(dx: 0, dy: 8), display: false)
        if !wasPresented { alphaValue = 0 }
        makeKeyAndOrderFront(nil)
        // 键盘事件交给托盘自己处理，不让空状态里的按钮抢走
        makeFirstResponder(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1)
            animator().setFrame(final, display: true)
            animator().alphaValue = 1
        }
        installMonitors()
    }

    /// 点掉底部说明后不再出现，托盘高度跟着收掉这一行
    private func dismissHint() {
        Preferences.shared.showTrayHint = false
        hintRow.isHidden = true
        guard isPresented else { return }
        contentView?.layoutSubtreeIfNeeded()
        guard let stack = flow.superview as? NSStackView else { return }
        let width = flow.intrinsicContentSize.width + 16
        let height = stack.fittingSize.height
        let next = NSRect(x: frame.maxX - width, y: frame.maxY - height, width: width, height: height)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.16
            animator().setFrame(next, display: true)
        }
    }

    func dismiss(animated: Bool = true) {
        guard isPresented else { return }
        isPresented = false
        removeMonitors()
        onDismiss?()
        guard animated else {
            alphaValue = 0
            orderOut(nil)
            return
        }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.14
            animator().alphaValue = 0
            animator().setFrame(frame.offsetBy(dx: 0, dy: 4), display: true)
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                // 淡出途中又被打开时不能收走
                guard let self, !self.isPresented else { return }
                self.orderOut(nil)
            }
        })
    }

    // MARK: - 键盘

    override func keyDown(with event: NSEvent) {
        if !handleKey(event) { super.keyDown(with: event) }
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        if event.keyCode == 53 { dismiss(); return true }   // Esc
        let mods = event.modifierFlags.intersection([.command, .control, .option])
        // ⌘ / ⌃ 组合交给系统；⌥ 只在回车 / 空格上有意义（直通原图标）
        guard !mods.contains(.command), !mods.contains(.control), !trayItems.isEmpty else { return false }
        switch event.keyCode {
        case 123: moveFocus(by: -1)                           // ←
        case 124: moveFocus(by: 1)                            // →
        case 126: moveFocusRow(by: -1)                        // ↑
        case 125: moveFocusRow(by: 1)                         // ↓
        case 48: moveFocus(by: event.modifierFlags.contains(.shift) ? -1 : 1) // ⇥
        case 36, 76: activateFocused(passThrough: mods.contains(.option))      // ↩ / 小键盘 ⌤
        case 49 where !isTyping: activateFocused(passThrough: mods.contains(.option)) // 空格
        default:
            guard mods.isEmpty, let chars = event.charactersIgnoringModifiers, !chars.isEmpty,
                  chars.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else { return false }
            typeSelect(chars)
        }
        return true
    }

    /// 连续输入的间隔不超过 1 秒算同一个词
    private var isTyping: Bool { !typeahead.isEmpty && Date().timeIntervalSince(lastTypeahead) < 1 }

    private func typeSelect(_ chars: String) {
        if !isTyping { typeahead = "" }
        typeahead += chars
        lastTypeahead = Date()
        let names = trayItems.map { [$0.item.displayName, $0.item.appName] }
        let prefix = names.firstIndex { $0.contains { $0.range(of: typeahead, options: [.caseInsensitive, .diacriticInsensitive, .anchored]) != nil } }
        let contains = names.firstIndex { $0.contains { $0.range(of: typeahead, options: [.caseInsensitive, .diacriticInsensitive]) != nil } }
        if let index = prefix ?? contains { setFocus(index) } else { NSSound.beep() }
    }

    private func moveFocus(by delta: Int) {
        guard let current = focusIndex else { return setFocus(0) }
        setFocus(min(max(current + delta, 0), trayItems.count - 1))
    }

    /// 折行时上下键按行移动：去相邻一行里水平位置最接近的那个
    private func moveFocusRow(by delta: Int) {
        guard let current = focusIndex else { return setFocus(0) }
        let rows = Array(Set(trayItems.map(\.frame.minY))).sorted()
        guard let row = rows.firstIndex(of: trayItems[current].frame.minY),
              rows.indices.contains(row + delta) else { return }
        let targetY = rows[row + delta], midX = trayItems[current].frame.midX
        let candidates = trayItems.indices.filter { trayItems[$0].frame.minY == targetY }
        if let best = candidates.min(by: { abs(trayItems[$0].frame.midX - midX) < abs(trayItems[$1].frame.midX - midX) }) {
            setFocus(best)
        }
    }

    private func setFocus(_ index: Int?) {
        focusIndex = index
        for (i, view) in trayItems.enumerated() { view.isFocused = i == index }
    }

    private func activateFocused(passThrough: Bool) {
        guard let index = focusIndex else { return setFocus(0) }
        trayItems[index].activate(passThrough: passThrough)
    }

    private func installMonitors() {
        removeMonitors()
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown]
        if let m = NSEvent.addGlobalMonitorForEvents(matching: clicks, handler: { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.isDraggingItem else { return }
                self.dismiss()
            }
        }) { monitors.append(m) }
        // 全局监听收不到自己进程的点击，点设置窗口也要收起；点 Veil 图标交给它自己的开关
        if let m = NSEvent.addLocalMonitorForEvents(matching: clicks, handler: { [weak self] event in
            MainActor.assumeIsolated {
                // 用事件自己的位置：光标可能已经移开
                let point = event.window?.convertPoint(toScreen: event.locationInWindow) ?? event.locationInWindow
                if let self, event.window !== self, !self.toggleFrame.contains(point) { self.dismiss() }
            }
            return event
        }) { monitors.append(m) }
    }

    private func removeMonitors() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
    }
}

// MARK: - 自动折行布局

private final class FlowView: NSView {
    private let spacing: CGFloat = 2
    private var size = NSSize.zero
    override var isFlipped: Bool { true }
    override var intrinsicContentSize: NSSize { size }

    func setItems(_ views: [NSView], maxWidth: CGFloat) {
        subviews.forEach { $0.removeFromSuperview() }
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
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
            widest = max(widest, x - spacing)
        }
        size = NSSize(width: widest, height: y + rowHeight)
        invalidateIntrinsicContentSize()
        removeConstraints(constraints)
        widthAnchor.constraint(equalToConstant: size.width).isActive = true
        heightAnchor.constraint(equalToConstant: size.height).isActive = true
    }
}

// MARK: - 托盘里的单个图标

private final class TrayItemView: NSView {
    let item: MenuBarItem
    private weak var panel: VeilBarPanel?
    private let highlight = CALayer()
    private let focusRing = CALayer()
    private let iconSize: NSSize
    private let image: NSImage
    private let isGlyph: Bool
    private var downPoint: NSPoint?
    private var ghost: NSWindow?

    private static let height: CGFloat = 30

    init(item: MenuBarItem, panel: VeilBarPanel) {
        self.item = item
        self.panel = panel
        // 优先用截取到的真实外观（和菜单栏里一模一样），没有时退回应用图标
        if let glyph = GlyphCache.shared.image(for: item) {
            image = glyph
            iconSize = NSSize(width: glyph.size.width, height: min(glyph.size.height, Self.height))
            isGlyph = true
        } else {
            image = item.appIcon
            iconSize = NSSize(width: 18, height: 18)
            isGlyph = false
        }
        super.init(frame: NSRect(x: 0, y: 0, width: max(Self.height, iconSize.width + 10), height: Self.height))
        wantsLayer = true
        highlight.cornerRadius = 8
        highlight.opacity = 0
        layer?.addSublayer(highlight)
        focusRing.cornerRadius = 8
        focusRing.borderWidth = 2
        focusRing.isHidden = true
        layer?.addSublayer(focusRing)

        let icon = NSImageView(image: image)
        icon.imageScaling = isGlyph ? .scaleNone : .scaleProportionallyUpOrDown
        icon.contentTintColor = .labelColor
        icon.frame = NSRect(x: (frame.width - iconSize.width) / 2, y: (frame.height - iconSize.height) / 2,
                            width: iconSize.width, height: iconSize.height)
        addSubview(icon)

        toolTip = item.displayName
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(item.displayName)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    required init?(coder: NSCoder) { fatalError() }

    override var fittingSize: NSSize { frame.size }

    /// 托盘不激活应用，第一下点击也要直接生效
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// 在屏幕上的位置，用来把菜单 / 面板放到它下方
    var screenRect: NSRect {
        guard let window else { return .zero }
        return window.convertToScreen(convert(bounds, to: nil))
    }

    override func layout() {
        super.layout()
        highlight.frame = bounds
        focusRing.frame = bounds
    }

    /// 键盘焦点：描边 + 浅色底，和鼠标悬停区分开
    var isFocused = false {
        didSet {
            focusRing.isHidden = !isFocused
            focusRing.borderColor = NSColor.keyboardFocusIndicatorColor.cgColor
            focusRing.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.15).cgColor
        }
    }

    /// passThrough：不做镜像，直接点按菜单栏里的原图标
    func activate(passThrough: Bool) {
        if passThrough { panel?.onPressOriginal?(item) } else { panel?.onSelect?(item, screenRect) }
    }

    override func accessibilityPerformPress() -> Bool {
        activate(passThrough: false)
        return true
    }

    override func mouseEntered(with event: NSEvent) { setHighlight(1) }
    override func mouseExited(with event: NSEvent) { setHighlight(0) }

    private func setHighlight(_ v: Float) {
        highlight.backgroundColor = NSColor.labelColor.withAlphaComponent(0.1).cgColor
        highlight.opacity = v
    }

    override func mouseDown(with event: NSEvent) {
        downPoint = NSEvent.mouseLocation
        setHighlight(0.6)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = downPoint else { return }
        let p = NSEvent.mouseLocation
        if ghost == nil, hypot(p.x - start.x, p.y - start.y) > 4 { beginGhost() }
        moveGhost(to: p)
    }

    override func mouseUp(with event: NSEvent) {
        defer { downPoint = nil }
        setHighlight(0)
        if let ghost {
            endGhost(ghost, at: NSEvent.mouseLocation)
        } else if bounds.contains(convert(event.locationInWindow, from: nil)) {
            activate(passThrough: event.modifierFlags.contains(.option))
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        let open = NSMenuItem(title: "打开", action: nil, keyEquivalent: "")
        open.onAction { [weak self] _ in self?.activate(passThrough: false) }
        let original = NSMenuItem(title: "在菜单栏中点按原图标", action: nil, keyEquivalent: "")
        original.toolTip = "菜单显示不全时使用：直接点按菜单栏里的原图标，菜单会出现在它原来的位置。也可以按住 ⌥ 点按。"
        original.onAction { [weak self] _ in self?.activate(passThrough: true) }
        let remove = NSMenuItem(title: "从 Veil 移除", action: nil, keyEquivalent: "")
        remove.image = NSImage(systemSymbolName: "minus.circle", accessibilityDescription: nil)
        remove.onAction { [weak self] _ in if let self { self.panel?.onRemove?(self.item) } }
        menu.addItem(open)
        menu.addItem(original)
        menu.addItem(.separator())
        menu.addItem(remove)
        return menu
    }

    // MARK: 拖出托盘移除

    private func beginGhost() {
        panel?.isDraggingItem = true
        let size = NSSize(width: max(iconSize.width, 18) + 12, height: 28)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 2)
        window.ignoresMouseEvents = true
        let bg = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        bg.material = .menu
        bg.state = .active
        bg.wantsLayer = true
        bg.layer?.cornerRadius = 8
        let icon = NSImageView(image: image)
        icon.imageScaling = isGlyph ? .scaleNone : .scaleProportionallyUpOrDown
        icon.contentTintColor = .labelColor
        icon.frame = NSRect(x: (size.width - iconSize.width) / 2, y: (size.height - iconSize.height) / 2,
                            width: iconSize.width, height: iconSize.height)
        bg.addSubview(icon)
        window.contentView = bg
        window.alphaValue = 0.92
        window.orderFront(nil)
        ghost = window
        alphaValue = 0.3
    }

    private func moveGhost(to p: NSPoint) {
        guard let ghost else { return }
        ghost.setFrameOrigin(NSPoint(x: p.x - ghost.frame.width / 2, y: p.y - ghost.frame.height / 2))
    }

    private func endGhost(_ ghost: NSWindow, at p: NSPoint) {
        self.ghost = nil
        panel?.isDraggingItem = false
        if let panel, !panel.frame.insetBy(dx: -12, dy: -12).contains(p) {
            ghost.orderOut(nil)
            panel.onRemove?(item)
            return
        }
        // 还在托盘范围内松手：飞回原位
        let home = window.map { convert(bounds, to: nil).offsetBy(dx: $0.frame.minX, dy: $0.frame.minY) } ?? ghost.frame
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            ghost.animator().setFrame(NSRect(x: home.midX - ghost.frame.width / 2, y: home.midY - ghost.frame.height / 2,
                                             width: ghost.frame.width, height: ghost.frame.height), display: true)
            ghost.animator().alphaValue = 0
        }, completionHandler: { ghost.orderOut(nil) })
        alphaValue = 1
    }
}
