import AppKit

/// 设置窗口的页面，顺序与标签一致
enum SettingsTab: Int { case layout, general, about }

@MainActor
final class SettingsWindowController: NSWindowController {
    init(menuBar: MenuBarController) {
        let tabs = SettingsTabViewController()
        tabs.tabStyle = .toolbar
        tabs.transitionOptions = []

        func add(_ vc: NSViewController, _ title: String, _ symbol: String) {
            let item = NSTabViewItem(viewController: vc)
            item.label = title
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
            tabs.addTabViewItem(item)
        }
        add(LayoutPaneController(menuBar: menuBar), "布局", "menubar.rectangle")
        add(GeneralPaneController(), "通用", "gearshape")
        add(AboutPaneController(), "关于", "info.circle")

        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("VeilSettings")
        window.center()
        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.makeFirstResponder(nil)
    }

    func select(_ tab: SettingsTab) {
        (window?.contentViewController as? NSTabViewController)?.selectedTabViewItemIndex = tab.rawValue
    }
}

extension NSViewController {
    /// 标签页控制器只在切换页面时贴合窗口，页面内容变高变矮后要自己调整（保持窗口顶边不动）
    func fitSettingsWindow(to size: NSSize) {
        guard let window = view.window,
              let tabs = window.contentViewController as? NSTabViewController,
              tabs.tabViewItems[tabs.selectedTabViewItemIndex].viewController === self else { return }
        let current = window.frame
        let target = window.frameRect(forContentRect: NSRect(origin: .zero, size: size))
        guard abs(target.height - current.height) > 0.5 else { return }
        window.setFrame(NSRect(x: current.minX, y: current.maxY - target.height, width: target.width, height: target.height),
                        display: true, animate: true)
    }
}

/// 切换面板时：窗口标题跟随面板名，窗口高度贴合面板内容（系统设置同款动画）
final class SettingsTabViewController: NSTabViewController {
    // 标签页控制器自带的窗口缩放不可靠（切到更高的页面时不长高），这里不给它 preferredContentSize，
    // 窗口高度全部由 fit(_:) 按页面内容设置
    override func tabView(_ tabView: NSTabView, willSelect item: NSTabViewItem?) {
        super.tabView(tabView, willSelect: item)
        view.window?.title = item?.label ?? "Veil"
    }

    override func tabView(_ tabView: NSTabView, didSelect item: NSTabViewItem?) {
        super.tabView(tabView, didSelect: item)
        let title = item?.label ?? "Veil"
        DispatchQueue.main.async { [weak self] in
            self?.view.window?.title = title
            // 「布局」页内容会变，由它自己在刷新后贴合
            if let vc = item?.viewController, !(vc is LayoutPaneController) { self?.fit(vc) }
        }
    }

    override func preferredContentSizeDidChange(for viewController: NSViewController) {}

    private func fit(_ vc: NSViewController) {
        guard tabViewItems[selectedTabViewItemIndex].viewController === vc else { return }
        vc.fitSettingsWindow(to: Self.naturalSize(of: vc.view))
    }

    /// 页面视图被钉在窗口当前尺寸上，fittingSize 不可靠，堆栈视图按可见子视图自己算
    private static func naturalSize(of view: NSView) -> NSSize {
        guard let stack = view as? NSStackView, stack.orientation == .vertical else { return view.fittingSize }
        let visible = stack.arrangedSubviews.filter { !$0.isHidden }
        var height = stack.edgeInsets.top + stack.edgeInsets.bottom + visible.reduce(0) { $0 + $1.fittingSize.height }
        for a in visible.dropLast() {
            let custom = stack.customSpacing(after: a)
            height += custom == NSStackView.useDefaultSpacing ? stack.spacing : custom
        }
        return NSSize(width: view.frame.width, height: ceil(height))
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.title = tabViewItems[selectedTabViewItemIndex].label
    }
}

// MARK: - 小组件

/// 让 NSControl 可以直接挂闭包
final class ActionHandler: NSObject {
    private let handler: (Any) -> Void
    init(_ handler: @escaping (Any) -> Void) { self.handler = handler }
    @objc func fire(_ sender: Any) { handler(sender) }
}

extension NSControl {
    private static var handlerKey: UInt8 = 0
    func onAction(_ handler: @escaping (Any) -> Void) {
        let h = ActionHandler(handler)
        objc_setAssociatedObject(self, &Self.handlerKey, h, .OBJC_ASSOCIATION_RETAIN)
        target = h
        action = #selector(ActionHandler.fire(_:))
    }
}

enum UI {
    static func checkbox(_ title: String, _ value: Bool, _ change: @escaping (Bool) -> Void) -> NSButton {
        let b = NSButton(checkboxWithTitle: title, target: nil, action: nil)
        b.state = value ? .on : .off
        b.onAction { change(($0 as! NSButton).state == .on) }
        return b
    }

    static func label(_ text: String) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.alignment = .right
        return l
    }

    static func note(_ text: String) -> NSTextField {
        let l = NSTextField(wrappingLabelWithString: text)
        l.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        l.textColor = .secondaryLabelColor
        l.preferredMaxLayoutWidth = 340
        return l
    }
}

/// 看起来是一段文字链接，而不是按钮
final class LinkButton: NSButton {
    init(_ title: String, url: URL) {
        super.init(frame: .zero)
        isBordered = false
        setButtonType(.momentaryChange)
        attributedTitle = NSAttributedString(string: title, attributes: [
            .foregroundColor: NSColor.linkColor,
            .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
        ])
        toolTip = url.absoluteString
        onAction { _ in NSWorkspace.shared.open(url) }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
}

/// 点一下开始录制，按下组合键即保存；Esc 取消，⌫ 清除
final class ShortcutRecorder: NSButton {
    var onChange: ((HotKey?) -> Void)?
    private var monitor: Any?
    private var hotKey: HotKey?

    init(_ hotKey: HotKey?) {
        self.hotKey = hotKey
        super.init(frame: .zero)
        bezelStyle = .push
        setButtonType(.momentaryPushIn)
        target = self
        action = #selector(startRecording)
        widthAnchor.constraint(greaterThanOrEqualToConstant: 150).isActive = true
        refresh()
    }

    required init?(coder: NSCoder) { fatalError() }

    /// 被占用的组合键不能显示得像已生效：加警告图标、文字标红
    func refresh() {
        let failed = monitor == nil && hotKey != nil && HotKeyCenter.shared.registrationFailed
        let text = monitor != nil ? "请按下快捷键…" : (hotKey?.display ?? "点击录制")
        if failed {
            attributedTitle = NSAttributedString(string: text, attributes: [.foregroundColor: NSColor.systemRed])
            image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "未生效")
            imagePosition = .imageLeading
            contentTintColor = .systemRed
        } else {
            title = text
            image = nil
            contentTintColor = nil
        }
        setAccessibilityValue(failed ? "未生效" : nil)
    }

    @objc private func startRecording() {
        guard monitor == nil else { return stopRecording() }
        HotKeyCenter.shared.setSuspended(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
            switch event.keyCode {
            case 53: // Esc
                self.stopRecording()
            case 51, 117: // ⌫ / ⌦
                self.hotKey = nil
                self.onChange?(nil)
                self.stopRecording()
            default:
                guard !flags.isEmpty, flags != .shift else { NSSound.beep(); return nil }
                let key = HotKey(keyCode: UInt32(event.keyCode),
                                 modifiers: HotKeyCenter.carbonModifiers(flags),
                                 display: HotKeyCenter.display(flags, keyCode: event.keyCode,
                                                               characters: event.charactersIgnoringModifiers))
                self.hotKey = key
                self.onChange?(key)
                self.stopRecording()
            }
            return nil
        }
        refresh()
    }

    /// 面板收起时结束录制，否则全局快捷键会一直处于暂停状态
    func cancelRecording() {
        if monitor != nil { stopRecording() }
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        HotKeyCenter.shared.setSuspended(false)
        refresh()
    }
}

// MARK: - 通用

@MainActor
final class GeneralPaneController: NSViewController {
    private let prefs = Preferences.shared
    private var recorder: ShortcutRecorder?
    private let grid = NSGridView()
    private let loginBox = NSButton(checkboxWithTitle: "登录时打开 Veil", target: nil, action: nil)
    private let loginNote = UI.note("")
    private let hotKeyWarning = UI.note("")

    override func viewWillAppear() {
        super.viewWillAppear()
        // 用户可能在系统设置里改过登录项，每次打开都按真实状态显示
        refreshLogin(error: nil)
        refreshHotKeyStatus()
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        recorder?.cancelRecording()
    }

    override func loadView() {
        let stylePopup = NSPopUpButton()
        for style in IconStyle.allCases {
            stylePopup.addItem(withTitle: style.title)
            stylePopup.lastItem?.image = style.image(expanded: false)
        }
        stylePopup.selectItem(at: IconStyle.allCases.firstIndex(of: prefs.iconStyle) ?? 0)
        stylePopup.onAction { [prefs] in prefs.iconStyle = IconStyle.allCases[($0 as! NSPopUpButton).indexOfSelectedItem] }

        let recorder = ShortcutRecorder(prefs.hotKey)
        recorder.onChange = { [prefs] in prefs.hotKey = $0 }
        self.recorder = recorder
        NotificationCenter.default.addObserver(forName: HotKeyCenter.statusDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshHotKeyStatus() }
        }

        loginBox.onAction { [weak self] in self?.setLaunchAtLogin(($0 as! NSButton).state == .on) }
        hotKeyWarning.textColor = .systemRed

        let rows: [[NSView]] = [
            [UI.label("启动："), loginBox],
            [NSGridCell.emptyContentView, loginNote],
            [section(), NSGridCell.emptyContentView],
            [UI.label("打开 Veil："), UI.note("点按菜单栏里的 Veil 图标，或：")],
            [NSGridCell.emptyContentView, UI.checkbox("在菜单栏上向下滚动", prefs.scrollToToggle) { [prefs] in prefs.scrollToToggle = $0 }],
            [UI.label("快捷键："), recorder],
            [NSGridCell.emptyContentView, hotKeyWarning],
            [NSGridCell.emptyContentView, UI.note("托盘里点按图标就会打开它的菜单。点其他地方或按 Esc 收起托盘。")],
            [section(), NSGridCell.emptyContentView],
            [UI.label("Veil 图标："), stylePopup],
        ]

        for row in rows { grid.addRow(with: row) }
        grid.rowSpacing = 8
        grid.columnSpacing = 10
        grid.rowAlignment = .firstBaseline
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 0).width = 96
        for i in 0..<grid.numberOfRows where rows[i].first is SectionSpacer {
            grid.row(at: i).height = 6
            grid.row(at: i).mergeCells(in: NSRange(location: 0, length: 2))
        }
        grid.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: container.topAnchor, constant: 24),
            grid.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -24),
            grid.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 30),
            grid.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -30),
            container.widthAnchor.constraint(equalToConstant: 520),
        ])
        view = container
        refreshLogin(error: nil)
        refreshHotKeyStatus()
    }

    private func section() -> NSView { SectionSpacer() }

    // MARK: 登录项

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try prefs.setLaunchAtLogin(enabled)
            refreshLogin(error: nil)
        } catch {
            NSLog("Veil: 登录项设置失败 \(error)")
            refreshLogin(error: error)
        }
    }

    /// 勾选框始终反映 SMAppService 的真实状态，失败时说明原因
    private func refreshLogin(error: Error?) {
        loginBox.state = prefs.launchAtLogin ? .on : .off
        var message: String?
        if let error {
            message = prefs.isInApplicationsFolder
                ? String(format: "无法设置登录时打开：%@", error.localizedDescription)
                : String(format: "无法设置登录时打开：%@\nVeil 不在「应用程序」文件夹里时，系统通常不允许把它设为登录项。请先把 Veil 移到「应用程序」文件夹再试。", error.localizedDescription)
        } else if prefs.launchAtLoginNeedsApproval {
            message = "还需要在「系统设置 › 通用 › 登录项」里允许 Veil。"
        }
        loginNote.stringValue = message ?? ""
        loginNote.textColor = error != nil ? .systemRed : .secondaryLabelColor
        setRow(of: loginNote, hidden: message == nil)
    }

    // MARK: 快捷键

    private func refreshHotKeyStatus() {
        recorder?.refresh()
        let failed = HotKeyCenter.shared.registrationFailed
        if failed, let key = prefs.hotKey {
            hotKeyWarning.stringValue = String(format: "「%@」已被其他应用占用，没有生效。请换一个组合键。", key.display)
        }
        setRow(of: hotKeyWarning, hidden: !failed)
    }

    private func setRow(of view: NSView, hidden: Bool) {
        guard let row = grid.cell(for: view)?.row, row.isHidden != hidden else { return }
        row.isHidden = hidden
        guard isViewLoaded else { return }
        grid.layoutSubtreeIfNeeded()
        fitSettingsWindow(to: NSSize(width: 520, height: ceil(grid.fittingSize.height) + 48))
    }
}

private final class SectionSpacer: NSBox {
    init() {
        super.init(frame: .zero)
        boxType = .separator
    }
    required init?(coder: NSCoder) { fatalError() }
}

// MARK: - 关于

/// 对外链接集中在这里
enum ProjectLinks {
    static let homepage = URL(string: "https://github.com/biyan113/Veil")!
    static let issues = homepage.appendingPathComponent("issues")
    static let author = URL(string: "https://mp.bytenote.net/")!
}

final class AboutPaneController: NSViewController {
    override func loadView() {
        let icon = NSImageView(image: NSApp.applicationIconImage)
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.widthAnchor.constraint(equalToConstant: 96).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 96).isActive = true

        let name = NSTextField(labelWithString: "Veil")
        name.font = .systemFont(ofSize: 26, weight: .semibold)

        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let ver = NSTextField(labelWithString: "版本 \(version)")
        ver.textColor = .secondaryLabelColor

        let blurb = NSTextField(wrappingLabelWithString: "把常用的菜单栏图标收进 Veil，\n被刘海挡住也能随时一点即开。")
        blurb.alignment = .center
        blurb.textColor = .secondaryLabelColor
        blurb.preferredMaxLayoutWidth = 360

        let author = LinkButton("@字节笔记本", url: ProjectLinks.author)

        func linkButton(_ title: String, _ symbol: String, _ url: URL) -> NSButton {
            let b = NSButton(title: title, target: nil, action: nil)
            b.bezelStyle = .push
            b.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            b.imagePosition = .imageLeading
            b.toolTip = url.absoluteString
            b.onAction { _ in NSWorkspace.shared.open(url) }
            return b
        }
        let links = NSStackView(views: [
            linkButton("项目主页", "house", ProjectLinks.homepage),
            linkButton("反馈问题", "exclamationmark.bubble", ProjectLinks.issues),
        ])
        links.spacing = 10

        let license = NSTextField(labelWithString: "以 GPL-3.0 许可证发布")
        license.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        license.textColor = .tertiaryLabelColor

        let stack = NSStackView(views: [icon, name, ver, blurb, author, links, license])
        stack.orientation = .vertical
        stack.spacing = 8
        stack.setCustomSpacing(14, after: icon)
        stack.setCustomSpacing(16, after: ver)
        stack.setCustomSpacing(6, after: blurb)
        stack.setCustomSpacing(16, after: author)
        stack.setCustomSpacing(14, after: links)
        stack.edgeInsets = NSEdgeInsets(top: 30, left: 40, bottom: 28, right: 40)
        stack.widthAnchor.constraint(equalToConstant: 520).isActive = true
        view = stack
    }
}
