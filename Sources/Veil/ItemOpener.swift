import AppKit

/// 从托盘打开某个图标，并让它的菜单 / 面板出现在托盘图标下方，而不是图标原来所在的（可能被刘海挡住的）位置。
///
/// 实测（macOS 27）：
/// - 状态栏菜单（NSMenu）的位置无法通过辅助功能修改，但菜单结构在关闭状态下也能完整读到，
///   所以在托盘图标下弹出一份原生菜单镜像，选中后再替用户点原菜单里的对应项。
/// - 弹出面板（NSPopover）的位置可以修改，打开后立即挪到托盘图标下方。
@MainActor
enum ItemOpener {
    /// iconRect：托盘里该图标的屏幕位置（Cocoa 坐标）
    static func open(_ item: MenuBarItem, from iconRect: NSRect, panel: VeilBarPanel) async {
        guard let element = item.element else { return }

        // 1. 菜单：直接镜像，不打开原菜单，也就不会在原位置闪一下
        if let menu = mirroredMenu(of: element) {
            pop(menu, under: iconRect, panel: panel)
            return
        }

        // 2. 其他情况：真的点一下，看弹出的是什么
        panel.dismiss(animated: false)
        MenuBarItemScanner.press(element)
        let deadline = ContinuousClock.now + .milliseconds(800)
        while ContinuousClock.now < deadline {
            if let popover = child(of: element, role: "AXPopover") {
                move(popover, under: iconRect)
                return
            }
            // 打开时才生成内容的菜单：读完立刻关掉原菜单，换成镜像
            if let open = child(of: element, role: "AXMenu"), let menu = mirror(open) {
                AXUIElementPerformAction(open, kAXCancelAction as CFString)
                pop(menu, under: iconRect, panel: nil)
                return
            }
            try? await Task.sleep(for: .milliseconds(15))
        }
    }

    // MARK: - 菜单镜像

    private static func mirroredMenu(of element: AXUIElement) -> NSMenu? {
        guard let axMenu = child(of: element, role: "AXMenu") else { return nil }
        return mirror(axMenu)
    }

    private static func mirror(_ axMenu: AXUIElement) -> NSMenu? {
        let axItems: [AXUIElement] = attribute(axMenu, kAXChildrenAttribute) ?? []
        guard !axItems.isEmpty else { return nil }
        let menu = NSMenu()
        menu.autoenablesItems = false
        for axItem in axItems {
            let title: String = attribute(axItem, kAXTitleAttribute) ?? ""
            let enabled: Bool = attribute(axItem, kAXEnabledAttribute) ?? true
            let sub: AXUIElement? = (attribute(axItem, kAXChildrenAttribute) as [AXUIElement]?)?.first

            if title.isEmpty, sub == nil, !enabled {
                menu.addItem(.separator())
                continue
            }
            let mi = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            mi.isEnabled = enabled
            if let mark: String = attribute(axItem, "AXMenuItemMarkChar"), !mark.isEmpty { mi.state = .on }
            if let key: String = attribute(axItem, "AXMenuItemCmdChar"), !key.isEmpty {
                mi.keyEquivalent = key.lowercased()
                mi.keyEquivalentModifierMask = modifiers(attribute(axItem, "AXMenuItemCmdModifiers") ?? 0)
            }
            if let sub, let submenu = mirror(sub) {
                mi.submenu = submenu
            } else {
                mi.onAction { _ in MenuBarItemScanner.press(axItem) }
            }
            menu.addItem(mi)
        }
        // 全是自定义视图的菜单读不到文字，镜像只会是一排空行，交给后面真的点开
        return menu.items.contains { !$0.title.isEmpty } ? menu : nil
    }

    /// AXMenuItemCmdModifiers：1=⇧ 2=⌥ 4=⌃ 8=无 ⌘
    private static func modifiers(_ raw: Int) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = raw & 8 == 0 ? [.command] : []
        if raw & 1 != 0 { flags.insert(.shift) }
        if raw & 2 != 0 { flags.insert(.option) }
        if raw & 4 != 0 { flags.insert(.control) }
        return flags
    }

    /// 在托盘图标正下方弹出；托盘保持显示，菜单关闭后再收起托盘
    private static func pop(_ menu: NSMenu, under iconRect: NSRect, panel: VeilBarPanel?) {
        menu.popUp(positioning: nil, at: NSPoint(x: iconRect.minX, y: iconRect.minY - 4), in: nil)
        panel?.dismiss()
    }

    // MARK: - 弹出面板

    private static func move(_ popover: AXUIElement, under iconRect: NSRect) {
        guard let posValue: AXValue = attribute(popover, kAXPositionAttribute),
              let sizeValue: AXValue = attribute(popover, kAXSizeAttribute) else { return }
        var pos = CGPoint.zero, size = CGSize.zero
        AXValueGetValue(posValue, .cgPoint, &pos)
        AXValueGetValue(sizeValue, .cgSize, &size)
        let screen = NSScreen.screens.first { $0.frame.intersects(iconRect) } ?? NSScreen.main
        let frame = screen?.frame ?? .zero
        // 高度保持系统给的位置（紧贴菜单栏），水平方向对准托盘图标
        var target = CGPoint(x: iconRect.midX - size.width / 2, y: pos.y)
        target.x = min(max(target.x, frame.minX + 6), frame.maxX - size.width - 6)
        if let value = AXValueCreate(.cgPoint, &target) {
            AXUIElementSetAttributeValue(popover, kAXPositionAttribute as CFString, value)
        }
    }

    // MARK: - 辅助

    private static func child(of element: AXUIElement, role: String) -> AXUIElement? {
        let children: [AXUIElement] = attribute(element, kAXChildrenAttribute) ?? []
        return children.first { (attribute($0, kAXRoleAttribute) as String?) == role }
    }

    private static func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? T
    }
}
