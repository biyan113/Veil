import AppKit
import ServiceManagement

enum IconStyle: String, CaseIterable {
    case chevron, eye, dot, lines

    var title: String {
        switch self {
        case .chevron: "箭头"
        case .eye: "眼睛"
        case .dot: "圆点"
        case .lines: "线条"
        }
    }

    func image(expanded: Bool) -> NSImage? {
        let name: String
        switch self {
        case .chevron: name = expanded ? "chevron.right" : "chevron.left"
        case .eye: name = expanded ? "eye" : "eye.slash"
        case .dot: name = expanded ? "circle" : "circle.fill"
        case .lines: name = expanded ? "line.3.horizontal" : "line.3.horizontal.decrease"
        }
        let config = NSImage.SymbolConfiguration(pointSize: self == .dot ? 9 : 13, weight: .semibold)
        let image = NSImage(systemSymbolName: name, accessibilityDescription: expanded ? "收起 Veil" : "打开 Veil")?
            .withSymbolConfiguration(config)
        image?.isTemplate = true
        return image
    }
}

struct HotKey: Equatable {
    var keyCode: UInt32
    var modifiers: UInt32   // Carbon 修饰键
    var display: String
}

final class Preferences {
    static let shared = Preferences()
    static let didChange = Notification.Name("VeilPreferencesDidChange")

    private let defaults = UserDefaults.standard

    private init() {
        defaults.register(defaults: [
            "scrollToToggle": true,
            "iconStyle": IconStyle.chevron.rawValue,
            // 默认 ⌥⌘B
            "hotKeyCode": 11,
            "hotKeyModifiers": 2304,
            "hotKeyDisplay": "⌥⌘B",
            "showTrayHint": true,
        ])
    }

    private func set(_ value: Any?, _ key: String) {
        defaults.set(value, forKey: key)
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }

    var scrollToToggle: Bool {
        get { defaults.bool(forKey: "scrollToToggle") }
        set { set(newValue, "scrollToToggle") }
    }
    var iconStyle: IconStyle {
        get { IconStyle(rawValue: defaults.string(forKey: "iconStyle") ?? "") ?? .chevron }
        set { set(newValue.rawValue, "iconStyle") }
    }
    var hasLaunchedBefore: Bool {
        get { defaults.bool(forKey: "hasLaunchedBefore") }
        set { defaults.set(newValue, forKey: "hasLaunchedBefore") }
    }

    /// 托盘底部的操作说明。点过叉之后不再出现。
    var showTrayHint: Bool {
        get { defaults.bool(forKey: "showTrayHint") }
        set { defaults.set(newValue, forKey: "showTrayHint") }
    }

    var hotKey: HotKey? {
        get {
            let code = defaults.integer(forKey: "hotKeyCode")
            guard code >= 0 else { return nil }
            return HotKey(keyCode: UInt32(code),
                          modifiers: UInt32(defaults.integer(forKey: "hotKeyModifiers")),
                          display: defaults.string(forKey: "hotKeyDisplay") ?? "")
        }
        set {
            defaults.set(newValue.map { Int($0.keyCode) } ?? -1, forKey: "hotKeyCode")
            defaults.set(newValue.map { Int($0.modifiers) } ?? 0, forKey: "hotKeyModifiers")
            set(newValue?.display ?? "", "hotKeyDisplay")
        }
    }

    var launchAtLogin: Bool { SMAppService.mainApp.status == .enabled }

    /// 失败时抛出 SMAppService 的错误，由界面展示原因
    func setLaunchAtLogin(_ enabled: Bool) throws {
        if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
    }

    /// 已登记但还要用户在系统设置里放行
    var launchAtLoginNeedsApproval: Bool { SMAppService.mainApp.status == .requiresApproval }

    /// 不在「应用程序」文件夹里运行时，系统通常不允许登记为登录项
    var isInApplicationsFolder: Bool {
        let path = Bundle.main.bundleURL.resolvingSymlinksInPath().path
        return path.hasPrefix("/Applications/") || path.hasPrefix(NSHomeDirectory() + "/Applications/")
    }
}
