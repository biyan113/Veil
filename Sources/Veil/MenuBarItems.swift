import AppKit

struct MenuBarItem: Hashable {
    let pid: pid_t
    let appName: String
    let bundleID: String?
    let title: String
    let frame: CGRect          // CG 全局坐标
    var element: AXUIElement? = nil
    /// 跨重启稳定的标识：应用 + 名称 + 同名序号（进程号每次启动都会变）
    var key: String = ""

    /// 键里「|」之前的部分，标识图标属于哪个应用
    static func owner(ofKey key: String) -> String { String(key.prefix { $0 != "|" }) }

    /// 收进了 Veil、但现在不在菜单栏上的条目（应用没运行等）：只有键，没有可操作的元素
    var isMissing: Bool { element == nil }

    /// 后台常驻应用的 NSRunningApplication.icon 常是通用占位图，从应用包取更可靠
    var appIcon: NSImage {
        let app = pid == 0 ? nil : NSRunningApplication(processIdentifier: pid)
        let url = app?.bundleURL ?? bundleID.flatMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
        if let url { return NSWorkspace.shared.icon(forFile: url.path) }
        return app?.icon ?? NSWorkspace.shared.icon(for: .applicationBundle)
    }

    var displayName: String {
        title.isEmpty || title == appName ? appName : title
    }
    var detail: String? {
        if isSystem { return "系统" }
        return title.isEmpty || title == appName ? nil : appName
    }

    var isSystem: Bool { ["com.apple.MenuBarAgent", "com.apple.controlcenter", "com.apple.systemuiserver", "com.apple.TextInputMenuAgent"].contains(bundleID ?? "") }

    /// macOS 自带的「显示隐藏菜单栏项目」按钮（«），在托盘里没有意义
    var isSystemOverflowButton: Bool {
        isSystem && (title.contains("隐藏菜单栏项目") || title.localizedCaseInsensitiveContains("hidden menu bar"))
    }

    static func ==(a: Self, b: Self) -> Bool { a.key == b.key }
    func hash(into h: inout Hasher) { h.combine(key) }
}

extension MenuBarItem {
    /// 所属应用是否在运行：按键里记的 bundleID 或应用名判断，和 scan 生成键的规则一致
    var isOwnerRunning: Bool {
        let owner = Self.owner(ofKey: key)
        return NSWorkspace.shared.runningApplications.contains { ($0.bundleIdentifier ?? $0.localizedName) == owner }
    }

    /// 按存下的键还原一个占位条目，键的格式见 scan：「bundleID或应用名|标题#序号」
    init(missingKey key: String) {
        let owner = Self.owner(ofKey: key)
        var title = String(key.dropFirst(owner.count + 1))
        // 只剥结尾的「#数字」，标题里本身的 # 保留
        if let hash = title.lastIndex(of: "#"), !title[title.index(after: hash)...].isEmpty,
           title[title.index(after: hash)...].allSatisfy(\.isNumber) {
            title = String(title[..<hash])
        }
        let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: owner)
        let appName = appURL.map { FileManager.default.displayName(atPath: $0.path) }
            .map { $0.hasSuffix(".app") ? String($0.dropLast(4)) : $0 } ?? owner
        self.init(pid: 0, appName: appName, bundleID: appURL == nil ? nil : owner, title: title, frame: .zero)
        self.key = key
    }
}

/// 通过辅助功能 API 的 AXExtrasMenuBar 枚举所有应用的菜单栏图标。
/// macOS 26 之后 CGWindowList 已拿不到状态栏窗口，这是目前最可靠的方式。
enum MenuBarItemScanner {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func requestTrust() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    /// 目标应用卡死时，辅助功能调用默认要等 6 秒。这里把全局上限压到 1 秒，主线程最多卡这么久。
    static func configureTimeout() {
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 1)
    }

    /// owners 不为空时只问这些应用：系统上有上百个进程，打开托盘只需要收藏所属的几个
    static func scan(owners: Set<String>? = nil) async -> [MenuBarItem] {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.processIdentifier != ownPID }
            .map { ($0.processIdentifier, $0.localizedName ?? $0.bundleIdentifier ?? "未知应用", $0.bundleIdentifier) }
            .filter { owners?.contains($0.2 ?? $0.1) ?? true }

        return await withTaskGroup(of: [MenuBarItem].self) { group in
            for (pid, name, bundle) in apps {
                group.addTask { items(pid: pid, appName: name, bundleID: bundle) }
            }
            var all: [MenuBarItem] = []
            for await chunk in group { all += chunk }
            all.sort { $0.frame.minX > $1.frame.minX }
            var seen: [String: Int] = [:]
            for i in all.indices {
                let base = "\(all[i].bundleID ?? all[i].appName)|\(all[i].title)"
                let n = seen[base, default: 0]
                seen[base] = n + 1
                all[i].key = n == 0 ? base : "\(base)#\(n)"
            }
            return all
        }
    }

    private static func items(pid: pid_t, appName: String, bundleID: String?) -> [MenuBarItem] {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.25)
        guard let bar: AXUIElement = attribute(app, "AXExtrasMenuBar"),
              let children: [AXUIElement] = attribute(bar, kAXChildrenAttribute) else { return [] }

        return children.compactMap { element in
            guard let posValue: AXValue = attribute(element, kAXPositionAttribute),
                  let sizeValue: AXValue = attribute(element, kAXSizeAttribute) else { return nil }
            var pos = CGPoint.zero, size = CGSize.zero
            AXValueGetValue(posValue, .cgPoint, &pos)
            AXValueGetValue(sizeValue, .cgSize, &size)
            guard size.width > 0 else { return nil }
            let title: String = attribute(element, kAXTitleAttribute)
                ?? attribute(element, kAXDescriptionAttribute)
                ?? childDescription(element).map(stableName)
                ?? attribute(element, kAXHelpAttribute)
                ?? ""
            return MenuBarItem(pid: pid, appName: appName, bundleID: bundleID,
                               title: title, frame: CGRect(origin: pos, size: size), element: element)
        }
    }

    /// 系统图标（时钟、Wi‑Fi…）的名字在第一个子元素的描述里
    private static func childDescription(_ element: AXUIElement) -> String? {
        guard let children: [AXUIElement] = attribute(element, kAXChildrenAttribute) else { return nil }
        return children.lazy.compactMap { attribute($0, kAXDescriptionAttribute) as String? }.first
    }

    /// 「Wi‑Fi，已接入，3格」→「Wi‑Fi」：去掉会变化的状态部分
    private static func stableName(_ s: String) -> String {
        String(s.split(whereSeparator: { "，,".contains($0) }).first ?? Substring(s))
            .trimmingCharacters(in: .whitespaces)
    }

    private static func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        if T.self == String.self, let s = value as? String, s.isEmpty { return nil }
        return value as? T
    }

    /// 触发图标或菜单项的点按。不等结果：弹出菜单或模态窗时，这个调用要等到超时才返回
    static func press(_ element: AXUIElement) {
        Task.detached { _ = AXUIElementPerformAction(element, kAXPressAction as CFString) }
    }
}
