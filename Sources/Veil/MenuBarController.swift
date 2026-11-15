import AppKit

/// 菜单栏里只放一个 Veil 图标，其他图标原样不动。
/// 点 Veil：从右上角落下托盘，里面是收进 Veil 的那组图标——即使它们被刘海挡住，也能从这里打开。
@MainActor
final class MenuBarController {
    /// 托盘是怎么被打开的：决定出现在哪块屏幕、要不要直接给键盘焦点
    enum Trigger { case click, hotKey, scroll }

    var onOpenSettings: (() -> Void)?

    private let prefs = Preferences.shared
    private let toggleItem: NSStatusItem
    private var scrollMonitors: [Any] = []
    private var lastScrollToggle = Date.distantPast
    private var pendingShow: Task<Void, Never>?
    private var lastTrigger = Trigger.click
    private lazy var panel: VeilBarPanel = {
        let panel = VeilBarPanel()
        panel.onSelect = { [weak self] item, rect in self?.open(item, from: rect) }
        panel.onPressOriginal = { [weak panel] item in
            panel?.dismiss(animated: false)
            if let element = item.element { MenuBarItemScanner.press(element) }
        }
        panel.onRemove = { [weak self] item in
            VeilCollection.remove(item)
            // 托盘还开着，沿用上次打开的方式和屏幕
            if let self { self.showPanel(trigger: self.lastTrigger) }
        }
        panel.onOpenSettings = { [weak self] in self?.onOpenSettings?() }
        panel.onDismiss = { [weak self] in self?.updateIcon() }
        return panel
    }()

    init() {
        // 数值越小越靠右：Veil 紧挨系统图标，刘海屏上图标再多也不会被系统藏掉
        Self.seedPosition("Veil.Main", 1)
        toggleItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        toggleItem.autosaveName = "Veil.Main"
        if let button = toggleItem.button {
            button.target = self
            button.action = #selector(toggleClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "点按：打开 Veil\n右键：菜单"
        }
        updateIcon()
        syncScrollMonitors()

        // 启动后把屏幕上能看到的图标外观截下来，托盘和设置里就能显示真实图标
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            guard MenuBarItemScanner.isTrusted else { return }
            Task { await GlyphCache.shared.capture(await MenuBarItemScanner.scan()) }
        }

        NotificationCenter.default.addObserver(forName: Preferences.didChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateIcon()
                self?.syncScrollMonitors()
            }
        }
    }

    // MARK: - 托盘

    func toggle(trigger: Trigger = .click) {
        if let pendingShow {
            pendingShow.cancel()
            self.pendingShow = nil
            updateIcon()
        } else if panel.isPresented {
            panel.dismiss()
        } else {
            showPanel(trigger: trigger)
        }
    }

    func showPanel(trigger: Trigger = .click) {
        guard MenuBarItemScanner.isTrusted else { onOpenSettings?(); return }
        guard let window = toggleItem.button?.window, let toggleScreen = window.screen else { return }
        lastTrigger = trigger
        let toggleFrame = window.frame
        var anchor = toggleFrame, screen = toggleScreen
        // 快捷键 / 滚动时人看着的是鼠标所在的屏幕。Veil 图标在每条菜单栏上离右边缘的距离相同，
        // 照原屏幕的位置换算过去；那块屏幕没有菜单栏时还是落在 Veil 图标下面
        if trigger != .click, let mouseScreen = Self.screenUnderMouse, mouseScreen != toggleScreen, Self.hasMenuBar(mouseScreen) {
            anchor.origin.x = mouseScreen.frame.maxX - (toggleScreen.frame.maxX - toggleFrame.minX)
            anchor.origin.y = mouseScreen.frame.maxY - (toggleScreen.frame.maxY - toggleFrame.minY)
            screen = mouseScreen
        }
        updateIcon(open: true)
        pendingShow?.cancel()
        pendingShow = Task {
            let found = await MenuBarItemScanner.scan(owners: VeilCollection.owners)
            guard !Task.isCancelled else { return }
            pendingShow = nil
            panel.show(items: VeilCollection.items(from: found), below: anchor, on: screen,
                       toggleFrame: toggleFrame, focusFirst: trigger == .hotKey)
            GlyphCache.shared.refreshIfStale()
        }
    }

    private static var screenUnderMouse: NSScreen? {
        let p = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(p, $0.frame, false) }
    }

    /// 「显示器使用不同的空间」关闭时只有主屏有菜单栏；菜单栏自动隐藏时 visibleFrame 不扣它，也当作没有
    private static func hasMenuBar(_ screen: NSScreen) -> Bool {
        guard NSScreen.screensHaveSeparateSpaces || screen == NSScreen.screens.first else { return false }
        return screen.frame.maxY - screen.visibleFrame.maxY > 1
    }

    /// 从托盘打开某个图标：菜单 / 面板出现在托盘图标下方
    private func open(_ item: MenuBarItem, from iconRect: NSRect) {
        Task { await ItemOpener.open(item, from: iconRect, panel: panel) }
    }

    private func updateIcon(open: Bool? = nil) {
        toggleItem.button?.image = prefs.iconStyle.image(expanded: open ?? panel.isPresented)
    }

    // MARK: - 点击

    @objc private func toggleClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return toggle() }
        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            showMenu()
        } else {
            toggle()
        }
    }

    private func showMenu() {
        panel.dismiss(animated: false)
        let menu = NSMenu()
        let settings = NSMenuItem(title: "整理 Veil 里的图标…", action: #selector(menuSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出 Veil", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        toggleItem.menu = menu
        toggleItem.button?.performClick(nil)
        toggleItem.menu = nil
    }

    @objc private func menuSettings() { onOpenSettings?() }

    // MARK: - 滚动

    /// 全局滚动监听会被系统里每一次滚动唤醒，关掉这个功能时就不装
    private func syncScrollMonitors() {
        guard prefs.scrollToToggle == scrollMonitors.isEmpty else { return }
        guard prefs.scrollToToggle else {
            scrollMonitors.forEach(NSEvent.removeMonitor)
            scrollMonitors = []
            return
        }
        let scroll: (NSEvent) -> Void = { [weak self] event in
            MainActor.assumeIsolated { self?.handleScroll(event) }
        }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel, handler: scroll) { scrollMonitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel, handler: { scroll($0); return $0 }) { scrollMonitors.append(m) }
    }

    private func handleScroll(_ event: NSEvent) {
        // 惯性滚动不算操作，否则一次拨动会连续触发。便宜的判断放前面，绝大多数滚动到这里就结束
        guard event.momentumPhase.isEmpty else { return }
        let dy = event.scrollingDeltaY * (event.isDirectionInvertedFromDevice ? -1 : 1)
        guard abs(dy) > 2, Date().timeIntervalSince(lastScrollToggle) > 0.35, isMouseInMenuBar() else { return }
        lastScrollToggle = Date()
        // 在菜单栏上向下拨 = 拉下托盘，向上拨 = 收起
        if dy < 0 {
            if !panel.isPresented { showPanel(trigger: .scroll) }
        } else if panel.isPresented {
            panel.dismiss()
        }
    }

    private func isMouseInMenuBar() -> Bool {
        let p = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(p, $0.frame, false) }) else { return false }
        let barHeight = max(screen.frame.maxY - screen.visibleFrame.maxY, NSStatusBar.system.thickness)
        return p.y >= screen.frame.maxY - barHeight - 1
    }

    /// Veil 图标在 CG 全局坐标（左上角为原点）里的位置，设置页用来在菜单栏预览里标出它
    var toggleFrame: CGRect? {
        guard let r = toggleItem.button?.window?.frame else { return nil }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }

    private static func seedPosition(_ name: String, _ value: Double) {
        let key = "NSStatusItem Preferred Position \(name)"
        if UserDefaults.standard.object(forKey: key) == nil { UserDefaults.standard.set(value, forKey: key) }
    }
}
