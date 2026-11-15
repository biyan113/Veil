import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBar: MenuBarController!
    private var settings: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMainMenu()
        MenuBarItemScanner.configureTimeout()
        menuBar = MenuBarController()
        // 从托盘 / Veil 图标进设置都是为了整理图标或授权，落在「布局」页
        menuBar.onOpenSettings = { [weak self] in self?.showSettings(tab: .layout) }

        HotKeyCenter.shared.action = { [weak self] in self?.menuBar.toggle(trigger: .hotKey) }
        registerHotKey()
        NotificationCenter.default.addObserver(forName: Preferences.didChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.registerHotKey() }
        }

        if !Preferences.shared.hasLaunchedBefore {
            Preferences.shared.hasLaunchedBefore = true
            // 「布局」页顶部就是权限引导
            showSettings(tab: .layout)
        }
        if ProcessInfo.processInfo.environment["VEIL_SNAPSHOT"] != nil {
            showSettings()
            DebugSnapshot.runIfRequested(settings: settings)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    private func registerHotKey() {
        let p = Preferences.shared
        if let key = p.hotKey { HotKeyCenter.shared.register(key) } else { HotKeyCenter.shared.unregister() }
    }

    /// tab 为 nil 时停在上次的页面
    func showSettings(tab: SettingsTab? = nil) {
        if settings == nil { settings = SettingsWindowController(menuBar: menuBar) }
        NSApp.activate()
        if let tab { settings?.select(tab) }
        settings?.showWindow(nil)
        settings?.window?.makeKeyAndOrderFront(nil)
    }

    /// 后台应用也需要一个主菜单，设置窗口里的 ⌘W / ⌘Q / 复制粘贴才能工作
    private func installMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "关于 Veil", action: #selector(showAboutFromMenu), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "设置…", action: #selector(showSettingsFromMenu), keyEquivalent: ",")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出 Veil", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "编辑")
        edit.addItem(withTitle: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)

        let windowItem = NSMenuItem()
        let window = NSMenu(title: "窗口")
        window.addItem(withTitle: "关闭", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowItem.submenu = window
        main.addItem(windowItem)
        NSApp.mainMenu = main
    }

    @objc private func showSettingsFromMenu() { showSettings() }
    @objc private func showAboutFromMenu() { showSettings(tab: .about) }
}
